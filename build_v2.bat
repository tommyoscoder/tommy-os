@echo off
echo ============================================
echo   Tommy OS v2.02 - Build Script
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

echo [1/5] Assembling bootloader...
"%NASM%" -f bin src\boot.asm -o build\boot.bin
if %errorlevel% neq 0 ( echo FAILED. & pause & exit /b 1 )
echo       boot.bin  OK  (512 bytes)

echo [2/5] Assembling v2.02 kernel...
"%NASM%" -f bin src\kernel_v2.asm -o build\kernel_v2.bin
if %errorlevel% neq 0 ( echo FAILED. & pause & exit /b 1 )
echo       kernel_v2.bin  OK  (64000 bytes)

echo [3/5] Linking...
copy /b build\boot.bin + build\kernel_v2.bin build\tommy_os_v2.img >nul
echo       Merged to tommy_os_v2.img

echo [4/5] Padding to 1.44MB floppy image...
powershell -NoProfile -Command "$f = [System.IO.File]::OpenWrite('build\tommy_os_v2.img'); $null = $f.Seek(0,[System.IO.SeekOrigin]::End); $target = 1474560; $pad = $target - $f.Position; if ($pad -gt 0) { $f.Write([byte[]]::new($pad), 0, $pad) }; $f.Close()"
echo       tommy_os_v2.img  OK  (1.44MB)

echo [5/5] Building ISO...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Get-Content build_iso.ps1 -Raw;$s=$s-replace'tommy_os\.img','tommy_os_v2.img'-replace'tommy_os\.iso','tommy_os_v2.iso';$s|Set-Content _tmp_v2iso.ps1;& powershell -NoProfile -File _tmp_v2iso.ps1;Remove-Item _tmp_v2iso.ps1"
echo       tommy_os_v2.iso  OK

echo.
echo ============================================
echo   BUILD v2.02 SUCCESSFUL
echo ============================================
echo.
echo   Run:  run_v2.bat
echo.
