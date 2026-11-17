# DriveTrack 国内 CDN 上传脚本（CloudBase 存储 / 腾讯云 COS）
#
# 用途：把 release APK 上传到 CloudBase 存储，得到国内直连地址，
# 再（可选）写入 update-manifest.json 并刷新 jsDelivr 缓存。
# 零依赖：只用 PowerShell 5.1 + .NET，不需要 node / tcb CLI。
#
# 首次使用只需要一份凭据（放在用户目录，绝不进仓库）：
#   %USERPROFILE%\.local\share\drive-track\secrets\.tencentcloud
#       第一行 SecretId，第二行 SecretKey（腾讯云控制台 → 访问管理 → API 密钥）
#   然后先跑一次 -Discover 列出账号下的存储桶，会自动识别 CloudBase 的桶
#   并写入同目录的 .cos-config（也可手动填 bucket=... / region=...）。
#
# 用法：
#   powershell -File tools/upload_cdn.ps1 -Discover          # 列桶并写配置
#   powershell -File tools/upload_cdn.ps1 -DryRun            # 只检查配置与签名
#   powershell -File tools/upload_cdn.ps1                    # 上传三包，打印 CDN 地址
#   powershell -File tools/upload_cdn.ps1 -WriteManifest     # 上传并写回清单
#   powershell -File tools/upload_cdn.ps1 -WriteManifest -Purge   # 再刷新 jsDelivr
#
# 说明：
# - 上传时带 x-cos-acl: public-read，对象本身公开可读；若桶策略禁止
#   公共读，脚本会在 HEAD 校验阶段报 403 并给出去控制台改权限的提示。
# - 上传后逐个 HEAD 校验 200 才返回成功，不把没验证的地址写进清单。
# - -WriteManifest 会把每个 apks.<abi>.cdnUrl 写上，并把顶层 apkUrl
#   （旧客户端唯一读取的字段）指向 arm64 的 CDN 地址，GitHub Release
#   地址原样保留在 apks.<abi>.url 作为兜底。

param(
  [string]$Version = "",
  [string]$Bucket = "",
  [string]$Region = "",
  [string]$Prefix = "apk",
  [string]$CdnDomain = "",
  [switch]$Discover,
  [switch]$WriteManifest,
  [switch]$Purge,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
if (!(Test-Path (Join-Path $root "pubspec.yaml"))) {
  $root = "F:\DriveTrack-src\_release_156"
}
$secDir = Join-Path $HOME ".local\share\drive-track\secrets"
$cfgFile = Join-Path $secDir ".cos-config"

function Fail($msg) {
  Write-Host "错误：$msg" -ForegroundColor Red
  exit 1
}

function Read-EffectiveLines($path) {
  $lines = Get-Content $path | Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") }
  if (!$lines) { return @() }
  return $lines
}

# ---- COS V5 签名 ----
function Get-HmacSha1Hex([string]$key, [string]$data) {
  $h = [System.Security.Cryptography.HMACSHA1]::Create()
  try {
    $h.Key = [System.Text.Encoding]::UTF8.GetBytes($key)
    $bytes = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))
    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $h.Dispose()
  }
}

function Get-Sha1Hex([string]$data) {
  $s = [System.Security.Cryptography.SHA1]::Create()
  try {
    $bytes = $s.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))
    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $s.Dispose()
  }
}

function New-CosAuthorization([string]$method, [string]$uriPath, [string]$canonicalHeaders, [string]$signedHeaderNames) {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $keyTime = "$($now - 60);$($now + 3600)"
  $signKey = Get-HmacSha1Hex $secretKey $keyTime
  $httpString = "$($method.ToLower())`n$uriPath`n`n$canonicalHeaders`n"
  $stringToSign = "sha1`n$keyTime`n" + (Get-Sha1Hex $httpString) + "`n"
  $sig = Get-HmacSha1Hex $signKey $stringToSign
  return "q-sign-algorithm=sha1&q-ak=$secretId&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=$signedHeaderNames&q-url-param-list=&q-signature=$sig"
}

# ---- 凭据 ----
$credFile = Join-Path $secDir ".tencentcloud"
if (!(Test-Path $credFile)) {
  Fail "缺少 $credFile`n请在腾讯云控制台创建 API 密钥（访问管理 → 密钥管理 → API 密钥管理），`n把 SecretId 写在第一行、SecretKey 写在第二行。"
}
$secretId = ""
$secretKey = ""
$credRaw = @(Get-Content $credFile)

# 优先按显式键名读：SecretId=... / SecretKey=...（允许行首 # 与空格）
foreach ($line in $credRaw) {
  $t = ($line -replace '^[#\s]+', '').Trim()
  if ($t -match '^(?i)SecretId\s*=\s*(.+)$') { $secretId = $Matches[1].Trim() }
  if ($t -match '^(?i)SecretKey\s*=\s*(.+)$') { $secretKey = $Matches[1].Trim() }
}

# 否则按 AKID 特征定位 SecretId，取其后第一段 16 位以上纯字母数字作为 SecretKey，
# 这样即使密钥被写成 # 注释行也能识别。
if (!$secretId -or !$secretKey) {
  for ($i = 0; $i -lt $credRaw.Count; $i++) {
    $m = [regex]::Match($credRaw[$i], 'AKID[0-9A-Za-z]{8,}')
    if (!$m.Success) { continue }
    $secretId = $m.Value
    for ($j = $i + 1; $j -lt $credRaw.Count; $j++) {
      $cand = ($credRaw[$j] -replace '^[#\s]+', '').Trim()
      if ($cand -match '^[0-9A-Za-z]{16,}$') { $secretKey = $cand; break }
    }
    break
  }
}

# 最终回退：文件前两行有效内容
if (!$secretId -or !$secretKey) {
  $cred = Read-EffectiveLines $credFile
  if ($cred.Count -ge 2) {
    $secretId = $cred[0].Trim()
    $secretKey = $cred[1].Trim()
  }
}

if ($secretId.Length -lt 10 -or $secretKey.Length -lt 10) {
  Fail "凭据文件里没找到可用的 SecretId / SecretKey。`n支持两种写法：`n  SecretId=AKID...`n  SecretKey=...`n或第一行 SecretId、第二行 SecretKey（不要加 # 前缀）。"
}

# ---- 列桶并写配置 ----
if ($Discover) {
  $serviceHost = "service.cos.myqcloud.com"
  $auth = New-CosAuthorization "get" "/" "host=$serviceHost" "host"
  try {
    $resp = Invoke-WebRequest -Uri "https://$serviceHost/" -Headers @{ Authorization = $auth } -UseBasicParsing -TimeoutSec 60
  } catch {
    $detail = ""
    try {
      $webResp = $_.Exception.Response
      if ($webResp) {
        $reader = New-Object System.IO.StreamReader($webResp.GetResponseStream())
        $detail = $reader.ReadToEnd()
        $reader.Dispose()
      }
    } catch { }
    Write-Host "COS 返回：$(($detail -replace '\s+', ' ').Trim())" -ForegroundColor DarkYellow
    Fail "列桶失败：$($_.Exception.Message)`nCode=AccessDenied 说明密钥有效但无 ListBuckets 权限（可直接跳过 -Discover，`n把控制台里的 bucket / region 写进 .cos-config）；`nCode=SignatureDoesNotMatch / InvalidAccessKeyId 说明密钥无效或复制不完整。"
  }
  [xml]$xml = $resp.Content
  $buckets = @($xml.ListAllMyBucketsResult.Buckets.Bucket)
  if ($buckets.Count -eq 0) { Fail "账号下没有存储桶。" }
  Write-Host "账号下的存储桶：" -ForegroundColor Cyan
  foreach ($b in $buckets) {
    Write-Host ("  {0}  region={1}" -f $b.Name, $b.Location)
  }
  $own = $buckets | Where-Object { $_.Name -like "*drive*" } | Select-Object -First 1
  if (!$own) { $own = $buckets | Select-Object -First 1 }
  $cfg = "bucket=$($own.Name)`nregion=$($own.Location)`n"
  [System.IO.File]::WriteAllText($cfgFile, $cfg, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ""
  Write-Host "已写入 $cfgFile ：bucket=$($own.Name) region=$($own.Location)" -ForegroundColor Green
  Write-Host "若不是 CloudBase 环境的桶，请改这两行后重跑。" -ForegroundColor Yellow
  exit 0
}

# ---- 版本号 ----
if (!$Version) {
  $m = Select-String -Path (Join-Path $root "pubspec.yaml") -Pattern '^version:\s*([0-9.]+)\+' | Select-Object -First 1
  if (!$m) { Fail "读不到 pubspec.yaml 里的 version" }
  $Version = $m.Matches[0].Groups[1].Value
}

# ---- 存储桶配置 ----
$cfg = @{}
if (Test-Path $cfgFile) {
  foreach ($line in Read-EffectiveLines $cfgFile) {
    $i = $line.IndexOf("=")
    if ($i -gt 0) {
      $cfg[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim()
    }
  }
}
if (!$Bucket -and $cfg["bucket"]) { $Bucket = $cfg["bucket"] }
if (!$Region -and $cfg["region"]) { $Region = $cfg["region"] }
if (!$CdnDomain -and $cfg["cdndomain"]) { $CdnDomain = $cfg["cdndomain"] }
if (!$Bucket -or !$Region) {
  Fail "缺少存储桶配置。先运行 -Discover 自动识别，`n或手动把 bucket=... / region=... 写入 $cfgFile。"
}

$hostName = "$Bucket.cos.$Region.myqcloud.com"
$publicBase = if ($CdnDomain) { "https://$CdnDomain" } else { "https://$hostName" }
Write-Host "环境：$Bucket / $Region / 版本 $Version" -ForegroundColor Cyan
if ($CdnDomain) { Write-Host "对外域名：$publicBase（CDN）" -ForegroundColor Cyan }

# ---- 上传 ----
function Send-CosObject([string]$localPath, [string]$objectKey, [string]$contentType = "application/vnd.android.package-archive") {
  $uriPath = "/" + $objectKey
  $uri = "https://$hostName$uriPath"
  $canonicalHeaders = "host=$hostName&x-cos-acl=public-read"
  $auth = New-CosAuthorization "put" $uriPath $canonicalHeaders "host;x-cos-acl"

  [System.Net.ServicePointManager]::Expect100Continue = $false
  $req = [System.Net.HttpWebRequest]::Create($uri)
  $req.Method = "PUT"
  $req.ContentType = $contentType
  $req.Timeout = 1800000
  $req.ReadWriteTimeout = 1800000
  $req.AllowWriteStreamBuffering = $false
  [void]$req.Headers.Add("Authorization", $auth)
  [void]$req.Headers.Add("x-cos-acl", "public-read")
  $req.ContentLength = (Get-Item $localPath).Length

  $fs = [System.IO.File]::OpenRead($localPath)
  try {
    $body = $req.GetRequestStream()
    try { $fs.CopyTo($body, 1048576) } finally { $body.Dispose() }
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
    Write-Host "  上传成功 HTTP $code" -ForegroundColor Green
    # 返回对外地址（配了 CDN 域名就用 CDN，否则回落到 COS 源站）。
    return "$publicBase$uriPath"
  } catch [System.Net.WebException] {
    $msg = $_.Exception.Message
    $detail = ""
    try {
      $r = $_.Exception.Response
      $rd = New-Object System.IO.StreamReader($r.GetResponseStream())
      $detail = $rd.ReadToEnd()
      $rd.Dispose()
    } catch { }
    Write-Host "  上传失败：$msg" -ForegroundColor Red
    if ($detail) { Write-Host "  $($detail -replace '\s+', ' ')" -ForegroundColor DarkGray }
    if ($msg -match '403') {
      Write-Host "  403 通常是桶策略不允许公共读，或密钥无该桶写权限。" -ForegroundColor Yellow
    }
    return $null
  } finally {
    $fs.Dispose()
  }
}

function Test-Url([string]$url) {
  try {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = "HEAD"
    $req.Timeout = 30000
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
    return $code
  } catch {
    return 0
  }
}

# ---- 主流程 ----
$abis = @("arm64-v8a", "armeabi-v7a", "x86_64")
$results = @{}

foreach ($abi in $abis) {
  $name = "DriveTrack-v$Version-release-$abi.apk"
  $path = Join-Path $root $name
  if (!(Test-Path $path)) { Fail "找不到 $name，请先构建并把包放到工程根目录。" }
  $sizeMb = [math]::Round((Get-Item $path).Length / 1MB, 1)
  $key = "$Prefix/$Version/$name"
  $url = "$publicBase/$key"
  Write-Host "[$abi] $name ($sizeMb MB) -> $key"

  if ($DryRun) {
    $auth = New-CosAuthorization "put" "/$key" "host=$hostName&x-cos-acl=public-read" "host;x-cos-acl"
    if ($auth -match "q-signature=[0-9a-f]{40}") {
      Write-Host "  签名自检通过（未上传）" -ForegroundColor Green
    } else {
      Fail "签名自检失败"
    }
    continue
  }

  $uploaded = Send-CosObject $path $key
  if (!$uploaded) { Fail "$abi 上传失败，清单未改动。" }
  $results[$abi] = $uploaded
}

if ($DryRun) {
  Write-Host "DryRun 完成：配置与签名正常。" -ForegroundColor Cyan
  exit 0
}

# ---- 公网可达校验 ----
Write-Host "校验公网可达性..." -ForegroundColor Cyan
foreach ($abi in $abis) {
  $code = Test-Url $results[$abi]
  if ($code -ne 200) {
    Fail "$abi 地址返回 $code（期望 200）。请到云开发控制台确认存储桶为公共读，或检查桶策略。"
  }
  Write-Host "  $abi 200 OK" -ForegroundColor Green
}

# ---- 写回清单 ----
if ($WriteManifest) {
  $manifestPath = Join-Path $root "update-manifest.json"
  # 清单含中文 notes：必须按 UTF-8 读，PS 5.1 默认 ANSI 会把中文读成乱码并让 ConvertFrom-Json 失败。
  $raw = Get-Content $manifestPath -Raw -Encoding UTF8
  $mf = $raw | ConvertFrom-Json

  if ($mf.versionName -ne $Version) {
    Fail "清单版本 $($mf.versionName) 与上传版本 $Version 不一致，先更新清单版本号。"
  }
  foreach ($abi in $abis) {
    if (!$mf.apks.PSObject.Properties[$abi]) {
      $mf.apks | Add-Member -NotePropertyName $abi -NotePropertyValue ([pscustomobject]@{ url = $results[$abi]; sha256 = "" })
    }
    $mf.apks.$abi | Add-Member -NotePropertyName cdnUrl -NotePropertyValue $results[$abi] -Force
  }
  # 旧客户端只读顶层 apkUrl：指向 arm64 的国内地址，GitHub 地址留在 apks.url 兜底。
  $mf.apkUrl = $results["arm64-v8a"]

  $json = $mf | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "已写回 update-manifest.json（apkUrl → 国内 CDN，GitHub 保留在 apks.url）" -ForegroundColor Green

  # v1.6.4：清单同时放到存储桶根，App 检查更新优先读这里
  # （https://<bucket>.tcb.qcloud.la/update-manifest.json），国内直连最稳。
  $mfUrl = Send-CosObject $manifestPath "update-manifest.json" "application/json"
  if (!$mfUrl) { Fail "清单上传失败，App 将无法通过 CloudBase 检查更新。" }
  $mfCode = Test-Url $mfUrl
  if ($mfCode -ne 200) { Fail "清单地址返回 $mfCode（期望 200）。" }
  Write-Host "清单已上传：$mfUrl" -ForegroundColor Green
}

# ---- 刷新 jsDelivr ----
if ($Purge) {
  try {
    $r = Invoke-RestMethod "https://purge.jsdelivr.net/gh/Toryphoto77/drive-track@main/update-manifest.json" -TimeoutSec 60
    Write-Host "jsDelivr 刷新：$($r.status)" -ForegroundColor Green
  } catch {
    Write-Host "jsDelivr 刷新失败：$($_.Exception.Message)" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "完成，CDN 地址：" -ForegroundColor Cyan
foreach ($abi in $abis) { Write-Host "  $abi  $($results[$abi])" }
Write-Host ""
Write-Host "提示：清单改动需要用 gh api 提交到 main（git 直连常被重置），例如：" -ForegroundColor DarkGray
Write-Host "  gh api repos/Toryphoto77/drive-track/contents/update-manifest.json -X PUT --input body.json" -ForegroundColor DarkGray
