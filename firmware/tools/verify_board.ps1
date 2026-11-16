<#
DriveTrack V4.6 首板验证脚本（Windows PowerShell 5.1）

用法：
  powershell -ExecutionPolicy Bypass -File .\verify_board.ps1
  powershell -ExecutionPolicy Bypass -File .\verify_board.ps1 -Port COM5 -Seconds 60
  powershell -ExecutionPolicy Bypass -File .\verify_board.ps1 -ListPorts
  powershell -ExecutionPolicy Bypass -File .\verify_board.ps1 -SkipHttp
  powershell -ExecutionPolicy Bypass -File .\verify_board.ps1 -Replay C:\path\to\saved.log

它做三件事：
  1. 抓设备串口日志（115200），按固件里的关键日志判断各模块是否起来；
  2. 解析 dt_gnss / dt_imu 的周期性输出，确认传感器真的在出数；
  3. 尝试访问 http://192.168.4.1/api/info（电脑需先连上设备热点）。

退出码 0 表示必检项全过，1 表示有失败项。
#>
[CmdletBinding()]
param(
    [string]$Port,
    [int]$Seconds = 45,
    [string]$DeviceHost = "192.168.4.1",
    [string]$LogPath,
    [string]$Replay,
    [switch]$SkipHttp,
    [switch]$ListPorts
)

$ErrorActionPreference = "Stop"

function Write-Item {
    param($Ok, [string]$Name, [string]$Detail)
    if ($Ok -eq $true) {
        Write-Host ("[PASS] {0}  {1}" -f $Name, $Detail) -ForegroundColor Green
    } elseif ($Ok -eq $false) {
        Write-Host ("[FAIL] {0}  {1}" -f $Name, $Detail) -ForegroundColor Red
    } else {
        Write-Host ("[SKIP] {0}  {1}" -f $Name, $Detail) -ForegroundColor Yellow
    }
}

function Get-SerialPortName {
    $names = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($null -eq $names -or $names.Count -eq 0) {
        return $null
    }
    if ($names.Count -eq 1) {
        return $names[0]
    }
    Write-Host "检测到多个串口，请用 -Port 指定其中一个：" -ForegroundColor Yellow
    foreach ($n in $names) {
        Write-Host ("  {0}" -f $n)
    }
    return $null
}

# ---------------- 列出串口 ----------------
if ($ListPorts) {
    $names = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($null -eq $names -or $names.Count -eq 0) {
        Write-Host "没有检测到任何串口。请插好 USB-C 线，并确认设备已上电。" -ForegroundColor Red
    } else {
        Write-Host "可用串口："
        foreach ($n in $names) { Write-Host ("  {0}" -f $n) }
    }
    exit 0
}

# ---------------- 采集或回放 ----------------
if (-not [string]::IsNullOrWhiteSpace($Replay)) {
    if (-not (Test-Path -LiteralPath $Replay)) {
        Write-Host ("找不到日志文件：" + $Replay) -ForegroundColor Red
        exit 1
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Get-Content -LiteralPath $Replay -Encoding UTF8)) {
        $lines.Add($l)
    }
    $LogPath = $Replay
    Write-Host ("离线分析 {0}，共 {1} 行" -f $Replay, $lines.Count) -ForegroundColor Cyan
} else {

# ---------------- 开串口 ----------------
if ([string]::IsNullOrWhiteSpace($Port)) {
    $Port = Get-SerialPortName
}
if ([string]::IsNullOrWhiteSpace($Port)) {
    Write-Host "未选定串口。先运行 -ListPorts 看一下，再传 -Port COMx。" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $env:TEMP ("drivetrack-board-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

Write-Host ("串口 {0}，波特率 115200，抓取 {1} 秒" -f $Port, $Seconds) -ForegroundColor Cyan
Write-Host "3 秒后开始，请在这段时间内把设备断电再上电（拨一下自锁开关），或按复位。" -ForegroundColor Cyan
Start-Sleep -Seconds 3

$sp = New-Object System.IO.Ports.SerialPort
$sp.PortName = $Port
$sp.BaudRate = 115200
$sp.Parity = [System.IO.Ports.Parity]::None
$sp.DataBits = 8
$sp.StopBits = [System.IO.Ports.StopBits]::One
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.ReadTimeout = 300
$sp.Encoding = [System.Text.Encoding]::UTF8
$sp.DtrEnable = $false
$sp.RtsEnable = $false

try {
    $sp.Open()
} catch {
    Write-Host ("打不开串口 {0}：{1}" -f $Port, $_.Exception.Message) -ForegroundColor Red
    Write-Host "常见原因：串口被 Arduino/串口助手/另一个 idf.py monitor 占用，或驱动没装。" -ForegroundColor Yellow
    exit 1
}

$lines = New-Object System.Collections.Generic.List[string]
$buffer = ""
$watch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($watch.Elapsed.TotalSeconds -lt $Seconds) {
        Start-Sleep -Milliseconds 100
        $chunk = ""
        try {
            $chunk = $sp.ReadExisting()
        } catch {
            break
        }
        if ([string]::IsNullOrEmpty($chunk)) {
            continue
        }
        $buffer += $chunk
        while ($true) {
            $idx = $buffer.IndexOf("`n")
            if ($idx -lt 0) { break }
            $line = $buffer.Substring(0, $idx).TrimEnd("`r")
            $buffer = $buffer.Substring($idx + 1)
            if ($line.Length -gt 0) {
                $lines.Add($line)
                Write-Host $line
            }
        }
        # 长时间没有换行时防止缓冲区无限增长（多半是波特率不对）
        if ($buffer.Length -gt 8192) {
            $buffer = $buffer.Substring($buffer.Length - 4096)
        }
    }
} finally {
    try { $sp.Close() } catch { }
    try { $sp.Dispose() } catch { }
}

$lines | Out-File -FilePath $LogPath -Encoding UTF8

}

$text = ($lines -join "`n")
function Has-Pattern {
    param([string]$Pattern)
    return [regex]::IsMatch($text, $Pattern)
}

$failCount = 0
$passCount = 0
function Count-Result {
    param($Ok)
    if ($Ok -eq $true) { $script:passCount++ }
    elseif ($Ok -eq $false) { $script:failCount++ }
}

Write-Host ""
Write-Host "================ 检查结果 ================" -ForegroundColor Cyan

# 1. 固件启动
$ok = Has-Pattern 'DriveTrack V4\.6 fw='
Count-Result $ok
Write-Item $ok "固件启动" $(if ($ok) { "看到启动横幅" } else { "没看到 'DriveTrack V4.6 fw='，串口/供电/烧录有问题" })

# 2. 电源与指示灯任务
$ok = Has-Pattern '电源监控已启动'
Count-Result $ok
Write-Item $ok "电源监控" $(if ($ok) { "ADC 与灯控任务已启动" } else { "没看到 '电源监控已启动'，检查 IO1 分压与 IO7/IO2" })

# 3. WiFi 热点
$ok = Has-Pattern '热点已开：DriveTrack-'
Count-Result $ok
Write-Item $ok "WiFi 热点" $(if ($ok) { "AP 已开" } else { "没看到热点日志" })

# 4. HTTP OTA 服务
$ok = Has-Pattern 'OTA 服务已就绪'
Count-Result $ok
Write-Item $ok "HTTP OTA 服务" $(if ($ok) { "192.168.4.1:80 已监听" } else { "HTTP 服务未就绪" })

# 5. BLE
$ok = Has-Pattern 'BLE 已启动，名称'
Count-Result $ok
Write-Item $ok "BLE 广播" $(if ($ok) { "NimBLE 已启动" } else { "BLE 没起来，检查 sdkconfig 的 NimBLE 配置" })

# 6. GNSS 波特率探测
$m = [regex]::Match($text, 'GNSS 波特率探测命中 (\d+) bps')
if ($m.Success) {
    Count-Result $true
    Write-Item $true "GNSS 波特率" ("命中 " + $m.Groups[1].Value + " bps")
} else {
    $ok = Has-Pattern 'GNSS 已启动'
    if ($ok) {
        Count-Result $false
        Write-Item $false "GNSS 波特率" "没探测到 NMEA（模块没供电/没接天线/波特率不在候选里）"
    } else {
        Count-Result $false
        Write-Item $false "GNSS 波特率" "GNSS 任务未启动"
    }
}

# 7. GNSS 实际出数
$gpsMatches = [regex]::Matches($text, 'fix=(\d) sats=(\d+) lat=([-\d.]+) lon=([-\d.]+)')
if ($gpsMatches.Count -gt 0) {
    $last = $gpsMatches[$gpsMatches.Count - 1]
    $fix = $last.Groups[1].Value
    $sats = [int]$last.Groups[2].Value
    $lat = $last.Groups[3].Value
    $lon = $last.Groups[4].Value
    if ($sats -gt 0) {
        Count-Result $true
        Write-Item $true "GNSS 数据" ("sats=" + $sats + " fix=" + $fix + " lat=" + $lat + " lon=" + $lon)
    } else {
        Count-Result $false
        Write-Item $false "GNSS 数据" ("sats=0（能收句子但没星，检查天线/是否在室内）")
    }
} else {
    Count-Result $false
    Write-Item $false "GNSS 数据" "没有 NMEA 解析输出"
}

# 8. IMU 初始化
$ok = Has-Pattern 'BMI088 已启动'
Count-Result $ok
Write-Item $ok "IMU 初始化" $(if ($ok) { "BMI088 双片选识别成功" } else { "BMI088 没起来，检查 SPI 引脚与 3V3" })

# 9. IMU 出数（重力模长应接近 1 g）
$imuMatches = [regex]::Matches($text, 'a=\(([-\d.]+),([-\d.]+),([-\d.]+)\)g')
if ($imuMatches.Count -gt 0) {
    $last = $imuMatches[$imuMatches.Count - 1]
    $ax = [double]$last.Groups[1].Value
    $ay = [double]$last.Groups[2].Value
    $az = [double]$last.Groups[3].Value
    $mag = [math]::Sqrt($ax * $ax + $ay * $ay + $az * $az)
    if ($mag -ge 0.5 -and $mag -le 1.5) {
        Count-Result $true
        Write-Item $true "IMU 数据" ("|a|=" + [math]::Round($mag, 2) + " g，数值合理")
    } else {
        Count-Result $false
        Write-Item $false "IMU 数据" ("|a|=" + [math]::Round($mag, 2) + " g，偏离 1 g（量程/坐标轴/焊接异常）")
    }
} else {
    Count-Result $false
    Write-Item $false "IMU 数据" "没有 IMU 周期输出"
}

# 10. 致命错误
$bad = 'Guru Meditation|assert failed|abort\(\)|Brownout detector|rst:0x[0-9a-fA-F]+ \('
$ok = -not (Has-Pattern $bad)
Count-Result $ok
Write-Item $ok "崩溃/复位" $(if ($ok) { "未见 panic、断言或欠压复位" } else { "日志里有崩溃或欠压记录，先解决再往下做" })

# 11. 模块级错误
$modErr = 'IMU 未就绪|加速度计 ID=|陀螺仪 ID=|SPIFFS 挂载失败|缓存已满'
$ok = -not (Has-Pattern $modErr)
Count-Result $ok
Write-Item $ok "模块错误" $(if ($ok) { "未见模块级错误" } else { "有模块报错，往上翻日志看具体是哪一项" })

# 12. HTTP /api/info（需要电脑先连设备热点）
if ($SkipHttp) {
    Write-Item $null "HTTP /api/info" "已按要求跳过"
} else {
    $url = "http://" + $DeviceHost + "/api/info"
    try {
        $info = Invoke-RestMethod -Uri $url -TimeoutSec 6
        $model = [string]$info.model
        $board = [string]$info.board
        $fw = [string]$info.fw
        $build = [int]$info.build
        $batt = [int]$info.battMv
        $ok = ($model -eq "DT-BOX-1") -and ($board -like "DriveTrack V4.6*") -and ($fw.Length -gt 0) -and $batt -ge 2800 -and $batt -le 4300
        Count-Result $ok
        Write-Item $ok "HTTP /api/info" ("model=" + $model + " fw=" + $fw + " build=" + $build + " battMv=" + $batt)
        if ($ok -and ($batt -lt 3400 -or $batt -gt 4250)) {
            Write-Host ("       注意：battMv=" + $batt + " 不在常见区间，用万用表复核一下分压电阻") -ForegroundColor Yellow
        }
    } catch {
        Write-Item $null "HTTP /api/info" ("连不上 " + $url + "，电脑没连设备热点时属正常")
    }
}

Write-Host ""
Write-Host ("通过 {0} 项，失败 {1} 项" -f $passCount, $failCount) -ForegroundColor Cyan
Write-Host ("串口原始日志：" + $LogPath)

Write-Host ""
Write-Host "================ 需要人眼确认 ================" -ForegroundColor Cyan
Write-Host "1. IO7 状态灯：待机时每 2 秒短闪一次；App 下发 start 后变快速双闪。"
Write-Host "2. 电量灯：电池低于 3.5 V 时第 4 颗（IO2）常亮，充满后熄灭。"
Write-Host "3. App 蓝牙能搜到 DriveTrack-XXXX 并连接，start/stop 有 ack 与 sum 返回。"
Write-Host "4. 万用表测电池电压，与 /api/info 的 battMv 相差应小于 100 mV。"
Write-Host "5. IP5306 待机测试：只开 BLE 不录数据，静置 30 分钟应不断电。"
Write-Host "   （V4.6 的虚负载电路 Q1/R19-R21 未贴，若断电需补件或改电源方案。）"

if ($failCount -gt 0) {
    exit 1
}
exit 0
