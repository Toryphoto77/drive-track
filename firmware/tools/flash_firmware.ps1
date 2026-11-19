# DriveTrack V4.6 首次串口烧录脚本（Windows PowerShell）
#
# 适用：新板第一次烧录，或设备变砖后的恢复。
# 之后升级固件请用 App 的「设备中心 → 固件升级」，不需要再插线。
#
# 前置条件：
#   1. Python 3.8+（python.org 或 Microsoft Store 均可）
#   2. pip install esptool
#   3. USB-C 数据线（能传数据，不是纯充电线）
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\flash_firmware.ps1 -Port COM5
#   powershell -ExecutionPolicy Bypass -File tools\flash_firmware.ps1 -Port COM5 -Erase
#
# 参数说明：
#   -Port   设备管理器里看到的串口，例如 COM5
#   -Baud   默认 460800；线材差导致失败时可降到 115200
#   -Erase  先整片擦除（会清空 NVS / 缓存的行程数据，首次或异常时才用）
param(
  [Parameter(Mandatory = $true)][string]$Port,
  [int]$Baud = 460800,
  [switch]$Erase,
  [string]$BinDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin')
)

$ErrorActionPreference = 'Stop'

$bootloader = Join-Path $BinDir 'bootloader.bin'
$partTable  = Join-Path $BinDir 'partition-table.bin'
$otaData    = Join-Path $BinDir 'ota_data_initial.bin'
$appBin     = Join-Path $BinDir 'drivetrack-box-0.3.0.bin'

foreach ($f in @($bootloader, $partTable, $otaData, $appBin)) {
  if (-not (Test-Path $f)) { throw "缺少烧录文件：$f" }
}

# 优先用 ESP-IDF 自带的 esptool（如果装过 IDF），否则用系统 Python 的 esptool。
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { throw "没找到 python。请先安装 Python 3.8+ 并勾选 Add to PATH。" }
$pythonExe = $pythonCmd.Source

$esptool = $null
foreach ($idfPython in @('C:\Espressif53\python_env', 'C:\Espressif\python_env')) {
  if (-not (Test-Path $idfPython)) { continue }
  $candidate = Get-ChildItem $idfPython -Recurse -Filter 'esptool.py' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($candidate) { $esptool = $candidate.FullName; break }
}
if (-not $esptool) {
  Write-Host "使用系统 Python 的 esptool 模块。" -ForegroundColor Cyan
  $prefix = @('-m', 'esptool')
} else {
  Write-Host "使用 ESP-IDF 自带 esptool：$esptool" -ForegroundColor Cyan
  $prefix = @($esptool)
}

if ($Erase) {
  Write-Host "整片擦除 $Port …" -ForegroundColor Yellow
  & $pythonExe @prefix -p $Port erase_flash
  if ($LASTEXITCODE -ne 0) { throw "擦除失败：检查串口是否被别的软件占用。" }
}

Write-Host "开始烧录 $Port @ $Baud …（ESP32-S3 的 bootloader 偏移是 0x0）" -ForegroundColor Cyan
& $pythonExe @prefix -p $Port -b $Baud --before default_reset --after hard_reset write_flash `
  --flash_mode dio --flash_freq 80m --flash_size 16MB `
  0x0     $bootloader `
  0x8000  $partTable `
  0xf000  $otaData `
  0x20000 $appBin
if ($LASTEXITCODE -ne 0) {
  throw "烧录失败。常见原因：串口被占用、线材不支持数据传输、没进下载模式（按住 BOOT 再复位）。"
}

Write-Host ""
Write-Host "烧录完成。设备会自动重启：" -ForegroundColor Green
Write-Host "  · 串口日志应出现 DriveTrack V4.6 fw=0.3.0 build=3"
Write-Host "  · 手机能搜到 WiFi 热点 DriveTrack-XXXX（密码 drivetrack123）"
Write-Host "  · 手机能搜到同名 BLE 设备"
Write-Host ""
Write-Host "查看串口日志：python -m serial.tools.miniterm $Port 115200"
