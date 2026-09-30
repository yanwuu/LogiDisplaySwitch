@echo off
chcp 65001 >nul
title 立即切回 Mac

echo 1. 正在将 MX Master 3 鼠标切回通道 1 (Mac)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mxswitch.ps1" 1 >nul 2>&1

echo 2. 正在切换显示器至 Mac (Type-C 27)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SwitchToMac.ps1" 27 >nul 2>&1

echo ✅ 已完成指令发送！
timeout /t 2 >nul
