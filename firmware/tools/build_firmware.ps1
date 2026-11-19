# DriveTrack V4.6 固件一键编译脚本（Windows PowerShell）
#
# 前置条件（只需装一次）：
#   1. 安装 ESP-IDF v5.3.x（官方离线安装包 idf-installer 即可）
#   2. 本脚本默认从 C:\Espressif\esp-idf 找 IDF，也可用 -IdfPath 指定
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\build_firmware.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build_firmware.ps1 -IdfPath D:\esp\esp-idf
#
# 产物：
#   build\drivetrack-box.bin              应用镜像（App OTA 用）
#   build\bootloader\bootloader.bin       引导程序（首次串口烧录用）
#   build\partition_table\partition-table.bin  分区表（首次串口烧录用）
param(
  [string]$IdfPath = '',
  [string]$Target  = 'esp32s3'
)

$ErrorActionPreference = 'Stop'
$firmwareDir = Split-Path -Parent $PSScriptRoot
Set-Location $firmwareDir

# 自动找常见的 ESP-IDF 安装位置，找不到再按提示让用户手动指定。
if ([string]::IsNullOrWhiteSpace($IdfPath)) {
  $candidates = @(
    'C:\Espressif53\frameworks\esp-idf-v5.3.5',
    'C:\Espressif\frameworks\esp-idf-v5.3.5',
    'C:\Espressif\esp-idf',
    (Join-Path $env:USERPROFILE 'esp\esp-idf')
  )
  $env:IDF_PATH | ForEach-Object { if ($_) { $candidates = @($_ ) + $candidates } }
  foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c 'export.ps1'))) { $IdfPath = $c; break }
  }
}

if (-not $IdfPath -or -not (Test-Path (Join-Path $IdfPath 'export.ps1'))) {
  throw "找不到 ESP-IDF（export.ps1）。请先安装 ESP-IDF v5.3.x，或用 -IdfPath 指定，例如 -IdfPath C:\Espressif53\frameworks\esp-idf-v5.3.5。"
}

Write-Host "[1/3] 加载 ESP-IDF 环境：$IdfPath" -ForegroundColor Cyan
. (Join-Path $IdfPath 'export.ps1')

Write-Host "[2/3] 设置目标芯片：$Target" -ForegroundColor Cyan
idf.py set-target $Target

Write-Host "[3/3] 编译固件…" -ForegroundColor Cyan
idf.py build
if ($LASTEXITCODE -ne 0) { throw "编译失败，请看上面的报错。" }

$appBin = Join-Path $firmwareDir 'build\drivetrack-box.bin'
if (-not (Test-Path $appBin)) { throw "编译结束但没找到 $appBin" }

$size = (Get-Item $appBin).Length
$sha  = (Get-FileHash $appBin -Algorithm SHA256).Hash.ToLower()
Write-Host ""
Write-Host "编译完成：$appBin" -ForegroundColor Green
Write-Host ("大小 {0} 字节  SHA256 {1}" -f $size, $sha)
