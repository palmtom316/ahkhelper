@echo off
rem ScreenPlus 构建包装 —— 绕过 PowerShell 执行策略，双击即可运行
setlocal
set ROOT=%~dp0..
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
endlocal
