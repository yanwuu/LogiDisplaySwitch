# LogiDisplaySwitch - Windows 端无感后台联动监听服务
param(
    [string]$TargetDevice = "MX Keys",
    [int]$MacInput = 27
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$switchScript = Join-Path $scriptDir "SwitchToMac.ps1"
$mxScript = Join-Path $scriptDir "mxswitch.ps1"

# 初始检测当前状态
function Check-DeviceConnected {
    param([string]$pattern)
    # 检查处于 Present (在线在线连接) 状态的目标设备
    $devs = Get-PnpDevice -FriendlyName "*$pattern*" -ErrorAction SilentlyContinue | Where-Object { $_.Present -eq $true -and $_.Status -eq "OK" }
    return ($devs -ne $null -and $devs.Count -gt 0)
}

$wasConnected = Check-DeviceConnected $TargetDevice

while ($true) {
    Start-Sleep -Milliseconds 800
    
    $isConnected = Check-DeviceConnected $TargetDevice

    # 检测到 MX Keys 从 Windows 切离（用户在键盘上按了 1 回 Mac）
    if (-not $isConnected -and $wasConnected) {
        # 1. 立即下发 HID++ 指令，将 MX Master 3 鼠标切回通道 1 (Mac)
        if (Test-Path $mxScript) {
            try {
                powershell -NoProfile -ExecutionPolicy Bypass -File $mxScript 1 > $null 2>&1
            } catch {}
        }
        
        # 2. 缓冲 150ms 等待蓝牙总线切换
        Start-Sleep -Milliseconds 150
        
        # 3. 将显示器切回 Mac (Type-C 27)
        if (Test-Path $switchScript) {
            try {
                powershell -NoProfile -ExecutionPolicy Bypass -File $switchScript $MacInput > $null 2>&1
            } catch {}
        }
        
        $wasConnected = $false
    }
    # 检测到 MX Keys 重新连回 Windows（用户在键盘上按了 2 来 Win）
    elseif ($isConnected -and -not $wasConnected) {
        $wasConnected = $true
    }
}
