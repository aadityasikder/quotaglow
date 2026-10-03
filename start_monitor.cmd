@echo off
setlocal
title ESP32 Codex Usage Monitor

rem ================================================================
rem CHANGE THIS to the ESP32 port shown in Arduino IDE: Tools ^> Port
set "COM_PORT=COM6"
rem ================================================================

rem Set DEMO_MODE to 1 for the display test, or 0 for live Codex data.
set "DEMO_MODE=0"

set "HELPER=%~dp0pc-helper\codex_usage_helper.ps1"

if "%DEMO_MODE%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Port "%COM_PORT%" -Demo
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Port "%COM_PORT%"
)

if errorlevel 1 (
    echo.
    echo The monitor stopped because of an error.
    pause
    goto :done
)

if "%DEMO_MODE%"=="1" (
    echo.
    echo Demo finished successfully. The three samples were sent to the ESP32.
    echo Set DEMO_MODE=0 when you are ready to display live Codex limits.
    pause
)

:done
endlocal
