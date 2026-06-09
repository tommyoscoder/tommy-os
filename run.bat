@echo off
echo ============================================
echo   Tommy OS - Launch
echo ============================================
echo.

if not exist "build\tommy_os.img" (
    echo [!] tommy_os.img not found. Run build.bat first.
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
    echo.
    echo Install:  winget install SoftwareFreedomConservancy.QEMU
    echo    -or-   choco install qemu
    echo.
    echo Then re-run this script.
    pause
    exit /b 1
)

echo QEMU: %QEMU%
echo Image: build\tommy_os.img  (1.44MB floppy)
echo.
echo  Ctrl+Alt+G   = release mouse
echo  Ctrl+Alt+F   = toggle fullscreen
echo  Ctrl+Alt+Q   = quit QEMU
echo.
echo Pass any arg (e.g.  run.bat w  ) to start in a window instead of fullscreen.
echo.

set "MODE_FLAG=-full-screen"
if not "%~1"=="" set "MODE_FLAG="

"%QEMU%" ^
    -fda "build\tommy_os.img" ^
    -boot a ^
    -m 32M ^
    -no-reboot ^
    -vga std ^
    %MODE_FLAG% ^
    -name "Tommy OS"
