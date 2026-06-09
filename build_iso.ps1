# PowerShell ISO builder for Tommy OS (no Python required)
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$imgPath = Join-Path $PSScriptRoot "build\tommy_os.img"
$isoPath = Join-Path $PSScriptRoot "build\tommy_os.iso"
$SECTOR  = 2048

function Get-B32BE([uint32]$v) {
    $le = [BitConverter]::GetBytes($v)
    return [byte[]]@($le[3],$le[2],$le[1],$le[0])
}
function Get-B32([uint32]$v) {
    $le = [BitConverter]::GetBytes($v)
    $be = [byte[]]@($le[3],$le[2],$le[1],$le[0])
    return $le + $be
}
function Get-B16([uint16]$v) {
    $le = [BitConverter]::GetBytes($v)
    $be = [byte[]]@($le[1],$le[0])
    return $le + $be
}
function Get-DChars([string]$s, [int]$n) {
    $raw = [System.Text.Encoding]::ASCII.GetBytes($s.ToUpper().PadRight($n).Substring(0,$n))
    foreach ($i in 0..($raw.Length-1)) { if ($raw[$i] -eq 0) { $raw[$i] = 0x20 } }
    return $raw
}
function New-DirRecord([uint32]$lba, [uint32]$dlen, [byte[]]$name, [bool]$isDir) {
    $nlen = $name.Length
    $rlen = 33 + $nlen
    if ($rlen % 2 -eq 1) { $rlen++ }
    $r = [System.Collections.Generic.List[byte]]::new()
    $r.Add([byte]$rlen); $r.Add([byte]0)
    foreach ($b in (Get-B32 $lba))  { $r.Add($b) }
    foreach ($b in (Get-B32 $dlen)) { $r.Add($b) }
    for ($i=0;$i -lt 7;$i++) { $r.Add([byte]0) }
    $flags = [byte]0; if ($isDir) { $flags = [byte]2 }
    $r.Add($flags); $r.Add([byte]0); $r.Add([byte]0)
    foreach ($b in (Get-B16 1)) { $r.Add($b) }
    $r.Add([byte]$nlen)
    foreach ($b in $name) { $r.Add($b) }
    while ($r.Count -lt $rlen) { $r.Add([byte]0) }
    return [byte[]]$r
}

$bootImg = [System.IO.File]::ReadAllBytes($imgPath)
if ($bootImg.Length -ne 1474560) { throw "bad img size $($bootImg.Length)" }

$LBA_PVD=16;$LBA_BR=17;$LBA_TERM=18;$LBA_BOOTCAT=19
$LBA_PT_L=20;$LBA_PT_M=21;$LBA_ROOT=22;$LBA_BOOT_IMG=23
$TOTAL_LBA = $LBA_BOOT_IMG + ($bootImg.Length / $SECTOR)

$rootRec = New-DirRecord $LBA_ROOT $SECTOR ([byte[]]@(0)) $true

# PVD
$pvd = [byte[]]::new($SECTOR); $pvd[0]=1
$enc = [System.Text.Encoding]::ASCII
$enc.GetBytes('CD001') | ForEach-Object -Begin {$i=1} { $pvd[$i]=$_; $i++ }
$pvd[6]=1
$dc32 = Get-DChars 'TOMMYOS' 32
[Array]::Copy($dc32,0,$pvd, 8,32); [Array]::Copy($dc32,0,$pvd,40,32)
[Array]::Copy((Get-B32 $TOTAL_LBA),0,$pvd,80,8)
[Array]::Copy((Get-B16 1),0,$pvd,120,4); [Array]::Copy((Get-B16 1),0,$pvd,124,4)
[Array]::Copy((Get-B16 $SECTOR),0,$pvd,128,4)
[Array]::Copy((Get-B32 10),0,$pvd,132,8)
[Array]::Copy([BitConverter]::GetBytes([uint32]$LBA_PT_L),0,$pvd,140,4)
[Array]::Copy((Get-B32BE $LBA_PT_M),0,$pvd,148,4)
[Array]::Copy($rootRec,0,$pvd,156,$rootRec.Length)
$dc128 = Get-DChars 'TOMMYOS' 128
[Array]::Copy($dc128,0,$pvd,190,128); [Array]::Copy($dc128,0,$pvd,318,128)
[Array]::Copy($dc128,0,$pvd,446,128); [Array]::Copy($dc128,0,$pvd,574,128)
$d = $enc.GetBytes('20260609000000')
[Array]::Copy($d,0,$pvd,813,14); $pvd[827]=0
[Array]::Copy($d,0,$pvd,830,14); $pvd[844]=0
$pvd[881]=1

# BR
$br = [byte[]]::new($SECTOR)
$enc.GetBytes('CD001') | ForEach-Object -Begin {$i=1} { $br[$i]=$_; $i++ }
$br[6]=1
$enc.GetBytes('EL TORITO SPECIFICATION') | ForEach-Object -Begin {$i=7} { $br[$i]=$_; $i++ }
[Array]::Copy([BitConverter]::GetBytes([uint32]$LBA_BOOTCAT),0,$br,71,4)

# TERM
$term=[byte[]]::new($SECTOR); $term[0]=0xFF
$enc.GetBytes('CD001') | ForEach-Object -Begin {$i=1} { $term[$i]=$_; $i++ }
$term[6]=1

# Boot Catalog
$bc=[byte[]]::new($SECTOR)
$ve=[byte[]]::new(32); $ve[0]=1; $ve[1]=0
$id = Get-DChars 'TOMMYOS' 24
[Array]::Copy($id,0,$ve,4,24)
$ve[30]=0x55; $ve[31]=0xAA
$s=0; for ($i=0;$i -lt 32;$i+=2) { $s=($s+$ve[$i]+($ve[$i+1]*256)) -band 0xFFFF }
$chk=(0x10000-$s) -band 0xFFFF; $ve[28]=$chk -band 0xFF; $ve[29]=($chk -shr 8) -band 0xFF
[Array]::Copy($ve,0,$bc,0,32)
$de=[byte[]]::new(32); $de[0]=0x88; $de[1]=3
[Array]::Copy([BitConverter]::GetBytes([uint16]1),0,$de,6,2)
[Array]::Copy([BitConverter]::GetBytes([uint32]$LBA_BOOT_IMG),0,$de,8,4)
[Array]::Copy($de,0,$bc,32,32)

# Path tables
$ptl=[byte[]]::new($SECTOR); $ptl[0]=1; $ptl[1]=0
[Array]::Copy([BitConverter]::GetBytes([uint32]$LBA_ROOT),0,$ptl,2,4)
[Array]::Copy([BitConverter]::GetBytes([uint16]1),0,$ptl,6,2)
$ptm=[byte[]]::new($SECTOR); $ptm[0]=1; $ptm[1]=0
[Array]::Copy((Get-B32BE $LBA_ROOT),0,$ptm,2,4)
$be2=[BitConverter]::GetBytes([uint16]1); [Array]::Reverse($be2)
[Array]::Copy($be2,0,$ptm,6,2)

# Root directory
$root=[byte[]]::new($SECTOR)
$dot    = New-DirRecord $LBA_ROOT $SECTOR ([byte[]]@(0)) $true
$dotdot = New-DirRecord $LBA_ROOT $SECTOR ([byte[]]@(1)) $true
[Array]::Copy($dot,0,$root,0,$dot.Length)
[Array]::Copy($dotdot,0,$root,$dot.Length,$dotdot.Length)

# Write ISO
$out = [System.IO.File]::OpenWrite($isoPath)
$out.Write([byte[]]::new(16*$SECTOR),0,16*$SECTOR)
$out.Write($pvd,0,$SECTOR); $out.Write($br,0,$SECTOR); $out.Write($term,0,$SECTOR)
$out.Write($bc,0,$SECTOR); $out.Write($ptl,0,$SECTOR); $out.Write($ptm,0,$SECTOR)
$out.Write($root,0,$SECTOR); $out.Write($bootImg,0,$bootImg.Length)
$out.Close()

$sz = (Get-Item $isoPath).Length
$expected = $TOTAL_LBA * $SECTOR
Write-Host "ISO: $isoPath"
Write-Host "Size: $sz bytes ($([math]::Round($sz/1MB,2)) MB), expected $expected"
if ($sz -eq $expected) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "SIZE MISMATCH" -ForegroundColor Red }
