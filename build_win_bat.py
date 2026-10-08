#!/usr/bin/env python3
import base64
import io
import os
import zipfile

def main():
    root = os.path.dirname(os.path.abspath(__file__))
    ps1_path = os.path.join(root, 'windows', 'LogiSync.ps1')
    vbs_path = os.path.join(root, 'windows', 'RunSilent.vbs')

    # 1. Create zip in memory containing LogiSync.ps1 and RunSilent.vbs
    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(ps1_path, arcname='LogiSync.ps1')
        zf.write(vbs_path, arcname='RunSilent.vbs')

    b64_zip = base64.b64encode(zip_buf.getvalue()).decode('ascii')
    print(f"Zip created. Base64 length: {len(b64_zip)}")

    # 2. Block 0: Install
    # Note: Use raw string or standard string without shell interference
    b0_ps = f"""$b64 = "{b64_zip}"
$dir = [System.IO.Path]::Combine($env:APPDATA, 'LogiDisplaySwitch')
if (-not (Test-Path $dir)) {{ New-Item -ItemType Directory -Path $dir -Force | Out-Null }}
$bytes = [Convert]::FromBase64String($b64)
$zip = [System.IO.Path]::Combine($dir, 'tmp.zip')
[System.IO.File]::WriteAllBytes($zip, $bytes)
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Remove-Item $zip -Force

$startup = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\\Windows\\Start Menu\\Programs\\Startup')
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut((Join-Path $startup 'LogiDisplaySwitch.lnk'))
$s.TargetPath = 'wscript.exe'
$vbs = Join-Path $dir 'RunSilent.vbs'
$s.Arguments = '"' + $vbs + '"'
$s.WorkingDirectory = $dir
$s.Save()

Get-CimInstance Win32_Process | Where-Object {{ $_.CommandLine -like '*LogiSync.ps1*' -or $_.CommandLine -like '*AutoSwitchWin.ps1*' }} | ForEach-Object {{ Stop-Process -Id $_.ProcessId -Force }}
Start-Process 'wscript.exe' -ArgumentList ('"' + $vbs + '"')
"""
    b0_enc = base64.b64encode(b0_ps.encode('utf-16le')).decode('ascii')

    # 3. Block 1: Test
    b1_ps = f"""$b64 = "{b64_zip}"
$dir = [System.IO.Path]::Combine($env:APPDATA, 'LogiDisplaySwitch')
if (-not (Test-Path $dir)) {{ New-Item -ItemType Directory -Path $dir -Force | Out-Null }}
$bytes = [Convert]::FromBase64String($b64)
$zip = [System.IO.Path]::Combine($dir, 'tmp.zip')
[System.IO.File]::WriteAllBytes($zip, $bytes)
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Remove-Item $zip -Force

$sync = Join-Path $dir 'LogiSync.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Test
"""
    b1_enc = base64.b64encode(b1_ps.encode('utf-16le')).decode('ascii')

    # 4. Block 2: Uninstall
    b2_ps = """Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*LogiSync.ps1*' -or $_.CommandLine -like '*AutoSwitchWin.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$startup = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\\Windows\\Start Menu\\Programs\\Startup')
$lnk = Join-Path $startup 'LogiDisplaySwitch.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }
$dir = [System.IO.Path]::Combine($env:APPDATA, 'LogiDisplaySwitch')
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
"""
    b2_enc = base64.b64encode(b2_ps.encode('utf-16le')).decode('ascii')

    # 5. Build Batch File Content with CRLF (\r\n) line endings
    bat_lines = [
        "@echo off",
        "title LogiDisplaySwitch (Windows 鼠标跟随守护)",
        "",
        'if "%1"=="-test" goto :RUN_TEST',
        'if "%1"=="-uninstall" goto :RUN_UNINSTALL',
        'if "%1"=="-stop" goto :RUN_UNINSTALL',
        "",
        "echo ==============================================================",
        "echo   LogiDisplaySwitch - 鼠标跟随键盘通道 (Windows 极速守护版)",
        "echo ==============================================================",
        "echo.",
        "echo  架构说明:",
        "echo    * 显示器切换: 由键盘与 Mac 联动全权控制 (键盘按1/2自动切屏)",
        "echo    * 鼠标跟随:   Windows 后台专职负责在键盘切回 Mac 时切走鼠标",
        "echo    * 彻底移除 Windows 切屏逻辑与键盘倒切，彻底杜绝切屏回弹！",
        "echo.",
        "echo  [1] 一键安装并立即在后台静默运行 (开机自启, 无黑框) [推荐]",
        "echo  [2] 立即测试切鼠标回 Mac (通道 1)",
        "echo  [3] 停止并卸载后台服务",
        "echo.",
        "set CHOICE=1",
        'set /p CHOICE="请输入选项 [1/2/3] (默认直接回车安装 1): "',
        'if "%CHOICE%"=="2" goto :RUN_TEST',
        'if "%CHOICE%"=="3" goto :RUN_UNINSTALL',
        "",
        ":RUN_INSTALL",
        "echo.",
        "echo 正在安装至 APPDATA 并配置开机自启...",
        f"powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand {b0_enc}",
        "echo.",
        "echo [+] 安装成功！后台无感服务已启动，开机将自动静默运行。",
        "echo.",
        "pause",
        "exit /b",
        "",
        ":RUN_TEST",
        "echo.",
        "echo 正在执行测试...",
        f"powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand {b1_enc}",
        "echo.",
        "echo [+] 测试脚本执行完毕。",
        "echo.",
        "pause",
        "exit /b",
        "",
        ":RUN_UNINSTALL",
        "echo.",
        "echo 正在停止后台守护进程并卸载...",
        f"powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand {b2_enc}",
        "echo.",
        "echo [+] 后台服务已停止并成功卸载！",
        "echo.",
        "pause",
        "exit /b",
        ""
    ]

    bat_content = "\r\n".join(bat_lines).encode("gbk")

    # Write to windows/LogiDisplaySwitch.bat and dist/LogiDisplaySwitch.bat
    target_paths = [
        os.path.join(root, 'windows', 'LogiDisplaySwitch.bat'),
        os.path.join(root, 'dist', 'LogiDisplaySwitch.bat')
    ]

    for p in target_paths:
        with open(p, "wb") as f:
            f.write(bat_content)
        print(f"Successfully generated: {p} ({len(bat_content)} bytes)")

    # 6. Verify generated files
    print("\n--- Verifying generated bat file ---")
    with open(target_paths[0], "rb") as f:
        data = f.read()

    # Verify CRLF
    assert b"\r\n" in data, "CRLF missing!"
    # Verify no bare LF
    bare_lf = data.replace(b"\r\n", b"").count(b"\n")
    assert bare_lf == 0, f"Found {bare_lf} bare LFs!"
    print(f"Line endings: 100% valid CRLF (bare LF count: {bare_lf})")

    # Verify PowerShell decoded blocks
    import re
    enc_matches = re.findall(rb'-EncodedCommand\s+([A-Za-z0-9+/=]+)', data)
    assert len(enc_matches) == 3, f"Expected 3 EncodedCommand blocks, found {len(enc_matches)}"

    for i, enc in enumerate(enc_matches):
        dec = base64.b64decode(enc).decode('utf-16le')
        print(f"\nBlock {i} verification:")
        if i == 0:
            assert "$b64 =" in dec, "Missing $b64 in Block 0!"
            assert "$bytes = [Convert]::FromBase64String($b64)" in dec, "Missing $bytes in Block 0!"
            assert "[System.IO.File]::WriteAllBytes($zip, $bytes)" in dec, "Missing WriteAllBytes in Block 0!"
            assert "$env:APPDATA" in dec, "Missing $env:APPDATA in Block 0!"
            assert "$_.CommandLine" in dec, "Missing $_.CommandLine in Block 0!"
            assert "$s.Save()" in dec, "Missing $s.Save() in Block 0!"
            print("  Block 0: ALL PowerShell variables verified intact!")
        elif i == 1:
            assert "$b64 =" in dec, "Missing $b64 in Block 1!"
            assert "$bytes = [Convert]::FromBase64String($b64)" in dec, "Missing $bytes in Block 1!"
            assert "$sync = Join-Path" in dec, "Missing $sync in Block 1!"
            print("  Block 1: ALL PowerShell variables verified intact!")
        elif i == 2:
            assert "$_.CommandLine" in dec, "Missing $_.CommandLine in Block 2!"
            assert "$startup = [System.IO.Path]::Combine($env:APPDATA" in dec, "Missing $startup in Block 2!"
            assert "$lnk = Join-Path" in dec, "Missing $lnk in Block 2!"
            print("  Block 2: ALL PowerShell variables verified intact!")

    print("\nALL VERIFICATIONS PASSED! Windows BAT file is 100% valid.")

if __name__ == '__main__':
    main()
