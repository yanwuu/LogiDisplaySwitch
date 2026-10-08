@echo off
chcp 65001 >nul
title 安装 LogiDisplaySwitch Windows 后台无感服务

set SCRIPT_DIR=%~dp0
set VBS_TARGET=%SCRIPT_DIR%RunSilent.vbs
set STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set LNK_FILE=%STARTUP_DIR%\LogiDisplaySwitch.lnk

echo 正在配置 Windows 开机静默后台自启...

powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%LNK_FILE%'); $s.TargetPath = 'wscript.exe'; $s.Arguments = '\"%VBS_TARGET%\"'; $s.WorkingDirectory = '%SCRIPT_DIR%'; $s.Save()"

echo 正在立即启动后台监听服务（无窗口静默运行）...
wscript "%VBS_TARGET%"

echo.
echo ==================================================
echo ✅ 安装成功！服务已在后台静默启动！
echo.
echo 工作逻辑：
echo  - 当你在 MX Keys 键盘上按 1 离开 Windows 时：
echo    Windows 会自动将 MX Master 3 鼠标切回通道 1 (Mac)
echo    并自动将显示器切回 Type-C (Mac)！
echo.
echo  - 以后电脑开机无需任何操作，自动在后台静默运行。
echo ==================================================
echo.
pause
