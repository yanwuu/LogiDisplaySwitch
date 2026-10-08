@echo off
chcp 65001 >nul
title 卸载 LogiDisplaySwitch 后台服务

set STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set LNK_FILE=%STARTUP_DIR%\LogiDisplaySwitch.lnk

echo 正在停止后台监听进程...
powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*AutoSwitchWin.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1

if exist "%LNK_FILE%" (
    del "%LNK_FILE%"
    echo 已移除开机自启快捷方式。
)

echo.
echo ✅ 后台服务已停止并成功卸载！
echo.
pause
