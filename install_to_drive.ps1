# =====================================================================
# Tommy OS - PowerShell USB / disk installer
#
# Lists physical drives via CIM (modern, replaces WMIC), asks for a
# selection, requires the user to type YES, then writes tommy_os.img
# straight to the physical drive using a FileStream.
#
# Run as Administrator! Otherwise opening \\.\PhysicalDriveN will fail
# with "access denied".
# =====================================================================

$ErrorActionPreference = "Stop"

function Require-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ""
        Write-Host "[!] This script must run as Administrator." -ForegroundColor Yellow
        Write-Host "    Right-click PowerShell -> Run as administrator, then re-run." -ForegroundColor Yellow
        Read-Host "Press ENTER to exit"
        exit 1
    }
}

function Format-Size([uint64]$bytes) {
    if ($bytes -ge 1TB) { return ("{0:N2} TB" -f ($bytes / 1TB)) }
    if ($bytes -ge 1GB) { return ("{0:N2} GB" -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N2} MB" -f ($bytes / 1MB)) }
    return ("{0:N0} bytes" -f $bytes)
}

Require-Admin

$imgPath = Join-Path $PSScriptRoot "build\tommy_os.img"
if (-not (Test-Path $imgPath)) {
    Write-Host "[ERROR] $imgPath not found. Run build.bat first." -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit 1
}

Write-Host ""
Write-Host "=== Tommy OS installer ===" -ForegroundColor Cyan
Write-Host "Image: $imgPath"
Write-Host ""
Write-Host "Detected physical drives:" -ForegroundColor Cyan
Write-Host ""

$drives = Get-CimInstance Win32_DiskDrive | Sort-Object Index
if (-not $drives) {
    Write-Host "No physical drives detected." -ForegroundColor Red
    exit 1
}

$drives | ForEach-Object {
    $size  = Format-Size ([uint64]$_.Size)
    $model = $_.Model
    $idx   = $_.Index
    $iface = $_.InterfaceType
    Write-Host ("  [{0}]  {1,-32}  {2,-12}  {3}" -f $idx, $model, $iface, $size)
}

Write-Host ""
Write-Host "WARNING: writing to a drive ERASES it completely." -ForegroundColor Yellow
Write-Host "Pick the USB stick you do NOT mind losing." -ForegroundColor Yellow
Write-Host ""

$num = Read-Host "Enter drive index (number above)"
if ($num -notmatch '^\d+$') {
    Write-Host "Not a number. Aborting." -ForegroundColor Red
    exit 1
}

$target = $drives | Where-Object { $_.Index -eq [int]$num }
if (-not $target) {
    Write-Host "No drive with index $num. Aborting." -ForegroundColor Red
    exit 1
}

$path = "\\.\PhysicalDrive$($target.Index)"
$size = Format-Size ([uint64]$target.Size)

Write-Host ""
Write-Host "You selected:" -ForegroundColor Yellow
Write-Host "  $path"
Write-Host "  Model: $($target.Model)"
Write-Host "  Size:  $size"
Write-Host ""

# Refuse to write to the system drive (heuristic: index 0 usually).
if ($target.Index -eq 0) {
    Write-Host "[BLOCKED] Drive 0 is almost always the system disk." -ForegroundColor Red
    Write-Host "          Refusing to write to it. Pick a USB stick." -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit 1
}

$confirm = Read-Host "Type YES (uppercase) to ERASE this drive and install Tommy OS"
if ($confirm -cne "YES") {
    Write-Host "Cancelled." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host "Writing $imgPath to $path ..." -ForegroundColor Cyan

try {
    $img    = [System.IO.File]::ReadAllBytes($imgPath)
    $stream = [System.IO.File]::Open($path,
              [System.IO.FileMode]::Open,
              [System.IO.FileAccess]::Write,
              [System.IO.FileShare]::ReadWrite)
    $stream.Write($img, 0, $img.Length)
    $stream.Flush()
    $stream.Close()
    Write-Host "OK - wrote $($img.Length) bytes." -ForegroundColor Green
    Write-Host ""
    Write-Host "Done. You can now boot from this drive."          -ForegroundColor Green
    Write-Host "  - Reboot, enter BIOS / boot menu (often F12 or Esc)" -ForegroundColor Green
    Write-Host "  - Pick the USB stick"                                -ForegroundColor Green
} catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    exit 1
}

Read-Host "Press ENTER to exit"
