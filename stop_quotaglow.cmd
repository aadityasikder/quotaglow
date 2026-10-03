@echo off
setlocal
set "STOPPER=%~dp0desktop-widget\Stop-QuotaGlow.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%STOPPER%"
if errorlevel 1 pause
endlocal
