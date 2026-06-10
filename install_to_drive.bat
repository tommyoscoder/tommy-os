@echo off
setlocal
echo ==================================================
echo   Tommy OS v2.02  -  Install to physical drive
echo   !! WARNING: this ERASES the chosen drive !!
echo ==================================================
echo.

if not exist build\tommy_os_v2.img (
    echo [ERROR] build\tommy_os_v2.img not found.
    echo         Run build_v2.bat first.
    pause
    exit /b 1
)

REM Hand off to PowerShell installer for safer drive listing and writing.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_to_drive.ps1"
exit /b %errorlevel%
