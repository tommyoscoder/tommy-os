; ============================================================
; Tommy OS - Stage 1 Bootloader (fits in 512-byte MBR)
;
; Loads N_SECT kernel sectors (1..N_SECT) to LOAD_SEG:0000.
;
; Reads ONE sector at a time. Tries LBA (INT 13h AH=42h) first;
; if that's unsupported, falls back to CHS using geometry queried
; from the BIOS at runtime (INT 13h AH=08h) — NOT a hardcoded
; floppy assumption. This way the same image boots correctly on:
;   - QEMU floppy / hdd / usb
;   - Real PC USB stick (FDD / HDD / Zip emulation)
;   - Real PC HDD / SSD / SD card
; ============================================================
[BITS 16]
[ORG 0x7C00]

LOAD_SEG  equ 0x0800      ; kernel loads to linear 0x8000
N_SECT    equ 125         ; total kernel sectors to load

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    mov si, msg_loading
    call print16

    ; ---- Query drive geometry up front so the CHS fallback has
    ; ---- the right spt / heads on USB-HDD / real HDD. ----
    push es
    mov ah, 0x08
    mov dl, [boot_drive]
    xor di, di
    mov es, di
    int 0x13
    pop es
    jc  .geom_default
    mov al, cl
    and al, 0x3F           ; sectors-per-track (low 6 bits of CL)
    mov [g_spt], al
    inc dh                 ; AH=08h returns max-head; +1 = head count
    mov [g_heads], dh
    jmp .geom_ok
.geom_default:
    ; Fallback to floppy values
    mov byte [g_spt], 18
    mov byte [g_heads], 2
.geom_ok:

    ; ---- Probe LBA (INT 13h extensions). ----
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc  .no_lba
    cmp bx, 0xAA55
    jne .no_lba
    test cx, 1
    jz  .no_lba
    mov byte [have_lba], 1
.no_lba:

    ; ---- Read N_SECT sectors, one at a time. ----
    mov word [cur_lba], 1
    mov word [cur_seg], LOAD_SEG
.read_loop:
    mov ax, [cur_lba]
    cmp ax, N_SECT+1
    jae .boot

    cmp byte [have_lba], 1
    jne .chs_one

    ; ---- Single-sector LBA read ----
    mov word [dap_count], 1
    mov word [dap_off],   0
    mov ax, [cur_seg]
    mov [dap_seg], ax
    mov ax, [cur_lba]
    mov [dap_lba_lo], ax
    mov word [dap_lba_lo+2], 0
    mov word [dap_lba_hi], 0
    mov word [dap_lba_hi+2], 0

    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jnc .next

    ; LBA call failed at runtime — fall back to CHS for this and
    ; future sectors.
    mov byte [have_lba], 0
    jmp .chs_one

.chs_one:
    ; LBA -> CHS using *queried* geometry
    ;   sec = (lba % spt) + 1
    ;   tmp = (lba / spt)
    ;   head = tmp % heads
    ;   cyl  = tmp / heads
    mov ax, [cur_lba]
    xor dx, dx
    movzx bx, byte [g_spt]
    div bx                  ; AX = lba/spt, DX = lba%spt
    mov cl, dl
    inc cl                  ; CL low-6 = sector
    xor dx, dx
    movzx bx, byte [g_heads]
    div bx                  ; AX = cyl, DX = head
    mov dh, dl              ; DH = head
    ; CX bits 6-7 hold cyl high 2 bits, CH holds cyl low 8
    mov ch, al              ; cyl low 8
    shl ah, 6
    or  cl, ah              ; CL bits 6-7 = cyl high 2 bits

    push es
    mov ax, [cur_seg]
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 1
    mov dl, [boot_drive]
    int 0x13
    pop es
    jc  .disk_err

.next:
    inc word [cur_lba]
    add word [cur_seg], 32   ; advance by 512 bytes (32 paragraphs)
    jmp .read_loop

.boot:
    mov dl, [boot_drive]
    jmp LOAD_SEG:0x0000

.disk_err:
    mov si, msg_err
    call print16
.halt:
    hlt
    jmp .halt

; -- 16-bit string print (BIOS teletype) --
print16:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    jmp print16
.done:
    ret

; -- data --
boot_drive  db 0
have_lba    db 0
g_spt       db 0
g_heads     db 0
cur_lba     dw 0
cur_seg     dw 0

msg_loading db 'Tommy OS booting...', 0x0D, 0x0A, 0
msg_err     db 'Disk read error!', 0

align 4
dap:
            db 0x10              ; size
            db 0                 ; reserved
dap_count   dw 0                 ; sectors
dap_off     dw 0                 ; offset
dap_seg     dw 0                 ; segment
dap_lba_lo  dd 0                 ; LBA low
dap_lba_hi  dd 0                 ; LBA high

times 510-($-$$) db 0
dw 0xAA55
