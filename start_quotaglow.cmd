@echo off
setlocal
set "LAUNCHER=%~dp0start_quotaglow.vbs"
wscript.exe //nologo "%LAUNCHER%"
endlocal
