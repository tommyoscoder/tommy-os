@echo off
echo ============================================
echo   Tommy OS - Build Script
echo ============================================
echo.

REM ---- Locate NASM ----
set "NASM="
where /q nasm 2>nul && set "NASM=nasm"
if "%NASM%"=="" if exist "%LOCALAPPDATA%\bin\NASM\nasm.exe" set "NASM=%LOCALAPPDATA%\bin\NASM\nasm.exe"
if "%NASM%"=="" if exist "C:\NASM\nasm.exe"                 set "NASM=C:\NASM\nasm.exe"
if "%NASM%"=="" if exist "C:\Program Files\NASM\nasm.exe"   set "NASM=C:\Program Files\NASM\nasm.exe"

if "%NASM%"=="" (
    echo [ERROR] NASM not found.
    echo Install:  winget install NASM.NASM
    pause
    exit /b 1
)

if not exist build mkdir build

echo [1/4] Assembling bootloader...
"%NASM%" -f bin src\boot.asm -o build\boot.bin
if %errorlevel% neq 0 ( echo FAILED. & pause & exit /b 1 )
echo       boot.bin  OK  (512 bytes)

echo [2/4] Assembling kernel...
"%NASM%" -f bin src\kernel.asm -o build\kernel.bin
if %errorlevel% neq 0 ( echo FAILED. & pause & exit /b 1 )
echo       kernel.bin  OK  (64000 bytes)

echo [3/4] Linking...
copy /b build\boot.bin + build\kernel.bin build\tommy_os.img >nul
echo       Merged to tommy_os.img

echo [4/4] Padding to 1.44MB floppy image...
powershell -NoProfile -Command "$f = [System.IO.File]::OpenWrite('build\tommy_os.img'); $null = $f.Seek(0,[System.IO.SeekOrigin]::End); $target = 1474560; $pad = $target - $f.Position; if ($pad -gt 0) { $f.Write([byte[]]::new($pad), 0, $pad) }; $f.Close()"
echo       tommy_os.img  OK  (1.44MB)

echo.
echo ============================================
echo   BUILD SUCCESSFUL
echo ============================================
echo.
echo   Run:  run.bat
echo.
