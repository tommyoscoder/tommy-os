#!/usr/bin/env python3
# Build a bootable El Torito (floppy-emulation) ISO 9660 image from tommy_os.img.
# Output: build/tommy_os.iso
#
# Layout:
#   LBA  0-15  : System area (zeros)
#   LBA 16     : Primary Volume Descriptor
#   LBA 17     : Boot Record Volume Descriptor (El Torito)
#   LBA 18     : Volume Descriptor Set Terminator
#   LBA 19     : Boot Catalog
#   LBA 20     : Path Table L (little-endian)
#   LBA 21     : Path Table M (big-endian)
#   LBA 22     : Root Directory
#   LBA 23+    : Boot image (1.44MB floppy, 720 ISO sectors)
#
# El Torito boots with 1.44 MB floppy emulation: BIOS sets DL=0 and exposes
# the image as a virtual floppy via INT 13h, so the unmodified Tommy OS
# bootloader works without changes.

import os
import struct
import sys

SECTOR = 2048

def b16(v):  # both-endian uint16 -> 4 bytes
    return struct.pack('<H', v) + struct.pack('>H', v)

def b32(v):  # both-endian uint32 -> 8 bytes
    return struct.pack('<I', v) + struct.pack('>I', v)

def pad(b, n, fill=b'\x00'):
    if len(b) > n:
        raise ValueError(f'overflow: {len(b)} > {n}')
    return b + fill * (n - len(b))

def dchars(s, n):
    return pad(s.upper().encode('ascii'), n, b' ')

def date_str(y, mo, d, h, mi, s):
    # 17-byte ISO 9660 date: YYYYMMDDHHMMSSff + tz
    return (f'{y:04d}{mo:02d}{d:02d}{h:02d}{mi:02d}{s:02d}00').encode('ascii') + b'\x00'

def dir_record(extent_lba, data_len, name, is_dir):
    # name: bytes
    name_len = len(name)
    rec_len = 33 + name_len + (1 - name_len % 2 if name_len % 2 == 0 else 0)
    # ISO 9660 dir records must be even length; if name_len odd, no pad; if even, +1 pad byte.
    rec_len = 33 + name_len
    if rec_len % 2:
        rec_len += 1
    flags = 0x02 if is_dir else 0x00
    r = bytes([rec_len, 0])                # len + ext_attr_len
    r += b32(extent_lba)                    # extent location (both-endian)
    r += b32(data_len)                      # data length (both-endian)
    r += bytes([0,0,0,0,0,0,0])             # date (7 bytes, all zeros = no date)
    r += bytes([flags, 0, 0])               # flags, unit, gap
    r += b16(1)                             # volume sequence number
    r += bytes([name_len])
    r += name
    if len(r) < rec_len:
        r += b'\x00'
    assert len(r) == rec_len, (len(r), rec_len)
    return r

def build_iso(img_path, iso_path):
    with open(img_path, 'rb') as f:
        boot_img = f.read()

    if len(boot_img) != 1474560:
        raise SystemExit(f'expected 1474560-byte floppy image, got {len(boot_img)}')

    # Each ISO sector is 2048 bytes; floppy is 1474560 bytes = exactly 720 ISO sectors.
    boot_img_iso_sectors = len(boot_img) // SECTOR
    assert boot_img_iso_sectors == 720

    LBA_PVD       = 16
    LBA_BR        = 17
    LBA_TERM      = 18
    LBA_BOOTCAT   = 19
    LBA_PT_L      = 20
    LBA_PT_M      = 21
    LBA_ROOT      = 22
    LBA_BOOT_IMG  = 23
    TOTAL_LBA     = LBA_BOOT_IMG + boot_img_iso_sectors  # 743

    # ----- Root directory record (used inside PVD) -----
    # Root has name = 0x00 (single null byte)
    root_dir_rec = dir_record(LBA_ROOT, SECTOR, b'\x00', is_dir=True)

    # ----- Primary Volume Descriptor (LBA 16) -----
    pvd = bytearray(SECTOR)
    pvd[0] = 0x01                            # VD type = primary
    pvd[1:6] = b'CD001'
    pvd[6] = 0x01                            # version
    # 7: unused
    pvd[8:40]   = dchars('TOMMYOS', 32)      # system id
    pvd[40:72]  = dchars('TOMMYOS', 32)      # volume id
    # 72-79: unused
    pvd[80:88]  = b32(TOTAL_LBA)             # volume space size
    # 88-119: unused (zeros)
    pvd[120:124] = b16(1)                    # volume set size
    pvd[124:128] = b16(1)                    # volume sequence number
    pvd[128:132] = b16(SECTOR)               # logical block size
    pvd[132:140] = b32(10)                   # path table size (we'll use 10 bytes)
    pvd[140:144] = struct.pack('<I', LBA_PT_L)   # LE path table location
    pvd[144:148] = b'\x00\x00\x00\x00'           # optional LE PT location
    pvd[148:152] = struct.pack('>I', LBA_PT_M)   # BE path table location
    pvd[152:156] = b'\x00\x00\x00\x00'           # optional BE PT location
    pvd[156:156+len(root_dir_rec)] = root_dir_rec
    pvd[190:318] = dchars('TOMMYOS', 128)    # volume set id
    pvd[318:446] = dchars('TOMMYOS', 128)    # publisher id
    pvd[446:574] = dchars('TOMMYOS_BUILD', 128)  # data preparer
    pvd[574:702] = dchars('TOMMYOS', 128)    # application id
    pvd[702:739] = b' ' * 37                 # copyright file id
    pvd[739:776] = b' ' * 37                 # abstract file id
    pvd[776:813] = b' ' * 37                 # bibliographic file id
    d = date_str(2026, 5, 27, 0, 0, 0)
    pvd[813:830] = d                          # creation
    pvd[830:847] = d                          # modification
    pvd[847:864] = b'0' * 16 + b'\x00'        # expiration (none)
    pvd[864:881] = b'0' * 16 + b'\x00'        # effective (none)
    pvd[881] = 0x01                           # file structure version
    # rest: zeros / reserved

    # ----- Boot Record Volume Descriptor (LBA 17) -----
    br = bytearray(SECTOR)
    br[0] = 0x00                              # VD type = boot record
    br[1:6] = b'CD001'
    br[6] = 0x01                              # version
    # boot system identifier, 32 bytes, ASCII "EL TORITO SPECIFICATION" NUL-padded
    bsi = b'EL TORITO SPECIFICATION'
    br[7:7+len(bsi)] = bsi
    # 39-70: boot identifier (zeros)
    # 71-74: absolute LBA of boot catalog (LE uint32)
    br[71:75] = struct.pack('<I', LBA_BOOTCAT)
    # rest: zeros

    # ----- Volume Descriptor Set Terminator (LBA 18) -----
    term = bytearray(SECTOR)
    term[0] = 0xFF
    term[1:6] = b'CD001'
    term[6] = 0x01

    # ----- Boot Catalog (LBA 19) -----
    bc = bytearray(SECTOR)
    # Validation Entry (32 bytes)
    ve = bytearray(32)
    ve[0] = 0x01                              # header_id
    ve[1] = 0x00                              # platform_id (x86)
    # 2-3: reserved
    ve[4:28] = dchars('TOMMYOS', 24)          # id string
    # 28-29: checksum (placeholder)
    ve[30] = 0x55
    ve[31] = 0xAA
    # Compute checksum: sum of all 16 words (LE) must be 0 mod 0x10000
    s = 0
    for i in range(0, 32, 2):
        w = ve[i] | (ve[i+1] << 8)
        s = (s + w) & 0xFFFF
    chk = (0x10000 - s) & 0xFFFF
    ve[28] = chk & 0xFF
    ve[29] = (chk >> 8) & 0xFF
    bc[0:32] = ve

    # Default Entry (32 bytes)
    de = bytearray(32)
    de[0] = 0x88                              # bootable
    de[1] = 0x03                              # media type: 1.44 MB floppy
    # 2-3: load segment (0 = default 0x7C0)
    # 4: system type (copy of partition byte; 0 = unspecified)
    # 5: unused
    # 6-7: sector count (for floppy emul, 1 sector loaded then emulated)
    de[6:8] = struct.pack('<H', 1)
    # 8-11: LBA of boot image (LE uint32)
    de[8:12] = struct.pack('<I', LBA_BOOT_IMG)
    bc[32:64] = de

    # ----- Path Table L (LE) at LBA 20 -----
    ptl = bytearray(SECTOR)
    # Single entry: root directory
    # name_len(1)=1, ext_attr(1)=0, extent(4 LE)=LBA_ROOT, parent(2 LE)=1, name(1)=0
    ptl[0:10] = bytes([1, 0]) + struct.pack('<I', LBA_ROOT) + struct.pack('<H', 1) + b'\x00\x00'
    # name is single 0x00 + pad to even (already even with name+pad=2)

    # ----- Path Table M (BE) at LBA 21 -----
    ptm = bytearray(SECTOR)
    ptm[0:10] = bytes([1, 0]) + struct.pack('>I', LBA_ROOT) + struct.pack('>H', 1) + b'\x00\x00'

    # ----- Root Directory (LBA 22) -----
    root = bytearray(SECTOR)
    # "." entry (name = 0x00) and ".." entry (name = 0x01), both pointing to root
    dot = dir_record(LBA_ROOT, SECTOR, b'\x00', is_dir=True)
    dotdot = dir_record(LBA_ROOT, SECTOR, b'\x01', is_dir=True)
    off = 0
    root[off:off+len(dot)] = dot
    off += len(dot)
    root[off:off+len(dotdot)] = dotdot

    # ----- Assemble final ISO -----
    with open(iso_path, 'wb') as o:
        o.write(b'\x00' * (16 * SECTOR))     # system area (LBA 0..15)
        o.write(pvd)
        o.write(br)
        o.write(term)
        o.write(bc)
        o.write(ptl)
        o.write(ptm)
        o.write(root)
        o.write(boot_img)
        # File is now exactly TOTAL_LBA * SECTOR bytes long.

    size = os.path.getsize(iso_path)
    expected = TOTAL_LBA * SECTOR
    print(f'wrote {iso_path}')
    print(f'  size: {size} bytes ({size/1024/1024:.2f} MB)')
    print(f'  expected: {expected} bytes')
    assert size == expected, (size, expected)
    print('  boot catalog @ LBA', LBA_BOOTCAT)
    print('  boot image   @ LBA', LBA_BOOT_IMG, f'({boot_img_iso_sectors} ISO sectors)')
    print('  emulation: 1.44 MB floppy')

if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    img = os.path.join(here, 'build', 'tommy_os.img')
    iso = os.path.join(here, 'build', 'tommy_os.iso')
    build_iso(img, iso)
