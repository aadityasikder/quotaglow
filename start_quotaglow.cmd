@echo off
setlocal
set "WIDGET=%~dp0desktop-widget\QuotaGlow.ps1"
start "QuotaGlow" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WIDGET%"
endlocal
