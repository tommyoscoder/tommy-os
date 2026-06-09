@echo off
echo ============================================
echo   Tommy OS v2.0 - Launch
echo ============================================
echo.

if not exist "build\tommy_os_v2.img" (
    echo [!] tommy_os_v2.img not found. Run build_v2.bat first.
    pause
    exit /b 1
)

REM ---- Locate QEMU ----
set "QEMU="
if exist "C:\Program Files\qemu\qemu-system-i386.exe"      set "QEMU=C:\Program Files\qemu\qemu-system-i386.exe"
if exist "C:\Program Files\QEMU\qemu-system-i386.exe"      set "QEMU=C:\Program Files\QEMU\qemu-system-i386.exe"
if exist "C:\qemu\qemu-system-i386.exe"                    set "QEMU=C:\qemu\qemu-system-i386.exe"
if exist "C:\Program Files\qemu\qemu-system-x86_64.exe"    set "QEMU=C:\Program Files\qemu\qemu-system-x86_64.exe"
if exist "C:\Program Files\QEMU\qemu-system-x86_64.exe"    set "QEMU=C:\Program Files\QEMU\qemu-system-x86_64.exe"
if exist "C:\qemu\qemu-system-x86_64.exe"                  set "QEMU=C:\qemu\qemu-system-x86_64.exe"

if "%QEMU%"=="" (
    where /q qemu-system-i386 2>nul   && set "QEMU=qemu-system-i386"
    where /q qemu-system-x86_64 2>nul && set "QEMU=qemu-system-x86_64"
)

if "%QEMU%"=="" (
    echo [ERROR] QEMU not found!
    echo Install:  winget install SoftwareFreedomConservancy.QEMU
    pause
    exit /b 1
)

echo QEMU: %QEMU%
echo Image: build\tommy_os_v2.img  (Tommy OS v2.0)
echo.
echo  Ctrl+Alt+G   = release mouse
echo  Ctrl+Alt+F   = toggle fullscreen
echo  Ctrl+Alt+Q   = quit QEMU
echo.
echo Pass any arg (e.g.  run_v2.bat w  ) to start windowed.
echo.

set "MODE_FLAG=-full-screen"
if not "%~1"=="" set "MODE_FLAG="

"%QEMU%" ^
    -fda "build\tommy_os_v2.img" ^
    -boot a ^
    -m 32M ^
    -no-reboot ^
    -vga std ^
    %MODE_FLAG% ^
    -name "Tommy OS v2.0"
