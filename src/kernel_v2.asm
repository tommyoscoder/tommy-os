; ============================================================
; Tommy OS v2.0 - macOS-style Desktop Environment
; Kernel, Shell, Editor, Graphics, Desktop, Dock, Menu bar
; Loaded at linear 0x8000 (segment 0x0800, offset 0x0000)
; ============================================================
[BITS 16]
[ORG 0x0000]

; ---- Constants ----
VGA_MEM        equ 0xB800
SCREEN_W       equ 80
SCREEN_H       equ 25
MAX_CMD        equ 128
MAX_ED_LINES   equ 150
ED_LINE_LEN    equ 78
SCRL_MAX       equ 10          ; terminal scrollback lines

; Desktop layout rows
DOCK_ROW       equ 23          ; dock lives on row 23
WIN_TITLE_ROW  equ 1           ; per-app window title bar row
CONTENT_TOP    equ 2           ; first usable content row

; v2 desktop states
DS_DESKTOP     equ 0
DS_TERMINAL    equ 1
DS_EDITOR      equ 2
DS_ABOUT       equ 3

; ---- macOS-style colour palette (16-bg-colour mode) ----
; Menu bar: black text on light-gray bg
COL_MENUBAR    equ 0x70        ; 0111 0000  bg=7(lgray) fg=0(black)
COL_MENU_SEL   equ 0x07        ; 0000 0111  bg=0(black) fg=7(lgray)  selected item
; Desktop: blue on blue (solid fill)
COL_DESK       equ 0x11        ; 0001 0001  bg=1(blue)  fg=1(blue)
COL_DESK_TXT   equ 0x1F        ; 0001 1111  bg=1(blue)  fg=F(white)  icon text
; Window title bar colours (one per app)
COL_WIN_TERM   equ 0x1F        ; bright white on blue   - Terminal
COL_WIN_EDIT   equ 0x2F        ; bright white on green  - Editor
COL_WIN_ABOUT  equ 0x5F        ; bright white on magenta - About
; Traffic-light buttons (solid bg = the color, use 0x20 space char)
COL_TL_RED     equ 0xCC        ; light-red on light-red
COL_TL_YEL     equ 0xEE        ; yellow on yellow
COL_TL_GRN     equ 0xAA        ; light-green on light-green
COL_TL_BG      equ 0x1F        ; surrounding title bar (blue)
; Dock
COL_DOCK       equ 0x78        ; dark-gray on light-gray
COL_DOCK_SEL   equ 0x3F        ; bright-white on cyan   - focused item
; Colour attributes (v2.0 compat)
COL_NORMAL     equ 0x07
COL_BRIGHT     equ 0x0F
COL_GREEN      equ 0x0A
COL_CYAN       equ 0x0B
COL_YELLOW     equ 0x0E
COL_RED        equ 0x0C
COL_MAGENTA    equ 0x0D   ; bright magenta
COL_TITLE      equ 0x4F   ; white on red  (kept for compat)
COL_STATUS     equ 0x30   ; black on cyan (kept for compat)

; ============================================================
; ENTRY POINT
; ============================================================
kernel_main:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    mov [boot_drive], dl

    mov ax, 0x0003          ; text mode 80x25
    int 0x10
    mov ah, 0x01            ; hide cursor
    mov cx, 0x2607
    int 0x10

    ; Enable 16 background colours (disable blink) — needed for traffic lights
    mov ax, 0x1003
    mov bx, 0x0000
    int 0x10

    call clrscr

    call disk_init
    call check_first_boot
    test al, al
    jz .do_setup
    call show_login
    jmp .desktop

.do_setup:
    call first_boot_setup

.desktop:
    call desktop_main       ; v2: enter macOS-style desktop

.halt:
    hlt
    jmp .halt

; ============================================================
; CHECK FIRST BOOT — returns AL=0 if not configured
;   Tries to load config from disk; if magic matches, we're configured.
; ============================================================
check_first_boot:
    call load_config_from_disk
    cmp byte [cfg_magic], 0xAB
    jne .no
    mov al, 1
    ret
.no:
    xor al, al
    ret

; ============================================================
; FIRST BOOT SETUP WIZARD
; ============================================================
first_boot_setup:
    call clrscr
    call draw_titlebar

    mov dh, 3
    mov dl, 20
    mov bl, COL_YELLOW
    mov si, str_welcome_big
    call print_at

    mov dh, 5
    mov dl, 15
    mov bl, COL_CYAN
    mov si, str_welcome_sub
    call print_at

    mov dh, 7
    mov dl, 0
    mov bl, COL_YELLOW
    mov cx, 80
    mov al, 0xCD
    call draw_hline

    ; -- Name --
    mov dh, 9
    mov dl, 4
    mov bl, COL_BRIGHT
    mov si, str_ask_name
    call print_at

    mov dh, 9
    mov dl, 37
    call setcursor
    mov di, username
    mov cx, 31
    call readline_echo

    ; -- Password --
    mov dh, 11
    mov dl, 4
    mov bl, COL_BRIGHT
    mov si, str_ask_pass
    call print_at

    mov dh, 11
    mov dl, 37
    call setcursor
    mov di, password
    mov cx, 31
    call readline_noecho

    mov dh, 11
    mov dl, 37
    mov bl, COL_YELLOW
    mov si, str_pass_set
    call print_at

    ; -- Drives --
    call enum_drives

    ; -- Drive choice --
    mov dh, 19
    mov dl, 4
    mov bl, COL_BRIGHT
    mov si, str_ask_drive
    call print_at

    mov dh, 19
    mov dl, 37
    call setcursor
    mov di, drive_choice
    mov cx, 3
    call readline_echo

    ; -- Confirm --
    mov dh, 21
    mov dl, 4
    mov bl, COL_RED
    mov si, str_confirm
    call print_at

    mov dh, 21
    mov dl, 30
    call setcursor
    mov ah, 0x00
    int 0x16
    cmp al, 'y'
    je .do_install
    cmp al, 'Y'
    je .do_install
    jmp .installed

.do_install:
    mov byte [cfg_magic], 0xAB
    mov si, username
    mov di, cfg_username
    mov cx, 33
    rep movsb

    ; Hash (password + username salt) -> cfg_pwhash
    mov word [hp_pw_ptr], password
    mov word [hp_un_ptr], username
    call hash_password
    mov eax, [hp_result]
    mov [cfg_pwhash], eax

    ; Wipe plaintext password from RAM
    mov di, password
    mov cx, 33
    xor al, al
    rep stosb

    ; Persist config to LBA 64 (best-effort; ignore failure)
    call save_config_to_disk
    jmp .installed

.installed:
    mov byte [cfg_magic], 0xAB  ; always mark installed

    call clrscr
    call draw_titlebar

    mov dh, 10
    mov dl, 24
    mov bl, COL_GREEN
    mov si, str_install_ok
    call print_at

    mov dh, 12
    mov dl, 22
    mov bl, COL_BRIGHT
    mov si, str_press_enter
    call print_at

    call wait_enter
    ret

; ============================================================
; ENUMERATE DRIVES (shows drive number, kind, and size in MB so
; the user can tell their USB stick from the boot disk).
; ============================================================
enum_drives:
    mov dh, 13
    mov dl, 4
    mov bl, COL_YELLOW
    mov si, str_drives_hdr
    call print_at

    mov byte [drv_row], 14

    ; Floppies (BIOS DL 0x00, 0x01)
    mov byte [drv_cur], 0x00
.fdd_loop:
    mov dl, [drv_cur]
    call query_drive
    jc .fdd_skip
    mov al, [drv_cur]
    mov bl, 0                  ; 0 = floppy label
    call print_drive_line
.fdd_skip:
    inc byte [drv_cur]
    cmp byte [drv_cur], 0x02
    jne .fdd_loop

    ; Hard / USB drives (BIOS DL 0x80..0x83)
    mov byte [drv_cur], 0x80
.hdd_loop:
    mov dl, [drv_cur]
    call query_drive
    jc .hdd_skip
    mov al, [drv_cur]
    mov bl, 1                  ; 1 = hard/usb label
    call print_drive_line
.hdd_skip:
    inc byte [drv_cur]
    cmp byte [drv_cur], 0x84
    jne .hdd_loop
    ret

; ----- print_drive_line: AL = BIOS drive #, BL = 0 (fdd) or 1 (hdd)
;       EAX (from query_drive) = MB size — pulled from cached var.
print_drive_line:
    push ax
    push bx
    push cx
    push dx

    mov dh, [drv_row]

    ; "  drive "
    mov dl, 2
    mov bl, COL_GREEN
    mov si, str_drv_pre
    call print_at

    ; drive number (for HDDs, show 0..3 instead of 0x80..)
    mov dh, [drv_row]
    mov dl, 10
    call setcursor
    pop dx
    push dx
    pop ax                     ; restore AL = BIOS drive number
    push ax
    cmp al, 0x80
    jb .as_is
    sub al, 0x80
.as_is:
    add al, '0'
    call putc_at_cursor

    ; "  " kind label
    mov al, ' '
    call putc_at_cursor
    mov al, ' '
    call putc_at_cursor
    pop ax
    push ax
    cmp al, 0x80
    jae .hdd_kind
    mov si, str_drv_fdd
    jmp .kind_done
.hdd_kind:
    mov si, str_drv_hdd
.kind_done:
    call print_str_at_cursor

    ; size in MB, right-aligned-ish at col 28
    mov dh, [drv_row]
    mov dl, 28
    call setcursor
    mov eax, [drv_size_mb]
    cmp eax, 0
    jne .has_size
    mov si, str_drv_unknown
    call print_str_at_cursor
    jmp .size_done
.has_size:
    ; print EAX as decimal (32-bit)
    call print_dec_eax_at_cursor
    mov si, str_drv_mb
    call print_str_at_cursor
.size_done:

    inc byte [drv_row]

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----- query_drive: DL = BIOS drive number
;   Output: CF=0 if drive exists, EAX = approx MB, also in [drv_size_mb]
;           CF=1 if drive doesn't respond.
;   Uses INT 13h AH=48h (extended drive params) when available,
;   falls back to AH=08h CHS.
query_drive:
    push bx
    push cx
    push dx
    push si
    push di
    push es
    push ds

    push cs
    pop ds                  ; DS = CS for our locals/buffer

    mov [q_dl], dl
    mov dword [drv_size_mb], 0

    ; Step 1: existence test via AH=08h. NOTE: int 13h AH=08h
    ; CLOBBERS DL (returns drive count) and DH (returns max head),
    ; so we cache the returns immediately and reload DL from q_dl.
    xor di, di
    mov es, di
    mov ah, 0x08
    mov dl, [q_dl]
    int 0x13
    jc .none

    ; Cache CHS values (max cyl, max head, spt) from the BIOS regs.
    ;   CH      = cyl low 8 bits
    ;   CL[7:6] = cyl high 2 bits
    ;   CL[5:0] = sectors-per-track
    ;   DH      = max head
    mov [q_max_cyl_lo], ch
    mov [q_max_head], dh
    mov al, cl
    rol al, 2
    and al, 0x03
    mov [q_max_cyl_hi], al
    mov al, cl
    and al, 0x3F
    mov [q_spt], al

    ; For floppies (DL < 0x80), use CHS directly (AH=48h unreliable).
    cmp byte [q_dl], 0x80
    jb .from_chs

    ; Step 2: AH=48h for HDD/USB (accurate even on > 8 GB drives)
    mov word [ext_buf], 30
    mov si, ext_buf
    mov ah, 0x48
    mov dl, [q_dl]
    int 0x13
    jc .from_chs

    mov eax, [ext_buf+16]
    cmp eax, 0
    je .from_chs
    shr eax, 11
    mov [drv_size_mb], eax
    jmp .ok

.from_chs:
    ; total = (max_cyl+1) * (max_head+1) * spt
    movzx eax, byte [q_max_cyl_lo]
    movzx ebx, byte [q_max_cyl_hi]
    shl ebx, 8
    or eax, ebx
    inc eax                 ; cyls
    movzx ebx, byte [q_max_head]
    inc ebx
    mul ebx
    movzx ebx, byte [q_spt]
    mul ebx
    shr eax, 11
    ; Floppies smaller than 1 MB should still show as 1 MB so the
    ; user sees them in the list.
    cmp eax, 0
    jne .have
    mov eax, 1
.have:
    mov [drv_size_mb], eax
.ok:
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    clc
    ret
.none:
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    stc
    ret

; ----- print_dec_eax_at_cursor: print EAX (unsigned 32-bit) as
;       decimal at current cursor.
print_dec_eax_at_cursor:
    push eax
    push ebx
    push ecx
    push edx

    mov ecx, 0
    mov ebx, 10
    cmp eax, 0
    jne .pd_loop
    mov al, '0'
    call putc_at_cursor
    jmp .pd_done
.pd_loop:
    cmp eax, 0
    je .pd_emit
    xor edx, edx
    div ebx
    push edx
    inc ecx
    jmp .pd_loop
.pd_emit:
    cmp ecx, 0
    je .pd_done
    pop eax
    add al, '0'
    call putc_at_cursor
    dec ecx
    jmp .pd_emit
.pd_done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ============================================================
; SHOW LOGIN
; ============================================================
show_login:
    call clrscr
    call draw_titlebar

    mov dh, 3
    mov dl, 20
    mov bl, COL_YELLOW
    mov si, str_logo1
    call print_at

    mov dh, 4
    mov dl, 20
    mov bl, COL_BRIGHT
    mov si, str_logo2
    call print_at

    mov dh, 5
    mov dl, 20
    mov bl, COL_CYAN
    mov si, str_logo3
    call print_at

    mov dh, 6
    mov dl, 20
    mov bl, COL_YELLOW
    mov si, str_logo4
    call print_at

    mov dh, 8
    mov dl, 0
    mov bl, COL_YELLOW
    mov cx, 80
    mov al, 0xCD
    call draw_hline

    mov dh, 10
    mov dl, 28
    mov bl, COL_YELLOW
    mov si, str_no_wifi
    call print_at

    mov dh, 12
    mov dl, 4
    mov bl, COL_YELLOW
    mov si, str_welcome_back
    call print_at

    mov dh, 12
    mov dl, 24
    mov bl, COL_GREEN
    mov si, cfg_username
    call print_at

    mov dh, 14
    mov dl, 4
    mov bl, COL_BRIGHT
    mov si, str_login_user
    call print_at

    mov dh, 14
    mov dl, 16
    call setcursor
    mov di, login_buf
    mov cx, 31
    call readline_echo

    mov dh, 16
    mov dl, 4
    mov bl, COL_BRIGHT
    mov si, str_login_pass
    call print_at

    mov dh, 16
    mov dl, 16
    call setcursor
    mov di, login_buf
    mov cx, 31
    call readline_noecho

    ; Hash the entered password (salted with stored username), compare to cfg_pwhash
    mov word [hp_pw_ptr], login_buf
    mov word [hp_un_ptr], cfg_username
    call hash_password

    ; Compare hash, then wipe login_buf either way
    mov eax, [hp_result]
    cmp eax, [cfg_pwhash]
    pushf
    mov di, login_buf
    mov cx, 33
    xor al, al
    rep stosb
    popf
    je .ok

    mov dh, 18
    mov dl, 4
    mov bl, COL_RED
    mov si, str_wrong_pass
    call print_at
    call wait_enter
    jmp show_login

.ok:
    ret

; ============================================================
; SHELL MAIN LOOP  (v2: runs inside a Terminal window)
; ============================================================
shell_main:
    mov byte [desk_state], DS_TERMINAL
    call clrscr
    call draw_titlebar          ; menu bar row 0
    call draw_win_titlebar      ; window title bar row 1 (traffic lights)
    call draw_statusbar         ; dock row 23

    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_shell_greet
    call print_at

    mov dh, 3
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_shell_hint
    call print_at

    mov dh, 4
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline

    mov byte [sh_row], 6

.loop:
    call shell_prompt

    mov di, cmd_buf
    mov cx, MAX_CMD - 1
    mov byte [hist_enabled], 1
    mov byte [hist_view], 0
    call readline_echo
    mov byte [hist_enabled], 0

    mov di, cmd_buf
    call hist_push

    call exec_cmd
    jmp .loop

; ============================================================
; SHELL PROMPT
; ============================================================
shell_prompt:
    movzx ax, byte [sh_row]
    cmp ax, SCREEN_H - 3
    jl .ok
    call shell_scroll
.ok:
    ; Write "TOMMY> " directly to VGA
    push es
    mov ax, VGA_MEM
    mov es, ax
    movzx bx, byte [sh_row]
    imul bx, bx, SCREEN_W * 2

    mov word [es:bx+0],  0x0C54   ; T - bright red
    mov word [es:bx+2],  0x0E4F   ; O - bright yellow
    mov word [es:bx+4],  0x0A4D   ; M - bright green
    mov word [es:bx+6],  0x0B4D   ; M - bright cyan
    mov word [es:bx+8],  0x0D59   ; Y - bright magenta
    mov word [es:bx+10], 0x0F3E   ; > - bright white
    mov word [es:bx+12], 0x0720   ; space
    pop es

    mov dh, [sh_row]
    mov dl, 7
    call setcursor
    ret

; ============================================================
; EXECUTE COMMAND
; ============================================================
exec_cmd:
    mov si, cmd_buf
    call skip_spaces

    cmp byte [si], 0
    je .done

    mov di, s_help
    call cmd_match
    je .do_help

    mov di, s_clear
    call cmd_match
    je .do_clear

    mov di, s_cls
    call cmd_match
    je .do_clear

    mov di, s_ver
    call cmd_match
    je .do_ver

    mov di, s_about
    call cmd_match
    je .do_about

    mov di, s_whoami
    call cmd_match
    je .do_whoami

    mov di, s_echo
    call cmd_match
    je .do_echo

    mov di, s_ls
    call cmd_match
    je .do_ls

    mov di, s_edit
    call cmd_match
    je .do_edit

    mov di, s_asm
    call cmd_match
    je .do_asm

    mov di, s_mem
    call cmd_match
    je .do_mem

    mov di, s_gfx
    call cmd_match
    je .do_graphics

    mov di, s_graphics
    call cmd_match
    je .do_graphics

    mov di, s_date
    call cmd_match
    je .do_date

    mov di, s_time
    call cmd_match
    je .do_time

    mov di, s_uptime
    call cmd_match
    je .do_uptime

    mov di, s_random
    call cmd_match
    je .do_random

    mov di, s_beep
    call cmd_match
    je .do_beep

    mov di, s_color
    call cmd_match
    je .do_color

    mov di, s_sysinfo
    call cmd_match
    je .do_sysinfo

    mov di, s_cpuid
    call cmd_match
    je .do_cpuid

    mov di, s_calc
    call cmd_match
    je .do_calc

    mov di, s_snake
    call cmd_match
    je .do_snake

    mov di, s_reboot
    call cmd_match
    je .do_reboot

    mov di, s_shutdown
    call cmd_match
    je .do_shutdown

    mov di, s_run
    call cmd_match
    je .do_tc_run

    mov di, s_tc
    call cmd_match
    je .do_tc_run

    mov di, s_manual
    call cmd_match
    je .do_manual

    mov di, s_save
    call cmd_match
    je .do_save

    mov di, s_load
    call cmd_match
    je .do_load

    mov di, s_dir
    call cmd_match
    je .do_dir

    mov di, s_cat
    call cmd_match
    je .do_cat

    mov di, s_del
    call cmd_match
    je .do_del

    mov di, s_write
    call cmd_match
    je .do_write

    mov di, s_read
    call cmd_match
    je .do_read

    mov di, s_df
    call cmd_match
    je .do_df

    mov di, s_fsinit
    call cmd_match
    je .do_fsinit

    mov di, s_hist
    call cmd_match
    je .do_hist

    mov di, s_hist2
    call cmd_match
    je .do_hist

    mov di, s_clock
    call cmd_match
    je .do_clock

    mov di, s_hex
    call cmd_match
    je .do_hex

    mov di, s_ttt
    call cmd_match
    je .do_ttt

    mov di, s_tictactoe
    call cmd_match
    je .do_ttt

    mov di, s_motd
    call cmd_match
    je .do_motd

    mov di, s_rename
    call cmd_match
    je .do_rename

    mov di, s_kedit
    call cmd_match
    je .do_kedit

    mov di, s_ide
    call cmd_match
    je .do_ide

    ; Unknown
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_unknown
    call print_at
    call sh_newline
    jmp .done

.do_help:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_help_title
    call print_at
    call sh_newline
    mov si, str_help_body
.help_loop:
    cmp byte [si], 0
    je .help_done
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    call print_line_si       ; prints until 0x0A or 0
    call sh_newline
    jmp .help_loop
.help_done:
    call sh_newline
    jmp .done

.do_clear:
    call clrscr
    call draw_titlebar
    call draw_win_titlebar
    call draw_statusbar

    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_shell_greet
    call print_at

    mov dh, 3
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_shell_hint
    call print_at

    mov dh, 4
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline

    mov byte [sh_row], 6
    jmp .done

.do_ver:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_ver
    call print_at
    call sh_newline
    jmp .done

.do_whoami:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, cfg_username
    call print_at
    call sh_newline
    jmp .done

.do_echo:
    ; Skip "echo "
    mov si, cmd_buf
    call skip_spaces
    add si, 4
    call skip_spaces
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_NORMAL
    call print_at
    call sh_newline
    jmp .done

.do_ls:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_ls
    call print_at
    call sh_newline
    call sh_newline
    jmp .done

.do_edit:
    ; If a filename argument follows "edit", load that file first
    call skip_first_word
    call arg_after_cmd
    cmp byte [arg_name], 0
    je .edit_open
    call fs_ensure_mounted
    mov si, arg_name
    call fs_find
    jne .edit_open              ; file not found: still open editor (new file)
    push ax
    push di
    push cx
    mov di, ed_buf
    mov cx, MAX_ED_LINES * ED_LINE_LEN
    xor al, al
    rep stosb
    pop cx
    pop di
    pop ax
    call fs_read_slot
    call tc_recount_lines
.edit_open:
    call text_editor
    call clrscr
    call draw_titlebar
    call draw_statusbar
    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_shell_greet
    call print_at
    mov dh, 3
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_shell_hint
    call print_at
    mov dh, 4
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline
    mov byte [sh_row], 6
    ; If user hit Ctrl-R inside the editor, run the program right away.
    cmp byte [ed_exit_run], 1
    jne .done
    mov byte [ed_exit_run], 0
    call tc_run
    jmp .done

.do_asm:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_asm
    call print_at
    call sh_newline
    call sh_newline
    jmp .done

.do_mem:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_mem
    call print_at
    call sh_newline
    call sh_newline
    jmp .done

.do_graphics:
    call graphics_mode
    call clrscr
    call draw_titlebar
    call draw_statusbar
    mov byte [sh_row], 6
    jmp .done

.do_about:
    call sh_newline
    mov si, str_about
    mov bl, COL_CYAN
    call sh_print_multiline
    call sh_newline
    jmp .done

.do_sysinfo:
    call sh_newline
    call cmd_sysinfo
    jmp .done

.do_cpuid:
    call sh_newline
    call cmd_cpuid
    jmp .done

.do_calc:
    call sh_newline
    call cmd_calc
    jmp .done

.do_snake:
    call gfx_app_snake_entry
    call clrscr
    call draw_titlebar
    call draw_statusbar
    mov byte [sh_row], 6
    jmp .done

.do_date:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_BRIGHT
    mov si, str_date_l
    call print_at
    mov dh, [sh_row]
    mov dl, 16                  ; len of "  Date (Y-M-D): "
    call setcursor
    ; BIOS get RTC date: AH=04h, CX=YYYY (BCD), DH=MM, DL=DD
    mov ah, 0x04
    int 0x1A
    push dx
    push cx
    mov al, ch                  ; century BCD
    call print_bcd_at_cursor
    pop cx
    push cx
    mov al, cl                  ; year-in-century BCD
    call print_bcd_at_cursor
    mov al, '-'
    call putc_at_cursor
    pop cx
    pop dx
    mov al, dh
    call print_bcd_at_cursor
    mov al, '-'
    call putc_at_cursor
    mov al, dl
    call print_bcd_at_cursor
    call sh_newline
    jmp .done

.do_time:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_BRIGHT
    mov si, str_time_l
    call print_at
    mov dh, [sh_row]
    mov dl, 16                  ; len of "  Time (H:M:S): "
    call setcursor
    ; BIOS get RTC time: AH=02h, CH=HH, CL=MM, DH=SS (BCD)
    mov ah, 0x02
    int 0x1A
    push dx
    mov al, ch
    call print_bcd_at_cursor
    mov al, ':'
    call putc_at_cursor
    mov al, cl
    call print_bcd_at_cursor
    mov al, ':'
    call putc_at_cursor
    pop dx
    mov al, dh
    call print_bcd_at_cursor
    call sh_newline
    jmp .done

.do_uptime:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_BRIGHT
    mov si, str_uptime_l
    call print_at
    mov dh, [sh_row]
    mov dl, 24                  ; len of "  Ticks since midnight: "
    call setcursor
    ; BIOS tick count: AH=00, returns CX:DX
    xor ax, ax
    int 0x1A
    mov ax, dx
    call print_dec_at_cursor
    call sh_newline
    jmp .done

.do_random:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_random_l
    call print_at
    mov dh, [sh_row]
    mov dl, 10                  ; len of "  Random: "
    call setcursor
    xor ax, ax
    int 0x1A
    mov ax, dx
    xor ax, cx
    and ax, 0x3FF
    call print_dec_at_cursor
    call sh_newline
    jmp .done

.do_beep:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_beep_l
    call print_at
    call sh_newline
    ; PC speaker: enable, set freq via 8254 ch 2, wait, disable
    mov al, 0xB6
    out 0x43, al
    mov ax, 1193        ; ~1000 Hz divisor
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    ; small delay loop
    mov cx, 0x0008
.bp_outer:
    push cx
    mov cx, 0xFFFF
.bp_inner:
    dec cx
    jnz .bp_inner
    pop cx
    loop .bp_outer
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    jmp .done

.do_color:
    ; Cycle through a small palette of title-bar attributes
    mov al, [title_color]
    cmp al, 0x4F
    je .col_to_green
    cmp al, 0x2F
    je .col_to_blue
    cmp al, 0x1F
    je .col_to_magenta
    cmp al, 0x5F
    je .col_to_red
    mov al, 0x4F
    jmp .col_set
.col_to_green:
    mov al, 0x2F
    jmp .col_set
.col_to_blue:
    mov al, 0x1F
    jmp .col_set
.col_to_magenta:
    mov al, 0x5F
    jmp .col_set
.col_to_red:
    mov al, 0x4F
.col_set:
    mov [title_color], al
    call draw_titlebar
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_color_l
    call print_at
    call sh_newline
    jmp .done

.do_reboot:
    mov ax, 0x0040
    mov ds, ax
    mov word [0x0072], 0x1234
    jmp 0xFFFF:0x0000

.do_shutdown:
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
    ; QEMU/Bochs fallback
    mov ax, 0x2000
    mov dx, 0x604
    out dx, ax
    hlt

.do_tc_run:
    call tc_run
    jmp .done

.do_manual:
    call sh_newline
    mov si, str_manual
    mov bl, COL_CYAN
    call sh_print_multiline
    jmp .done

.do_save:
    call tc_save
    jmp .done

.do_load:
    call tc_load
    jmp .done

.do_dir:
    call cmd_dir
    jmp .done

.do_cat:
    call cmd_cat
    jmp .done

.do_del:
    call cmd_del
    jmp .done

.do_write:
    call cmd_write
    jmp .done

.do_read:
    call cmd_read
    jmp .done

.do_df:
    call cmd_df
    jmp .done

.do_fsinit:
    call cmd_fs_init
    jmp .done

.do_hist:
    call cmd_hist
    jmp .done

.do_clock:
    call cmd_clock
    jmp .done

.do_hex:
    call cmd_hexdump
    jmp .done

.do_ttt:
    call cmd_ttt
    jmp .done

.do_motd:
    call cmd_motd
    jmp .done

.do_rename:
    call cmd_rename
    jmp .done

.do_kedit:
    ; Kernel binary editor
    mov byte [ed_mode], 1
    call kernel_editor
    call clrscr
    call draw_titlebar
    call draw_statusbar
    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_shell_greet
    call print_at
    mov dh, 3
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_shell_hint
    call print_at
    mov dh, 4
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline
    mov byte [sh_row], 6
    jmp .done

.do_ide:
    ; Tommy's C IDE
    call ide_open
    call clrscr
    call draw_titlebar
    call draw_statusbar
    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_shell_greet
    call print_at
    mov dh, 3
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_shell_hint
    call print_at
    mov dh, 4
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline
    mov byte [sh_row], 6
    cmp byte [ed_exit_run], 1
    jne .done
    mov byte [ed_exit_run], 0
    call tc_run

.done:
    call sh_newline
    ret

; ============================================================
; PRINT CURRENT LINE from SI until 0x0A or 0 (doesn't advance SI past newline)
; DH=row, DL=col, BL=attr  — advances SI to char after 0x0A
; ============================================================
print_line_si:
    push es
    push ax
    push bx
    push cx
    push dx

    mov ax, VGA_MEM
    mov es, ax

.cl:
    mov al, [si]
    inc si
    cmp al, 0
    je .cldone
    cmp al, 0x0A
    je .cldone

    push ax              ; preserve char in AL
    movzx cx, dh
    imul cx, cx, SCREEN_W
    movzx ax, dl
    add cx, ax
    shl cx, 1
    mov di, cx           ; DI = VGA offset (DI is valid for addressing)
    pop ax

    mov [es:di], al
    mov [es:di+1], bl
    inc dl
    jmp .cl
.cldone:
    pop dx
    pop cx
    pop bx
    pop ax
    pop es
    ret

; ============================================================
; SH_NEWLINE — increment shell row with scroll
; ============================================================
sh_newline:
    inc byte [sh_row]
    movzx ax, byte [sh_row]
    cmp ax, SCREEN_H - 2
    jl .ok
    call shell_scroll
.ok:
    ret

; ============================================================
; SHELL SCROLL — scroll content area up one line
; ============================================================
shell_scroll:
    push ds
    push es
    push si
    push di
    push cx
    push ax

    ; Save VGA row 5 into the scrollback ring buffer BEFORE scrolling.
    ; DS is still CS here (kernel segment).  We need DS=VGA for source and
    ; ES=CS for the scrl_buf destination, then use rep movsw.
    push bx
    push cs
    pop es                          ; ES = CS (scrl_buf lives here)
    mov ax, VGA_MEM
    mov ds, ax                      ; DS = VGA (row 5 source)
    movzx bx, word [es:scrl_head]
    imul bx, bx, SCREEN_W * 2
    add bx, scrl_buf
    mov di, bx                      ; ES:DI = destination in scrl_buf
    mov si, 5 * SCREEN_W * 2       ; DS:SI = VGA row 5
    mov cx, SCREEN_W
    rep movsw
    ; advance ring head
    movzx bx, word [es:scrl_head]
    inc bx
    cmp bx, SCRL_MAX
    jl .scrl_head_ok
    xor bx, bx
.scrl_head_ok:
    mov [es:scrl_head], bx
    ; cap scrl_n at SCRL_MAX
    movzx bx, word [es:scrl_n]
    cmp bx, SCRL_MAX
    jge .scrl_n_cap
    inc bx
    mov [es:scrl_n], bx
.scrl_n_cap:
    pop bx
    ; Now set DS=ES=VGA for the real scroll
    mov ax, VGA_MEM
    mov es, ax                      ; restore ES = VGA

    ; Copy rows 6..23 up by 1 (preserve rows 0-5 header)
    mov si, 6 * SCREEN_W * 2
    mov di, 5 * SCREEN_W * 2
    mov cx, (SCREEN_H - 7) * SCREEN_W
    rep movsw

    ; Clear the last content row
    mov di, (SCREEN_H - 3) * SCREEN_W * 2
    mov cx, SCREEN_W
    mov ax, 0x0720
    rep stosw

    pop ax
    pop cx
    pop di
    pop si
    pop es
    pop ds
    dec byte [sh_row]
    ret

; ============================================================
; TEXT EDITOR
; ============================================================
text_editor:
    call clrscr

    ; Header bar color depends on ed_mode
    push es
    mov ax, VGA_MEM
    mov es, ax
    xor di, di
    mov cx, 80
    mov ah, 0x1F                ; default: white on blue
    cmp byte [ed_mode], 1
    je .ehdr_kern
    cmp byte [ed_mode], 2
    je .ehdr_ide
    jmp .ehdr_draw
.ehdr_kern:
    mov ah, 0x4F                ; white on red (kernel editor)
    jmp .ehdr_draw
.ehdr_ide:
    mov ah, 0x2F                ; white on green (IDE)
.ehdr_draw:
.ehdr:
    mov byte [es:di], ' '
    mov byte [es:di+1], ah
    add di, 2
    loop .ehdr

    ; Grey footer bar row 24
    mov di, 24 * SCREEN_W * 2
    mov cx, 80
    mov ah, 0x70
.eftr:
    mov byte [es:di], ' '
    mov byte [es:di+1], ah
    add di, 2
    loop .eftr
    pop es

    ; Header text
    mov dh, 0
    mov dl, 0
    cmp byte [ed_mode], 1
    je .etitle_kern
    cmp byte [ed_mode], 2
    je .etitle_ide
    mov bl, 0x1F
    mov si, str_ed_title
    jmp .etitle_print
.etitle_kern:
    mov bl, 0x4F
    mov si, str_kd_title
    jmp .etitle_print
.etitle_ide:
    mov bl, 0x2F
    mov si, str_ide_title
.etitle_print:
    call print_at

    ; Footer text + set ed_footer_ptr
    mov word [ed_footer_ptr], str_ed_keys
    mov dh, 24
    mov dl, 0
    mov bl, 0x70
    cmp byte [ed_mode], 2
    jne .efkeys_normal
    mov word [ed_footer_ptr], str_ide_keys
    mov si, str_ide_keys
    jmp .efkeys_print
.efkeys_normal:
    cmp byte [ed_mode], 1
    jne .efkeys_std
    mov word [ed_footer_ptr], str_kd_keys
    mov si, str_kd_keys
    jmp .efkeys_print
.efkeys_std:
    mov si, str_ed_keys
.efkeys_print:
    call print_at

    ; Init editor state
    mov word [ed_lines], 1
    mov word [ed_line], 0
    mov word [ed_col], 0
    mov word [ed_top], 0

    ; Clear buffer only in normal mode (kedit loads its own content)
    cmp byte [ed_mode], 1
    je .no_clr
    mov di, ed_buf
    mov cx, MAX_ED_LINES * ED_LINE_LEN
    xor al, al
    rep stosb
.no_clr:

    call ed_redraw

.eloop:
    call ed_show_cur
    mov ah, 0x00
    int 0x16

    cmp ah, 0x01            ; ESC = quit
    je .equit

    cmp ah, 0x48            ; UP
    je .eup

    cmp ah, 0x50            ; DOWN
    je .edown

    cmp ah, 0x4B            ; LEFT
    je .eleft

    cmp ah, 0x4D            ; RIGHT
    je .eright

    cmp ah, 0x47            ; HOME
    je .ehome

    cmp ah, 0x4F            ; END
    je .eend

    cmp al, 0x0D            ; ENTER = new line
    je .eenter

    cmp al, 0x08            ; BACKSPACE
    je .ebksp

    cmp ah, 0x53            ; DEL key
    je .edel

    cmp al, 0x13            ; Ctrl-S = save
    je .esave
    cmp al, 0x0C            ; Ctrl-L = load
    je .eload
    cmp al, 0x12            ; Ctrl-R = run
    je .erun
    cmp al, 0x17            ; Ctrl-W = write kernel (kedit mode only)
    je .ewrite_kern

    ; Printable char
    cmp al, 0x20
    jl .eloop
    call ed_put_char
    call ed_redraw
    jmp .eloop

.esave:
    call ed_quick_save
    mov si, str_ed_saved
    call ed_flash_footer
    jmp .eloop

.eload:
    call ed_quick_load
    call ed_redraw
    mov si, str_ed_loaded
    call ed_flash_footer
    jmp .eloop

.erun:
    mov byte [ed_exit_run], 1
    mov byte [ed_mode], 0
    ret

.ewrite_kern:
    cmp byte [ed_mode], 1       ; only active in kernel editor mode
    jne .eloop
    call ed_kern_write
    jmp .eloop

.eup:
    cmp word [ed_line], 0
    je .eloop
    dec word [ed_line]
    call ed_clamp_col
    call ed_scroll_adj
    call ed_redraw
    jmp .eloop

.edown:
    mov ax, [ed_lines]
    dec ax
    cmp [ed_line], ax
    jge .eloop
    inc word [ed_line]
    call ed_clamp_col
    call ed_scroll_adj
    call ed_redraw
    jmp .eloop

.eleft:
    cmp word [ed_col], 0
    je .eloop
    dec word [ed_col]
    jmp .eloop

.eright:
    call ed_cur_linelen
    cmp [ed_col], ax
    jge .eloop
    inc word [ed_col]
    jmp .eloop

.ehome:
    mov word [ed_col], 0
    jmp .eloop

.eend:
    call ed_cur_linelen
    mov [ed_col], ax
    jmp .eloop

.eenter:
    call ed_insert_line
    inc word [ed_line]
    mov word [ed_col], 0
    call ed_scroll_adj
    call ed_redraw
    jmp .eloop

.ebksp:
    call ed_bksp
    call ed_redraw
    jmp .eloop

.edel:
    call ed_del_char
    call ed_redraw
    jmp .eloop

.equit:
    mov byte [ed_exit_run], 0
    mov byte [ed_mode], 0
    ret

; ---- ed_quick_save: write ed_buf to disk slot at LBA 65 ----
ed_quick_save:
    pusha
    mov ax, cs
    mov [file_dap_seg], ax
    mov ah, 0x43
    mov al, 0
    mov dl, [boot_drive]
    mov si, file_dap
    int 0x13
    popa
    ret

; ---- ed_quick_load: zero ed_buf then read disk slot ----
ed_quick_load:
    pusha
    mov di, ed_buf
    mov cx, MAX_ED_LINES * ED_LINE_LEN
    xor al, al
    rep stosb
    mov ax, cs
    mov [file_dap_seg], ax
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, file_dap
    int 0x13
    call tc_recount_lines
    popa
    ret

; ---- ed_flash_footer: SI = zero-terminated message, paints it on
;      row 24 with bright color, then restores the regular key hint.
ed_flash_footer:
    pusha
    push si
    ; Clear row 24 to dark
    mov dh, 24
    mov dl, 0
    mov cx, 80
    mov al, ' '
    mov bl, 0x20            ; black on green
    call draw_hline
    pop si
    mov dh, 24
    mov dl, 2
    mov bl, 0x2F            ; bright white on green
    call print_at
    ; Brief delay
    mov cx, 0x0014
.fl_outer:
    push cx
    mov cx, 0xFFFF
.fl_inner:
    dec cx
    jnz .fl_inner
    pop cx
    loop .fl_outer
    ; Restore regular footer (use ed_footer_ptr for mode-correct string)
    mov dh, 24
    mov dl, 0
    mov cx, 80
    mov al, ' '
    mov bl, 0x70
    call draw_hline
    mov dh, 24
    mov dl, 0
    mov bl, 0x70
    mov si, [ed_footer_ptr]
    call print_at
    popa
    ret

; ---- ed_cur_linelen: AX = length of current line ----
ed_cur_linelen:
    push si
    mov si, [ed_line]
    imul si, si, ED_LINE_LEN
    add si, ed_buf          ; SI = start of current line
    xor ax, ax
.lc:
    cmp ax, ED_LINE_LEN
    jge .done
    mov bx, si
    add bx, ax              ; BX = SI + AX (valid: BX is base reg)
    cmp byte [bx], 0
    je .done
    inc ax
    jmp .lc
.done:
    pop si
    ret

; ---- ed_clamp_col ----
ed_clamp_col:
    call ed_cur_linelen
    cmp [ed_col], ax
    jle .ok
    mov [ed_col], ax
.ok:
    ret

; ---- ed_scroll_adj ----
ed_scroll_adj:
    mov ax, [ed_line]
    cmp ax, [ed_top]
    jl .scroll_up_adj
    ; Check if below visible area
    mov bx, [ed_top]
    add bx, 22              ; 22 visible rows (rows 1-22)
    cmp ax, bx
    jl .ok_adj
    mov bx, ax
    sub bx, 21
    mov [ed_top], bx
    ret
.scroll_up_adj:
    mov [ed_top], ax
.ok_adj:
    ret

; ---- ed_put_char: insert AL at cursor ----
ed_put_char:
    push si
    push di
    push ax
    push bx
    push cx

    mov bx, [ed_line]
    imul bx, bx, ED_LINE_LEN
    add bx, ed_buf          ; BX = line base

    mov cx, [ed_col]
    cmp cx, ED_LINE_LEN - 1
    jge .done

    ; Shift chars right: from (linelen-1) down to col
    push ax                 ; save char
    call ed_cur_linelen     ; AX = linelen
    cmp ax, ED_LINE_LEN - 1
    jge .pop_done           ; line full

    ; SI = BX + linelen - 1 (last char)
    mov si, bx
    add si, ax              ; SI = end of text
    ; DI = SI + 1 (destination: one right)
    mov di, si
    inc di

    ; shift from si down to bx+col
    mov ax, [ed_col]
    mov cx, [ed_line]       ; reuse cx temporarily
    call ed_cur_linelen     ; AX = linelen again
    mov cx, ax
    sub cx, [ed_col]        ; cx = chars to shift
    jz .no_shift

.shift_right:
    mov al, [si]
    mov [di], al
    dec si
    dec di
    loop .shift_right

.no_shift:
    pop ax                  ; restore char to insert
    ; Write char at BX + col
    mov si, bx
    add si, [ed_col]
    mov [si], al
    inc word [ed_col]
    jmp .done

.pop_done:
    pop ax
.done:
    pop cx
    pop bx
    pop ax
    pop di
    pop si
    ret

; ---- ed_bksp: delete char before cursor ----
ed_bksp:
    cmp word [ed_col], 0
    je .at_bol
    dec word [ed_col]
    call ed_del_char
    ret
.at_bol:
    ; merge with previous line (simplified: just move cursor up)
    cmp word [ed_line], 0
    je .done
    dec word [ed_line]
    call ed_cur_linelen
    mov [ed_col], ax
.done:
    ret

; ---- ed_del_char: delete char at cursor ----
ed_del_char:
    push si
    push di
    push cx

    mov si, [ed_line]
    imul si, si, ED_LINE_LEN
    add si, ed_buf

    mov di, si
    add di, [ed_col]        ; DI = cursor pos in line
    mov si, di
    inc si                  ; SI = char after cursor

    ; Shift left
    mov cx, ED_LINE_LEN
    sub cx, [ed_col]
    dec cx
    jz .clear_last
.del_shift:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .del_shift

.clear_last:
    ; Zero the last position
    mov di, [ed_line]
    imul di, di, ED_LINE_LEN
    add di, ed_buf
    add di, ED_LINE_LEN - 1
    mov byte [di], 0

    pop cx
    pop di
    pop si
    ret

; ---- ed_insert_line: insert blank line after current ----
ed_insert_line:
    mov ax, [ed_lines]
    cmp ax, MAX_ED_LINES - 1
    jge .done

    ; Shift lines down from (lines-1) to (ed_line+1)
    ; Use SI=source, DI=dest for rep movsb
    mov ax, [ed_lines]      ; ax = count
    dec ax                  ; ax = last index

.shift:
    cmp ax, [ed_line]
    jle .clear_new

    ; DI = line[ax+1], SI = line[ax]
    push ax
    inc ax
    imul ax, ax, ED_LINE_LEN
    add ax, ed_buf
    mov di, ax
    pop ax

    push ax
    imul ax, ax, ED_LINE_LEN
    add ax, ed_buf
    mov si, ax
    pop ax

    push ax
    push cx
    mov cx, ED_LINE_LEN
    rep movsb
    pop cx
    pop ax
    dec ax
    jmp .shift

.clear_new:
    ; Zero out ed_line+1
    mov ax, [ed_line]
    inc ax
    imul ax, ax, ED_LINE_LEN
    add ax, ed_buf
    mov di, ax
    mov cx, ED_LINE_LEN
    xor al, al
    rep stosb
    inc word [ed_lines]

.done:
    ret

; ---- ed_redraw: redraw entire editor content area ----
ed_redraw:
    push es
    mov ax, VGA_MEM
    mov es, ax

    ; Clear content area rows 1-23
    mov di, SCREEN_W * 2
    mov cx, SCREEN_W * 22
.er_clr:
    mov word [es:di], 0x0720
    add di, 2
    loop .er_clr

    ; Render visible lines
    mov ax, [ed_top]
    mov byte [ed_tmp_row], 1

.er_row:
    movzx bx, byte [ed_tmp_row]
    cmp bx, 23
    jge .er_done
    cmp ax, [ed_lines]
    jge .er_done

    ; Set row base in VGA
    imul bx, bx, SCREEN_W * 2   ; bx = VGA row offset
    add bx, 8                    ; +4 chars gutter

    ; Get line pointer
    push ax
    imul ax, ax, ED_LINE_LEN
    add ax, ed_buf
    mov si, ax
    pop ax

    ; Print up to ED_LINE_LEN chars
    push ax
    mov cx, ED_LINE_LEN
.er_char:
    cmp cx, 0
    je .er_next
    cmp byte [si], 0
    je .er_next
    mov al, [si]
    mov byte [es:bx], al
    mov byte [es:bx+1], 0x07
    inc si
    add bx, 2
    dec cx
    jmp .er_char

.er_next:
    pop ax
    inc ax
    inc byte [ed_tmp_row]
    jmp .er_row

.er_done:
    pop es

    ; Highlight current line
    call ed_hl_curline
    ret

; ---- ed_hl_curline: highlight current line ----
ed_hl_curline:
    push es
    mov ax, VGA_MEM
    mov es, ax

    mov ax, [ed_line]
    sub ax, [ed_top]
    inc ax                  ; +1 for header row
    imul ax, ax, SCREEN_W * 2
    add ax, 8               ; gutter
    mov di, ax

    mov cx, SCREEN_W - 4
.hl:
    mov byte [es:di+1], 0x02  ; dark green attr
    add di, 2
    loop .hl
    pop es
    ret

; ---- ed_show_cur: position hardware cursor ----
ed_show_cur:
    mov ax, [ed_line]
    sub ax, [ed_top]
    inc ax
    mov dh, al
    mov ax, [ed_col]
    add ax, 4
    mov dl, al
    call setcursor
    ret

; ============================================================
; KERNEL EDITOR - load kernel binary from disk into editor
; ============================================================
kernel_editor:
    ; Clear ed_buf
    mov di, ed_buf
    mov cx, MAX_ED_LINES * ED_LINE_LEN
    xor al, al
    rep stosb

    ; Read 22 kernel sectors (LBA 1..22) into ed_buf
    mov ax, cs
    mov [kedit_dap_seg], ax
    mov ah, 0x42            ; INT 13h extended read
    mov dl, [boot_drive]
    mov si, kedit_dap
    int 0x13
    jc .ke_err

    ; Replace null bytes with '.' so editor lines don't terminate early
    mov si, ed_buf
    mov cx, 22 * 512        ; bytes actually loaded
.ke_null:
    cmp byte [si], 0
    jne .ke_notnull
    mov byte [si], '.'
.ke_notnull:
    inc si
    dec cx
    jnz .ke_null

    ; Count lines: 22*512/ED_LINE_LEN = 144 lines, +1 partial
    mov word [ed_lines], 145

    ; Open editor in kernel mode (ed_mode=1 already set by caller)
    mov word [ed_line], 0
    mov word [ed_col], 0
    mov word [ed_top], 0
    call text_editor
    ret

.ke_err:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_kern_load_err
    call print_at
    call sh_newline
    ret

; ---- ed_kern_write: write ed_buf back to kernel sectors (Ctrl-W) ----
ed_kern_write:
    pusha
    ; Warn on footer row
    mov dh, 24
    mov dl, 0
    mov cx, 80
    mov al, ' '
    mov bl, 0x4F
    call draw_hline
    mov dh, 24
    mov dl, 0
    mov bl, 0x4F
    mov si, str_kern_warn
    call print_at
    ; Wait for Y/N
    mov ah, 0x00
    int 0x16
    cmp al, 'Y'
    je .kw_do
    cmp al, 'y'
    je .kw_do
    ; Cancelled — restore footer
    mov dh, 24
    mov dl, 0
    mov cx, 80
    mov al, ' '
    mov bl, 0x70
    call draw_hline
    mov dh, 24
    mov dl, 0
    mov bl, 0x70
    mov si, [ed_footer_ptr]
    call print_at
    popa
    ret
.kw_do:
    mov ax, cs
    mov [kedit_dap_seg], ax
    mov ah, 0x43            ; INT 13h extended write
    mov al, 0
    mov dl, [boot_drive]
    mov si, kedit_dap
    int 0x13
    jc .kw_err
    mov si, str_kern_saved
    call ed_flash_footer
    popa
    ret
.kw_err:
    mov si, str_kern_save_err
    call ed_flash_footer
    popa
    ret

; ============================================================
; TOMMY'S C IDE - open editor in IDE mode (ed_mode=2)
; ============================================================
ide_open:
    ; Buffer keeps existing content (user edits their TC program)
    mov byte [ed_mode], 2
    call text_editor
    ret

; ============================================================
; GRAPHICS MODE - menu with 4 mini-apps
;   1 PAINT    2 BALL    3 PALETTE    4 CLOCK    ESC exit
; ============================================================
graphics_mode:
    ; Init mouse once
    cmp byte [ms_ready], 0
    jne .ms_ok
    call mouse_init
.ms_ok:
.gm_main:
    mov ax, 0x0013
    int 0x10
    mov byte [ms_saved], 0
    call gfx_draw_menu

.gm_wait:
    ; Poll mouse + keys until something interesting
    call mouse_poll
    call mouse_restore_bg
    call mouse_draw_cursor

    ; Check for key
    mov ah, 0x01
    int 0x16
    jz .no_key
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    je .gm_exit
    cmp al, '1'
    je .gm_paint
    cmp al, '2'
    je .gm_ball
    cmp al, '3'
    je .gm_pal
    cmp al, '4'
    je .gm_clock
    cmp al, '5'
    je .gm_snake
    cmp al, '6'
    je .gm_stars
    jmp .no_key
.no_key:
    ; Check mouse click (left button transition 0->1)
    mov al, [ms_btn]
    and al, 1
    mov bl, [ms_lbtn_prev]
    mov [ms_lbtn_prev], al
    cmp al, 0
    je .gm_wait
    cmp bl, 0
    jne .gm_wait

    ; Click! Hit-test menu rows. Items at y=64..151 (8 rows each, gap of 4)
    mov ax, [ms_y]
    cmp ax, 64
    jl .gm_wait
    sub ax, 64
    mov bl, 12
    xor dx, dx
    div bl                       ; AL = (y-64)/12  -> 0..5
    cmp al, 0
    je .gm_paint
    cmp al, 1
    je .gm_ball
    cmp al, 2
    je .gm_pal
    cmp al, 3
    je .gm_clock
    cmp al, 4
    je .gm_snake
    cmp al, 5
    je .gm_stars
    jmp .gm_wait

.gm_paint:
    call gfx_app_paint
    jmp .gm_main
.gm_ball:
    call gfx_app_ball
    jmp .gm_main
.gm_pal:
    call gfx_app_palette
    jmp .gm_main
.gm_clock:
    call gfx_app_clock
    jmp .gm_main
.gm_snake:
    call gfx_app_snake
    jmp .gm_main
.gm_stars:
    call gfx_app_starfield
    jmp .gm_main

.gm_exit:
    mov ax, 0x0003
    int 0x10
    ret

; --- gfx_draw_menu: paint the static menu chrome ---
gfx_draw_menu:
    ; Gradient background
    call gfx_draw_bg

    ; Title bar (rows 0..15 dark blue)
    push es
    mov ax, 0xA000
    mov es, ax
    xor di, di
    mov cx, 16 * 320 / 2
    mov ax, 0x0101
    rep stosw
    ; Bottom bar (rows 184..199)
    mov di, 184 * 320
    mov cx, 16 * 320 / 2
    mov ax, 0x0808
    rep stosw
    pop es

    mov bp, gfx_title
    mov cx, 23
    mov dh, 0
    mov dl, 8
    mov bl, 0x0F
    call gfx_print

    mov bp, gfx_subtitle
    mov cx, 24
    mov dh, 3
    mov dl, 8
    mov bl, 0x0E
    call gfx_print

    ; Menu items
    mov bp, gfx_menu1
    mov cx, 28
    mov dh, 8
    mov dl, 5
    mov bl, 0x0A
    call gfx_print

    mov bp, gfx_menu2
    mov cx, 27
    mov dh, 10
    mov dl, 5
    mov bl, 0x0E
    call gfx_print

    mov bp, gfx_menu3
    mov cx, 24
    mov dh, 12
    mov dl, 5
    mov bl, 0x0B
    call gfx_print

    mov bp, gfx_menu4
    mov cx, 28
    mov dh, 14
    mov dl, 5
    mov bl, 0x0D
    call gfx_print

    mov bp, gfx_menu5
    mov cx, 27
    mov dh, 16
    mov dl, 5
    mov bl, 0x0C
    call gfx_print

    mov bp, gfx_menu6
    mov cx, 28
    mov dh, 18
    mov dl, 5
    mov bl, 0x09
    call gfx_print

    mov bp, gfx_esc
    mov cx, 27
    mov dh, 24
    mov dl, 6
    mov bl, 0x0F
    call gfx_print
    ret

; ---- gfx_fill: AL = color, fills 320x200 in mode 13h ----
gfx_fill:
    push es
    push ax
    push cx
    push di
    mov ah, al
    push ax
    mov ax, 0xA000
    mov es, ax
    pop ax
    xor di, di
    mov cx, 320*200/2
    rep stosw
    pop di
    pop cx
    pop ax
    pop es
    ret

; ---- gfx_print: BP=str, CX=len, DH=row, DL=col, BL=color ----
gfx_print:
    push ax
    push bx
    push bp
    mov ah, 0x13
    mov al, 0x01
    mov bh, 0
    int 0x10
    pop bp
    pop bx
    pop ax
    ret

; ---- gfx_putpixel: CX=x, DX=y, AL=color. Preserves all. ----
gfx_putpixel:
    push es
    push di
    push bx
    push ax
    mov bx, 0xA000
    mov es, bx
    mov bx, dx
    imul bx, bx, 320
    add bx, cx
    mov di, bx
    pop ax
    mov [es:di], al
    pop bx
    pop di
    pop es
    ret

; ---- gfx_fillrect5: CX=x, DX=y, AL=color. 5x5 block. ----
gfx_fillrect5:
    push si
    push di
    push cx
    push dx
    push ax
    mov si, 5
.fr_row:
    push cx
    mov di, 5
.fr_col:
    call gfx_putpixel
    inc cx
    dec di
    jnz .fr_col
    pop cx
    inc dx
    dec si
    jnz .fr_row
    pop ax
    pop dx
    pop cx
    pop di
    pop si
    ret

; ============================================================
; APP: PAINT - move cursor with arrows, leaves a colored trail
; ============================================================
; Mouse paint:
;   move mouse to position
;   LEFT click/drag = paint with current color
;   RIGHT click     = cycle color
;   c               = clear canvas
;   ESC             = back to menu
;   arrows          = also move (fallback if no mouse)
gfx_app_paint:
    cmp byte [ms_ready], 0
    jne .ms_ok
    call mouse_init
.ms_ok:
    xor al, al
    call gfx_fill
    mov bp, gfx_paint_hint
    mov cx, 30
    mov dh, 0
    mov dl, 5
    mov bl, 0x0F
    call gfx_print
    mov byte [gfx_col], 0x0A
    mov byte [ms_saved], 0
.pl:
    call mouse_poll
    call mouse_restore_bg

    ; If left button held, stamp at cursor (under the cursor sprite area)
    mov al, [ms_btn]
    test al, 0x01
    jz .no_paint
    mov cx, [ms_x]
    mov dx, [ms_y]
    cmp dx, 12
    jl .no_paint
    cmp dx, 195
    jg .no_paint
    mov al, [gfx_col]
    call gfx_fillrect5
.no_paint:
    ; Right button (transition) = cycle color
    mov al, [ms_btn]
    and al, 0x02
    mov bl, [ms_rbtn_prev]
    mov [ms_rbtn_prev], al
    cmp al, 0
    je .skip_cycle
    cmp bl, 0
    jne .skip_cycle
    call .do_cycle
.skip_cycle:

    call mouse_draw_cursor

    ; Non-blocking key check
    mov ah, 0x01
    int 0x16
    jz .pl
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    je .pp_done
    cmp al, 'c'
    je .pp_clear
    cmp al, 'C'
    je .pp_clear
    cmp al, ' '
    je .pp_kcolor
    jmp .pl

.do_cycle:
    inc byte [gfx_col]
    cmp byte [gfx_col], 0
    jne .dc_ret
    mov byte [gfx_col], 1
.dc_ret:
    ret

.pp_kcolor:
    call .do_cycle
    jmp .pl

.pp_clear:
    xor al, al
    call gfx_fill
    mov bp, gfx_paint_hint
    mov cx, 30
    mov dh, 0
    mov dl, 5
    mov bl, 0x0F
    call gfx_print
    mov byte [ms_saved], 0
    jmp .pl
.pp_done:
    ret

; ============================================================
; APP: BOUNCING BALL
; ============================================================
gfx_app_ball:
    xor al, al
    call gfx_fill
    mov bp, gfx_ball_hint
    mov cx, 16
    mov dh, 0
    mov dl, 12
    mov bl, 0x0F
    call gfx_print
    mov word [gfx_x], 50
    mov word [gfx_y], 60
    mov word [gfx_dx], 2
    mov word [gfx_dy], 1
.bl:
    mov ah, 0x01
    int 0x16
    jz .b_skip_key
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    je .b_done
.b_skip_key:
    ; Erase old ball
    mov cx, [gfx_x]
    mov dx, [gfx_y]
    xor al, al
    call gfx_fillrect5

    ; Update x
    mov ax, [gfx_x]
    add ax, [gfx_dx]
    cmp ax, 4
    jg .b_no_lx
    neg word [gfx_dx]
    mov ax, 4
.b_no_lx:
    cmp ax, 310
    jl .b_no_rx
    neg word [gfx_dx]
    mov ax, 310
.b_no_rx:
    mov [gfx_x], ax

    ; Update y
    mov ax, [gfx_y]
    add ax, [gfx_dy]
    cmp ax, 12
    jg .b_no_uy
    neg word [gfx_dy]
    mov ax, 12
.b_no_uy:
    cmp ax, 192
    jl .b_no_dy
    neg word [gfx_dy]
    mov ax, 192
.b_no_dy:
    mov [gfx_y], ax

    ; Draw new ball
    mov cx, [gfx_x]
    mov dx, [gfx_y]
    mov al, 0x0E
    call gfx_fillrect5

    ; Delay
    mov cx, 0x0003
.b_outer:
    push cx
    mov cx, 0xFFFF
.b_inner:
    dec cx
    jnz .b_inner
    pop cx
    loop .b_outer
    jmp .bl
.b_done:
    ret

; ============================================================
; APP: PALETTE - all 256 VGA colors in a 16x16 grid
; ============================================================
gfx_app_palette:
    xor al, al
    call gfx_fill
    mov bp, gfx_pal_hint
    mov cx, 16
    mov dh, 0
    mov dl, 12
    mov bl, 0x0F
    call gfx_print

    push es
    mov ax, 0xA000
    mov es, ax
    mov di, 20 * 320          ; y=20

    xor bx, bx                ; cell row 0..15
.prow:
    cmp bx, 16
    jge .pdone
    mov si, 10                ; 10 pixel rows per cell row
.pyloop:
    xor dx, dx                ; cell col 0..15
.pcol:
    cmp dx, 16
    jge .pcol_done
    mov ax, bx
    shl ax, 4
    add ax, dx                ; AL = color = bx*16 + dx
    mov cx, 20
    rep stosb
    inc dx
    jmp .pcol
.pcol_done:
    dec si
    jnz .pyloop
    inc bx
    jmp .prow
.pdone:
    pop es

.pwait:
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    jne .pwait
    ret

; ============================================================
; APP: CLOCK - live BIOS time, redraw each second
; ============================================================
gfx_app_clock:
    xor al, al
    call gfx_fill
    mov bp, gfx_clk_hint
    mov cx, 16
    mov dh, 22
    mov dl, 12
    mov bl, 0x0F
    call gfx_print
.ck_loop:
    ; Clear the time region (rows 80..120)
    push es
    mov ax, 0xA000
    mov es, ax
    mov di, 80 * 320
    mov cx, 40 * 320 / 2
    xor ax, ax
    rep stosw
    pop es

    call gfx_make_time_str

    mov bp, clk_buf
    mov cx, 8
    mov dh, 12
    mov dl, 16
    mov bl, 0x0F
    call gfx_print

    ; Wait roughly 1 second, polling ESC
    mov bx, 16
.ck_wait:
    mov ah, 0x01
    int 0x16
    jz .ck_no_key
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    je .ck_done
.ck_no_key:
    mov cx, 0x0001
.cd_outer:
    push cx
    mov cx, 0xFFFF
.cd_inner:
    dec cx
    jnz .cd_inner
    pop cx
    loop .cd_outer
    dec bx
    jnz .ck_wait
    jmp .ck_loop
.ck_done:
    ret

; ---- gfx_make_time_str: build HH:MM:SS into clk_buf ----
gfx_make_time_str:
    push ax
    push cx
    push dx
    mov ah, 0x02
    int 0x1A
    ; HH (CH BCD)
    mov al, ch
    mov ah, al
    shr ah, 4
    and ah, 0x0F
    add ah, '0'
    mov [clk_buf+0], ah
    and al, 0x0F
    add al, '0'
    mov [clk_buf+1], al
    mov byte [clk_buf+2], ':'
    ; MM (CL BCD)
    mov al, cl
    mov ah, al
    shr ah, 4
    and ah, 0x0F
    add ah, '0'
    mov [clk_buf+3], ah
    and al, 0x0F
    add al, '0'
    mov [clk_buf+4], al
    mov byte [clk_buf+5], ':'
    ; SS (DH BCD)
    mov al, dh
    mov ah, al
    shr ah, 4
    and ah, 0x0F
    add ah, '0'
    mov [clk_buf+6], ah
    and al, 0x0F
    add al, '0'
    mov [clk_buf+7], al
    pop dx
    pop cx
    pop ax
    ret

; ============================================================
; TITLE BAR
; ============================================================
draw_titlebar:
; ============================================================
; v2: macOS-style menu bar on row 0
;   Layout:  [space] Tommy OS [sep] File  Edit  View  Apps  Help ... HH:MM:SS
; ============================================================
    push es
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; --- Fill row 0 with menu-bar colour ---
    mov ax, VGA_MEM
    mov es, ax
    xor di, di
    mov cx, SCREEN_W
    mov ax, (COL_MENUBAR << 8) | 0x20
.mb_fill:
    stosw
    loop .mb_fill

    ; --- Brand mark ---
    mov dh, 0
    mov dl, 1
    mov bl, COL_MENUBAR
    mov si, str_mb_brand
    call print_at

    ; --- Separator ---
    mov dh, 0
    mov dl, 10
    mov bl, COL_MENUBAR
    mov al, 0xB3            ; │ vertical bar
    call print_char_vga     ; helper: write one char at DH/DL with attr BL

    ; --- Menu items ---
    mov dh, 0
    mov dl, 12
    mov bl, COL_MENUBAR
    mov si, str_mb_file
    call print_at

    mov dh, 0
    mov dl, 18
    mov bl, COL_MENUBAR
    mov si, str_mb_edit
    call print_at

    mov dh, 0
    mov dl, 24
    mov bl, COL_MENUBAR
    mov si, str_mb_view
    call print_at

    mov dh, 0
    mov dl, 30
    mov bl, COL_MENUBAR
    mov si, str_mb_apps
    call print_at

    mov dh, 0
    mov dl, 36
    mov bl, COL_MENUBAR
    mov si, str_mb_help
    call print_at

    ; --- Right separator ---
    mov dh, 0
    mov dl, 42
    mov bl, COL_MENUBAR
    mov al, 0xB3
    call print_char_vga

    ; --- Clock (right-aligned at col 69) ---
    call draw_menubar_clock

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop es
    ret

; --- draw_menubar_clock: read BIOS RTC and write HH:MM:SS at col 69 ---
draw_menubar_clock:
    push ax
    push bx
    push cx
    push dx
    push si

    mov ah, 0x02
    int 0x1A
    jc .no_rtc

    ; CH=hours, CL=minutes, DH=seconds (all BCD)
    push cx
    push dx

    ; hours
    mov al, ch
    call mbclk_bcd          ; AX = two ASCII digits
    mov [clk_buf2+0], ah
    mov [clk_buf2+1], al
    mov byte [clk_buf2+2], ':'

    pop dx
    push dx
    ; minutes
    mov al, cl
    call mbclk_bcd
    mov [clk_buf2+3], ah
    mov [clk_buf2+4], al
    mov byte [clk_buf2+5], ':'

    ; seconds
    mov al, dh
    call mbclk_bcd
    mov [clk_buf2+6], ah
    mov [clk_buf2+7], al
    mov byte [clk_buf2+8], 0

    pop dx
    pop cx

    mov dh, 0
    mov dl, 69
    mov bl, COL_MENUBAR
    mov si, clk_buf2
    call print_at
    jmp .clk_done

.no_rtc:
    mov dh, 0
    mov dl, 70
    mov bl, COL_MENUBAR
    mov si, str_mb_clock_na
    call print_at

.clk_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; mbclk_bcd: AL = BCD byte -> AH = tens digit ASCII, AL = units digit ASCII
mbclk_bcd:
    push bx
    mov bh, al
    shr bh, 4
    and bh, 0x0F
    add bh, '0'         ; tens
    and al, 0x0F
    add al, '0'         ; units
    mov ah, bh
    pop bx
    ret

; --- print_char_vga: write char AL at DH=row DL=col with attr BL ---
print_char_vga:
    push es
    push ax
    push bx
    push di
    push dx
    push cx

    mov cx, VGA_MEM
    mov es, cx
    movzx di, dh
    imul di, di, SCREEN_W * 2
    movzx cx, dl
    shl cx, 1
    add di, cx
    mov [es:di], al
    mov [es:di+1], bl

    pop cx
    pop dx
    pop di
    pop bx
    pop ax
    pop es
    ret

; ============================================================
; DOCK  (v2: macOS-style dock on row 23)
; ============================================================
draw_statusbar:
; Fill dock row with dock colour
    push es
    push ax
    push cx
    push di
    mov ax, VGA_MEM
    mov es, ax
    mov di, DOCK_ROW * SCREEN_W * 2
    mov cx, SCREEN_W
    mov ax, (COL_DOCK << 8) | 0x20
.dk_fill:
    stosw
    loop .dk_fill
    pop di
    pop cx
    pop ax
    pop es

    ; Left bracket
    mov dh, DOCK_ROW
    mov dl, 0
    mov bl, COL_DOCK
    mov si, str_dock_l
    call print_at

    ; Dock items
    mov dh, DOCK_ROW
    mov dl, 3
    mov bl, COL_DOCK
    mov si, str_dock_term
    call print_at

    mov dh, DOCK_ROW
    mov dl, 18
    mov bl, COL_DOCK
    mov si, str_dock_edit
    call print_at

    mov dh, DOCK_ROW
    mov dl, 33
    mov bl, COL_DOCK
    mov si, str_dock_gfx
    call print_at

    mov dh, DOCK_ROW
    mov dl, 48
    mov bl, COL_DOCK
    mov si, str_dock_games
    call print_at

    mov dh, DOCK_ROW
    mov dl, 63
    mov bl, COL_DOCK
    mov si, str_dock_about
    call print_at

    ; Right bracket
    mov dh, DOCK_ROW
    mov dl, 78
    mov bl, COL_DOCK
    mov si, str_dock_r
    call print_at

    ; Highlight active dock item based on desktop state
    call dock_highlight
    ret

; --- dock_highlight: colour the current [desk_state]'s dock item ---
dock_highlight:
    push ax
    push bx
    push dx
    push si

    movzx ax, byte [desk_state]
    cmp al, DS_TERMINAL
    je .term
    cmp al, DS_EDITOR
    je .edit
    cmp al, DS_ABOUT
    je .about
    jmp .done

.term:
    mov dh, DOCK_ROW
    mov dl, 3
    mov bl, COL_DOCK_SEL
    mov si, str_dock_term
    call print_at
    jmp .done
.edit:
    mov dh, DOCK_ROW
    mov dl, 18
    mov bl, COL_DOCK_SEL
    mov si, str_dock_edit
    call print_at
    jmp .done
.about:
    mov dh, DOCK_ROW
    mov dl, 63
    mov bl, COL_DOCK_SEL
    mov si, str_dock_about
    call print_at
.done:
    pop si
    pop dx
    pop bx
    pop ax
    ret

; ============================================================
; CLEAR SCREEN
; ============================================================
clrscr:
    push es
    mov ax, VGA_MEM
    mov es, ax
    xor di, di
    mov cx, SCREEN_W * SCREEN_H
    mov ax, 0x0720
    rep stosw
    pop es
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10
    ret

; ============================================================
; PRINT_AT: SI=string, DH=row, DL=col, BL=colour attr
; ============================================================
print_at:
    push es
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, VGA_MEM
    mov es, ax

.pa_loop:
    lodsb
    or al, al
    jz .pa_done
    cmp al, 0x0A
    je .pa_nl

    ; Compute VGA offset into DI (preserve AL = character via stack)
    push ax
    movzx cx, dh
    imul cx, cx, SCREEN_W
    movzx ax, dl
    add cx, ax
    shl cx, 1
    mov di, cx
    pop ax

    mov [es:di], al
    mov [es:di+1], bl
    inc dl
    cmp dl, SCREEN_W
    jl .pa_loop
    mov dl, 0
    inc dh
    jmp .pa_loop

.pa_nl:
    mov dl, 0
    inc dh
    jmp .pa_loop

.pa_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop es
    ret

; ============================================================
; DRAW_HLINE: DH=row, DL=col, CX=count, AL=char, BL=attr
; ============================================================
draw_hline:
    push es
    push ax
    push bx
    push cx
    push di

    mov bh, al
    mov ax, VGA_MEM
    mov es, ax

    movzx ax, dh
    imul ax, ax, SCREEN_W
    movzx di, dl
    add ax, di
    shl ax, 1
    mov di, ax

.dh_loop:
    mov byte [es:di], bh
    mov byte [es:di+1], bl
    add di, 2
    loop .dh_loop

    pop di
    pop cx
    pop bx
    pop ax
    pop es
    ret

; ============================================================
; SETCURSOR: DH=row, DL=col
; ============================================================
setcursor:
    push ax
    push bx
    mov ah, 0x02
    xor bh, bh
    int 0x10
    pop bx
    pop ax
    ret

; ============================================================
; READLINE_ECHO: DI=buf, CX=maxlen
; ============================================================
readline_echo:
    push ax
    push bx
    push cx
    push di
    xor bx, bx
.re_loop:
    mov ah, 0x00
    int 0x16
    ; Check scroll-mode keys first (work regardless of hist_enabled)
    cmp ah, 0x49         ; PageUp  = scroll back
    je .re_pgup
    cmp ah, 0x51         ; PageDown = scroll forward / exit
    je .re_pgdn
    ; If currently in scroll view, any other key exits it
    cmp byte [scrl_mode], 0
    je .re_no_scrl_exit
    call scrl_exit_view
.re_no_scrl_exit:
    cmp al, 0x0D
    je .re_done
    cmp al, 0x08
    je .re_bksp
    test al, al
    jz .re_ext           ; extended key (arrows, F-keys, ...)
    cmp al, 0x09         ; Tab = try completion
    je .re_tab
    cmp bx, cx
    jge .re_loop
    mov [di+bx], al
    inc bx
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    jmp .re_loop
.re_pgup:
    ; Scroll back in terminal history
    cmp word [scrl_n], 0
    je .re_loop             ; no history yet
    cmp byte [scrl_mode], 0
    jne .re_pgup_more       ; already in scroll mode — go further back
    call scrl_enter_view
    jmp .re_loop
.re_pgup_more:
    ; Check if we can scroll further back
    mov ax, [scrl_off]
    inc ax
    ; scrl_off max = scrl_n - 1 (can't go back more than what we have)
    mov bx, [scrl_n]
    dec bx
    cmp ax, bx
    jg .re_loop             ; already at oldest line
    mov [scrl_off], ax
    call scrl_show_view
    jmp .re_loop
.re_pgdn:
    cmp byte [scrl_mode], 0
    je .re_loop             ; not in scroll mode
    cmp word [scrl_off], 0
    je .re_pgdn_exit        ; already at newest — exit scroll mode
    dec word [scrl_off]
    call scrl_show_view
    jmp .re_loop
.re_pgdn_exit:
    call scrl_exit_view
    jmp .re_loop
.re_ext:
    cmp byte [hist_enabled], 0
    je .re_loop
    cmp ah, 0x48         ; UP
    je .re_up
    cmp ah, 0x50         ; DOWN
    je .re_down
    jmp .re_loop
.re_up:
    mov al, [hist_view]
    cmp al, [hist_count]
    jae .re_loop
    inc al
    mov [hist_view], al
    call hist_apply
    jmp .re_loop
.re_down:
    cmp byte [hist_view], 0
    je .re_loop
    dec byte [hist_view]
    call hist_apply
    jmp .re_loop
.re_tab:
    ; Tab completion: scan tab_list for prefix match
    cmp bx, 0
    je .re_loop
    cmp byte [hist_enabled], 0
    je .re_loop
    ; scan tab_list for entries matching [di..di+bx-1] as prefix
    mov word [tab_count], 0
    mov word [tab_match_ptr], 0
    mov si, tab_list
.rtl:
    cmp byte [si], 0
    je .rtd
    ; compare [si..] with [di..di+bx-1]
    push si
    push di
    push bx
.rtc:
    cmp bx, 0
    je .rtm
    mov al, [si]
    or al, al
    je .rtn
    cmp al, [di]
    jne .rtn
    inc si
    inc di
    dec bx
    jmp .rtc
.rtm:
    pop bx
    pop di
    pop si
    inc word [tab_count]
    mov [tab_match_ptr], si
.rtskip:
    mov al, [si]
    or al, al
    je .rtne
    inc si
    jmp .rtskip
.rtne:
    inc si
    jmp .rtl
.rtn:
    pop bx
    pop di
    pop si
.rtskip2:
    mov al, [si]
    or al, al
    je .rtne2
    inc si
    jmp .rtskip2
.rtne2:
    inc si
    jmp .rtl
.rtd:
    cmp word [tab_count], 1
    jne .re_loop
    ; exactly one match: print suffix and store it
    mov si, [tab_match_ptr]
    add si, bx                 ; skip past already-typed prefix
.rtfill:
    mov al, [si]
    or al, al
    je .rtspace
    cmp bx, cx
    jge .rtspace
    mov [di+bx], al
    inc bx
    push ax
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    pop ax
    inc si
    jmp .rtfill
.rtspace:
    cmp bx, cx
    jge .re_loop
    mov byte [di+bx], ' '
    inc bx
    push ax
    mov ah, 0x0E
    mov al, ' '
    xor bh, bh
    int 0x10
    pop ax
    jmp .re_loop

.re_bksp:
    cmp bx, 0
    je .re_loop
    dec bx
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .re_loop
.re_done:
    pop di
    mov byte [di+bx], 0
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; TERMINAL SCROLLBACK - scrl_enter_view / scrl_exit_view / scrl_show_view
; ============================================================

; scrl_enter_view: save rows 5-22 to scrl_save, show scrollback, enter scroll mode
scrl_enter_view:
    push ds
    push es
    push si
    push di
    push cx
    ; Copy VGA rows 5..22 (18 rows × 160 bytes) into scrl_save in CS
    ; DS=VGA (source), ES=CS (dest)
    push cs
    pop es                          ; ES = kernel segment
    mov ax, VGA_MEM
    mov ds, ax                      ; DS = VGA
    mov si, 5 * SCREEN_W * 2
    mov di, scrl_save
    mov cx, 18 * SCREEN_W
    rep movsw
    ; restore DS
    push cs
    pop ds
    pop cx
    pop di
    pop si
    pop es
    pop ds
    mov byte [scrl_mode], 1
    mov word [scrl_off], 0
    call scrl_show_view
    ret

; scrl_exit_view: restore rows 5-22 from scrl_save, exit scroll mode
scrl_exit_view:
    cmp byte [scrl_mode], 0
    je .done
    push ds
    push es
    push si
    push di
    push cx
    ; Copy scrl_save back into VGA rows 5..22
    ; DS=CS (scrl_save source), ES=VGA (dest) — normal movsw direction
    mov ax, VGA_MEM
    mov es, ax
    mov si, scrl_save
    mov di, 5 * SCREEN_W * 2
    mov cx, 18 * SCREEN_W
    rep movsw
    pop cx
    pop di
    pop si
    pop es
    pop ds
    mov byte [scrl_mode], 0
    mov word [scrl_off], 0
.done:
    ret

; scrl_show_view: render scrollback ring buffer into VGA rows 5..21,
;                 show hint on row 22.  Called with DS=CS, must set ES=VGA.
scrl_show_view:
    push ds
    push es
    push si
    push di
    push ax
    push bx
    push cx

    mov ax, VGA_MEM
    mov es, ax                      ; ES = VGA (destination)
    ; DS is already CS (scrl_buf source)

    ; Clear rows 5..21 with scroll-mode colour (bright white on blue)
    mov di, 5 * SCREEN_W * 2
    mov cx, 17 * SCREEN_W
    mov ax, 0x1F20
    rep stosw

    ; Print scroll hint on row 22
    mov dh, 22
    mov dl, 0
    mov bl, 0x70
    mov si, str_scrl_hint
    call print_at

    ; Display up to 17 lines from the scrollback ring.
    ; Row 5+i shows the line (scrl_off + 16 - i) back from newest.
    xor cx, cx                      ; cx = row index i (0..16)
.sv_loop:
    cmp cx, 17
    jge .sv_done

    ; k = scrl_off + 16 - cx  (lines back from newest)
    mov ax, [scrl_off]
    mov bx, 16
    sub bx, cx
    add ax, bx                      ; ax = k

    ; Skip if we don't have this line yet
    cmp ax, [scrl_n]
    jge .sv_blank

    ; ring_idx = (scrl_head - 1 - k + SCRL_MAX) % SCRL_MAX
    mov bx, [scrl_head]
    dec bx
    sub bx, ax                      ; bx = scrl_head - 1 - k
    test bx, 0x8000                 ; negative?
    jz .sv_pos
    add bx, SCRL_MAX                ; add once (enough for SCRL_MAX=10)
.sv_pos:
    cmp bx, SCRL_MAX
    jl .sv_got_idx
    sub bx, SCRL_MAX
.sv_got_idx:
    ; SI = scrl_buf + ring_idx * SCREEN_W * 2  (in DS = CS)
    imul bx, bx, SCREEN_W * 2
    add bx, scrl_buf
    mov si, bx

    ; DI = VGA row (5 + cx)
    mov di, cx
    add di, 5
    imul di, di, SCREEN_W * 2

    push cx
    mov cx, SCREEN_W
    rep movsw                       ; DS:SI (scrl_buf) -> ES:DI (VGA)
    pop cx
    jmp .sv_next

.sv_blank:
    ; Dim row — no data for this position
    mov di, cx
    add di, 5
    imul di, di, SCREEN_W * 2
    push cx
    mov cx, SCREEN_W
    mov ax, 0x0820
    rep stosw
    pop cx

.sv_next:
    inc cx
    jmp .sv_loop

.sv_done:
    pop cx
    pop bx
    pop ax
    pop di
    pop si
    pop es
    pop ds
    ret

; ============================================================
; SHELL HISTORY
;   hist_apply: replace current input with hist_buf entry at
;     view position hist_view (1 = newest, 0 = empty/current).
;     On entry: DI = buf base, BX = current length.
;     On exit:  buffer/display reflect the new content, BX updated.
;   hist_push: copy DI's null-terminated string into the next
;     ring slot. Skips empty strings.
; ============================================================
MAX_HIST equ 8

hist_apply:
    push ax
    push cx
    push si
.hap_erase:
    cmp bx, 0
    je .hap_eraseD
    mov ah, 0x0E
    mov al, 0x08
    xor bh, bh
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    dec bx
    jmp .hap_erase
.hap_eraseD:
    push di
    push cx
    mov cx, MAX_CMD
    xor al, al
    rep stosb
    pop cx
    pop di

    cmp byte [hist_view], 0
    je .hap_done

    movzx ax, byte [hist_head]
    movzx cx, byte [hist_view]
    sub ax, cx
    add ax, MAX_HIST
    and ax, MAX_HIST - 1
    imul ax, ax, MAX_CMD
    add ax, hist_buf
    mov si, ax

.hap_copy:
    mov al, [si]
    or al, al
    jz .hap_done
    cmp bx, MAX_CMD - 1
    jge .hap_done
    mov [di+bx], al
    inc bx
    push si
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    pop si
    inc si
    jmp .hap_copy
.hap_done:
    pop si
    pop cx
    pop ax
    ret

hist_push:
    push ax
    push bx
    push cx
    push si
    push di
    cmp byte [di], 0
    je .hp_done
    movzx ax, byte [hist_head]
    imul ax, ax, MAX_CMD
    add ax, hist_buf
    mov bx, ax
    mov si, di
    mov di, bx
    mov cx, MAX_CMD
.hp_cp:
    mov al, [si]
    mov [di], al
    or al, al
    jz .hp_pad
    inc si
    inc di
    dec cx
    jnz .hp_cp
    jmp .hp_advance
.hp_pad:
    inc di
    dec cx
.hp_pz:
    cmp cx, 0
    je .hp_advance
    mov byte [di], 0
    inc di
    dec cx
    jmp .hp_pz
.hp_advance:
    movzx ax, byte [hist_head]
    inc ax
    and al, MAX_HIST - 1
    mov [hist_head], al
    movzx ax, byte [hist_count]
    cmp ax, MAX_HIST
    jge .hp_done
    inc ax
    mov [hist_count], al
.hp_done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; READLINE_NOECHO: DI=buf, CX=maxlen
; ============================================================
readline_noecho:
    push ax
    push bx
    push cx
    push di
    xor bx, bx
.rn_loop:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    je .rn_done
    cmp al, 0x08
    je .rn_bksp
    cmp bx, cx
    jge .rn_loop
    mov [di+bx], al
    inc bx
    jmp .rn_loop
.rn_bksp:
    cmp bx, 0
    je .rn_loop
    dec bx
    jmp .rn_loop
.rn_done:
    pop di
    mov byte [di+bx], 0
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; STRCMP: SI=a, DI=b — AL=1 if equal
; ============================================================
strcmp:
    push si
    push di
.sc_l:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .sc_ne
    or al, al
    jz .sc_eq
    inc si
    inc di
    jmp .sc_l
.sc_eq:
    mov al, 1
    jmp .sc_ret
.sc_ne:
    xor al, al
.sc_ret:
    pop di
    pop si
    ret

; ============================================================
; CMD_MATCH: compare cmd_buf(SI) prefix with DI, sets ZF
; ============================================================
cmd_match:
    push si
    push di
    push ax
.cm_loop:
    mov al, [di]
    or al, al
    jz .cm_end
    mov ah, [si]
    cmp al, ah
    jne .cm_no
    inc si
    inc di
    jmp .cm_loop
.cm_end:
    ; DI string ended — SI must be space or end
    mov al, [si]
    or al, al
    jz .cm_yes
    cmp al, ' '
    je .cm_yes
    cmp al, 0x0D
    je .cm_yes
.cm_no:
    pop ax
    pop di
    pop si
    or ax, 1
    cmp ax, 0           ; clear ZF
    ret
.cm_yes:
    pop ax
    pop di
    pop si
    xor ax, ax
    cmp ax, 0           ; set ZF
    ret

; ============================================================
; SKIP_SPACES: advance SI past spaces
; ============================================================
skip_spaces:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp skip_spaces
.done:
    ret

; ============================================================
; SH_PRINT_MULTILINE: print a multi-line 0-terminated string,
; one shell line at a time (handles 0x0A as line breaks).
; SI = string, BL = color attr
; ============================================================
sh_print_multiline:
    cmp byte [si], 0
    je .pm_done
    mov dh, [sh_row]
    mov dl, 2
    call print_line_si       ; advances SI past 0x0A or to 0
    call sh_newline
    jmp sh_print_multiline
.pm_done:
    ret

; ============================================================
; PUTC_AT_CURSOR: print AL via BIOS teletype at current cursor
; ============================================================
putc_at_cursor:
    push ax
    push bx
    mov ah, 0x0E
    xor bh, bh
    mov bl, 0x07
    int 0x10
    pop bx
    pop ax
    ret

; ============================================================
; PRINT_BCD_AT_CURSOR: print AL as two BCD digits at cursor
; ============================================================
print_bcd_at_cursor:
    push ax
    mov ah, al
    shr ah, 4
    and ah, 0x0F
    add ah, '0'
    push ax
    mov al, ah
    call putc_at_cursor
    pop ax
    pop ax
    push ax
    and al, 0x0F
    add al, '0'
    call putc_at_cursor
    pop ax
    ret

; ============================================================
; PRINT_DEC_AT_CURSOR: print AX as decimal (unsigned)
; ============================================================
print_dec_at_cursor:
    push ax
    push bx
    push cx
    push dx
    mov cx, 0            ; digit count
    mov bx, 10
    cmp ax, 0
    jne .pd_loop
    mov al, '0'
    call putc_at_cursor
    jmp .pd_done2
.pd_loop:
    cmp ax, 0
    je .pd_emit
    xor dx, dx
    div bx               ; AX/10 → AX, remainder DX
    push dx
    inc cx
    jmp .pd_loop
.pd_emit:
    cmp cx, 0
    je .pd_done2
    pop ax
    add al, '0'
    call putc_at_cursor
    dec cx
    jmp .pd_emit
.pd_done2:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; WAIT_ENTER
; ============================================================
wait_enter:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    jne wait_enter
    ret

; ============================================================
; CMD_SYSINFO - report memory, equipment, video mode
; ============================================================
cmd_sysinfo:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_si_hdr
    call print_at
    call sh_newline

    ; --- Conventional RAM (int 12h, returns AX = KB) ---
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_si_ram
    call print_at
    mov dh, [sh_row]
    mov dl, 22
    call setcursor
    int 0x12
    call print_dec_at_cursor
    mov si, str_si_kb
    call print_str_at_cursor
    call sh_newline

    ; --- Equipment list (int 11h) ---
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_si_eq
    call print_at
    mov dh, [sh_row]
    mov dl, 22
    call setcursor
    int 0x11
    call print_hex_word_at_cursor
    call sh_newline

    ; --- Boot drive ---
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_si_drv
    call print_at
    mov dh, [sh_row]
    mov dl, 22
    call setcursor
    mov al, [boot_drive]
    call print_hex_byte_at_cursor
    call sh_newline

    ; --- Video mode (int 10h, AH=0Fh) ---
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_si_vid
    call print_at
    mov dh, [sh_row]
    mov dl, 22
    call setcursor
    mov ah, 0x0F
    int 0x10
    call print_hex_byte_at_cursor
    call sh_newline
    call sh_newline
    ret

; ============================================================
; CMD_CPUID - show vendor string + family/model
; ============================================================
cmd_cpuid:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_cp_hdr
    call print_at
    call sh_newline

    ; CPUID leaf 0 -> vendor in EBX,EDX,ECX
    mov eax, 0
    cpuid
    mov [cpu_vendor+0],  ebx
    mov [cpu_vendor+4],  edx
    mov [cpu_vendor+8],  ecx
    mov byte [cpu_vendor+12], 0

    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_GREEN
    mov si, str_cp_vendor
    call print_at
    mov dh, [sh_row]
    mov dl, 12
    mov bl, COL_BRIGHT
    mov si, cpu_vendor
    call print_at
    call sh_newline

    ; CPUID leaf 1 -> family/model/stepping in EAX
    mov eax, 1
    cpuid
    mov [cpu_sig], eax

    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_GREEN
    mov si, str_cp_sig
    call print_at
    mov dh, [sh_row]
    mov dl, 12
    call setcursor
    mov ax, [cpu_sig]
    call print_hex_word_at_cursor
    call sh_newline
    call sh_newline
    ret

; ============================================================
; CMD_CALC - parse "calc N op N" from cmd_buf
; ============================================================
cmd_calc:
    mov si, cmd_buf
    call skip_spaces
    add si, 4                       ; skip "calc"
    call skip_spaces

    call parse_dec
    mov [calc_a], ax
    call skip_spaces

    mov al, [si]
    mov [calc_op], al
    inc si
    call skip_spaces

    call parse_dec
    mov [calc_b], ax

    mov ax, [calc_a]
    mov bx, [calc_b]
    mov cl, [calc_op]

    cmp cl, '+'
    je .add
    cmp cl, '-'
    je .sub
    cmp cl, '*'
    je .mul
    cmp cl, '/'
    je .div
    cmp cl, 'x'
    je .mul

    ; Unknown operator
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_RED
    mov si, str_calc_badop
    call print_at
    call sh_newline
    call sh_newline
    ret

.add:
    add ax, bx
    jmp .show
.sub:
    sub ax, bx
    jmp .show
.mul:
    mul bx                          ; DX:AX = AX*BX, ignore overflow
    jmp .show
.div:
    cmp bx, 0
    je .divzero
    xor dx, dx
    div bx                          ; AX = AX/BX
    jmp .show

.divzero:
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_RED
    mov si, str_calc_div0
    call print_at
    call sh_newline
    call sh_newline
    ret

.show:
    push ax
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_BRIGHT
    mov si, str_calc_eq
    call print_at
    mov dh, [sh_row]
    mov dl, 6
    call setcursor
    pop ax
    call print_dec_at_cursor
    call sh_newline
    call sh_newline
    ret

; parse_dec: SI = string ptr, returns AX = number, advances SI
parse_dec:
    push bx
    push cx
    xor ax, ax
    mov bx, 10
.pd:
    mov cl, [si]
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    mul bx
    sub cl, '0'
    xor ch, ch
    add ax, cx
    inc si
    jmp .pd
.done:
    pop cx
    pop bx
    ret

; print_str_at_cursor: SI = 0-terminated, prints via BIOS teletype
print_str_at_cursor:
    push ax
    push bx
.ps:
    mov al, [si]
    or al, al
    jz .pd
    inc si
    mov ah, 0x0E
    xor bh, bh
    mov bl, 0x07
    int 0x10
    jmp .ps
.pd:
    pop bx
    pop ax
    ret

; print_hex_byte_at_cursor: AL = byte
print_hex_byte_at_cursor:
    push ax
    push ax
    shr al, 4
    call .nib
    pop ax
    and al, 0x0F
    call .nib
    pop ax
    ret
.nib:
    and al, 0x0F
    cmp al, 10
    jb .dig
    add al, 'A' - 10
    jmp .out
.dig:
    add al, '0'
.out:
    call putc_at_cursor
    ret

; print_hex_word_at_cursor: AX = word
print_hex_word_at_cursor:
    push ax
    mov al, ah
    call print_hex_byte_at_cursor
    pop ax
    call print_hex_byte_at_cursor
    ret

; ============================================================
; HASH_PASSWORD - FNV-1a 32-bit with key stretching + salt
;   In : hp_pw_ptr -> null-terminated password
;        hp_un_ptr -> null-terminated salt (username)
;   Out: hp_result = 32-bit hash (dword)
; ============================================================
hash_password:
    pushad
    mov eax, 0x811C9DC5         ; FNV-1a offset basis
    mov bp, 4096                ; rounds of key stretching
.hp_round:
    mov si, [hp_pw_ptr]
.hp_pw:
    mov bl, [si]
    or bl, bl
    jz .hp_un_start
    xor al, bl
    mov ecx, 0x01000193         ; FNV prime
    mul ecx                     ; EDX:EAX = EAX * ECX, keep low 32 in EAX
    inc si
    jmp .hp_pw
.hp_un_start:
    mov si, [hp_un_ptr]
.hp_un:
    mov bl, [si]
    or bl, bl
    jz .hp_round_done
    xor al, bl
    mov ecx, 0x01000193
    mul ecx
    inc si
    jmp .hp_un
.hp_round_done:
    dec bp
    jnz .hp_round
    mov [hp_result], eax
    popad
    ret

; ============================================================
; DISK_INIT - set DAP buffer segment to CS (once at boot)
; ============================================================
disk_init:
    push ax
    mov ax, cs
    mov [dap_buf_seg], ax
    pop ax
    ret

; ============================================================
; DISK_READ_CONFIG - read LBA 64 -> cfg_disk_buf via INT 13h AH=42h
;   Out: cfg_disk_ok = 1 on success, 0 on failure
; ============================================================
disk_read_config:
    push ax
    push dx
    push si
    mov byte [cfg_disk_ok], 0
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, dap
    int 0x13
    jc .drc_done
    mov byte [cfg_disk_ok], 1
.drc_done:
    pop si
    pop dx
    pop ax
    ret

; ============================================================
; DISK_WRITE_CONFIG - write cfg_disk_buf -> LBA 64 via AH=43h
; ============================================================
disk_write_config:
    push ax
    push dx
    push si
    mov byte [cfg_disk_ok], 0
    mov ah, 0x43
    mov al, 0                   ; write w/o verify
    mov dl, [boot_drive]
    mov si, dap
    int 0x13
    jc .dwc_done
    mov byte [cfg_disk_ok], 1
.dwc_done:
    pop si
    pop dx
    pop ax
    ret

; ============================================================
; LOAD_CONFIG_FROM_DISK - read sector, populate cfg_magic, cfg_username, cfg_pwhash
; ============================================================
load_config_from_disk:
    pusha
    call disk_read_config
    cmp byte [cfg_disk_ok], 1
    jne .lcfd_done

    ; Layout in cfg_disk_buf: magic(1) | username(33) | pwhash(4)
    mov al, [cfg_disk_buf]
    mov [cfg_magic], al

    mov si, cfg_disk_buf + 1
    mov di, cfg_username
    mov cx, 33
    rep movsb

    mov eax, [cfg_disk_buf + 34]
    mov [cfg_pwhash], eax
.lcfd_done:
    popa
    ret

; ============================================================
; SAVE_CONFIG_TO_DISK - serialize cfg_* and write sector
; ============================================================
save_config_to_disk:
    pusha

    ; Zero the buffer first
    mov di, cfg_disk_buf
    xor al, al
    mov cx, 512
    rep stosb

    ; magic(1) | username(33) | pwhash(4)
    mov al, [cfg_magic]
    mov [cfg_disk_buf], al

    mov si, cfg_username
    mov di, cfg_disk_buf + 1
    mov cx, 33
    rep movsb

    mov eax, [cfg_pwhash]
    mov [cfg_disk_buf + 34], eax

    call disk_write_config
    popa
    ret

; ============================================================
; PS/2 MOUSE DRIVER (polled, real-mode)
; ============================================================
ps2_wait_in:
    push cx
    push ax
    mov cx, 0xFFFF
.w:
    in al, 0x64
    test al, 0x02
    jz .d
    loop .w
.d:
    pop ax
    pop cx
    ret

ps2_wait_out:
    push cx
    push ax
    mov cx, 0xFFFF
.w:
    in al, 0x64
    test al, 0x01
    jnz .d
    loop .w
.d:
    pop ax
    pop cx
    ret

mouse_send:
    call ps2_wait_in
    mov al, 0xD4
    out 0x64, al
    call ps2_wait_in
    ret

mouse_ack:
    push cx
    mov cx, 0xFFFF
.w:
    in al, 0x64
    test al, 0x01
    jnz .r
    loop .w
    pop cx
    ret
.r:
    in al, 0x60
    pop cx
    ret

mouse_init:
    pusha
    ; Enable aux device
    call ps2_wait_in
    mov al, 0xA8
    out 0x64, al
    ; Read controller config
    call ps2_wait_in
    mov al, 0x20
    out 0x64, al
    call ps2_wait_out
    in al, 0x60
    and al, 0xDD         ; clear bit 1 (no mouse IRQ -- we poll) & bit 5 (enable mouse clock)
    mov bl, al
    ; Write config back
    call ps2_wait_in
    mov al, 0x60
    out 0x64, al
    call ps2_wait_in
    mov al, bl
    out 0x60, al
    ; Set defaults
    call mouse_send
    mov al, 0xF6
    out 0x60, al
    call mouse_ack
    ; Enable data reporting
    call mouse_send
    mov al, 0xF4
    out 0x60, al
    call mouse_ack

    mov byte [ms_pkt_idx], 0
    mov word [ms_x], 160
    mov word [ms_y], 100
    mov byte [ms_btn], 0
    mov byte [ms_saved], 0
    mov byte [ms_ready], 1
    popa
    ret

; mouse_poll - drain any pending PS/2 data; non-blocking
mouse_poll:
    push ax
    push bx
.l:
    in al, 0x64
    test al, 0x01
    jz .done
    test al, 0x20
    jz .kbd
    in al, 0x60
    movzx bx, byte [ms_pkt_idx]
    mov [ms_pkt+bx], al
    inc bx
    cmp bx, 3
    jl .save
    call mouse_process
    xor bx, bx
.save:
    mov [ms_pkt_idx], bl
    jmp .l
.kbd:
    ; Drain the keyboard byte from the PS/2 hardware output buffer.
    ; BIOS IRQ 1 already copied it into the BIOS key ring, so reading
    ; 0x60 here doesn't lose the keystroke — it just unblocks the
    ; single-byte PS/2 output register so mouse packets can flow again.
    in al, 0x60
    jmp .l          ; loop: check for more pending data
.done:
    pop bx
    pop ax
    ret

mouse_process:
    push ax
    push bx
    push dx
    mov al, [ms_pkt]
    test al, 0x08
    jz .bad             ; invalid packet header
    mov [ms_btn], al

    ; --- X ---
    test al, 0x40       ; X overflow -> ignore
    jnz .skip_x
    mov bl, [ms_pkt+1]
    mov bh, 0
    test bl, bl
    jns .x_pos
    mov bh, 0xFF
.x_pos:
    mov dx, [ms_x]
    add dx, bx
    cmp dx, 0
    jge .x_chi
    xor dx, dx
.x_chi:
    cmp dx, 319
    jle .x_ok
    mov dx, 319
.x_ok:
    mov [ms_x], dx
.skip_x:

    ; --- Y (mouse +y means up, screen +y means down -> negate) ---
    test al, 0x80
    jnz .skip_y
    mov bl, [ms_pkt+2]
    mov bh, 0
    test bl, bl
    jns .y_pos
    mov bh, 0xFF
.y_pos:
    neg bx
    mov dx, [ms_y]
    add dx, bx
    cmp dx, 0
    jge .y_chi
    xor dx, dx
.y_chi:
    cmp dx, 199
    jle .y_ok
    mov dx, 199
.y_ok:
    mov [ms_y], dx
.skip_y:

.bad:
    pop dx
    pop bx
    pop ax
    ret

; --- mouse_save_bg: save 8x8 region at ms_x,ms_y -> ms_bg ---
mouse_save_bg:
    pusha
    push es
    push ds

    ; Record save position while DS still points at the kernel.
    ; (Earlier this was done after DS was swapped to 0xA000, which
    ; meant ms_saved/ms_saved_x/ms_saved_y were being written into
    ; VRAM and never updated — so the cursor never got erased and
    ; left a trail at every position it visited.)
    mov ax, [ms_y]
    mov [ms_saved_y], ax
    mov bx, [ms_x]
    mov [ms_saved_x], bx
    mov byte [ms_saved], 1

    push ax                  ; save Y
    push bx                  ; save X

    push cs
    pop es                   ; ES = kernel (dest)
    mov di, ms_bg
    mov ax, 0xA000
    mov ds, ax               ; DS = VRAM (source)

    pop bx                   ; X
    pop ax                   ; Y
    imul ax, ax, 320
    add ax, bx
    mov si, ax

    mov cx, 8
.row:
    push cx
    push si
    mov cx, 8
.col:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    loop .col
    pop si
    pop cx
    add si, 320
    loop .row

    pop ds
    pop es
    popa
    ret

; --- mouse_restore_bg: restore previously-saved 8x8 region ---
mouse_restore_bg:
    pusha
    push es
    push ds
    cmp byte [ms_saved], 0
    je .skip

    push cs
    pop ds
    mov ax, 0xA000
    mov es, ax
    mov si, ms_bg

    mov ax, [ms_saved_y]
    mov bx, [ms_saved_x]
    imul ax, ax, 320
    add ax, bx
    mov di, ax

    mov cx, 8
.row:
    push cx
    push di
    mov cx, 8
.col:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    loop .col
    pop di
    pop cx
    add di, 320
    loop .row

    mov byte [ms_saved], 0
.skip:
    pop ds
    pop es
    popa
    ret

; --- mouse_draw_cursor: save bg then stamp arrow sprite ---
mouse_draw_cursor:
    call mouse_save_bg
    pusha
    push es
    push ds

    push cs
    pop ds
    mov ax, 0xA000
    mov es, ax
    mov si, ms_sprite

    mov ax, [ms_y]
    mov bx, [ms_x]
    imul ax, ax, 320
    add ax, bx
    mov di, ax

    mov cx, 8
.row:
    push cx
    push di
    mov cx, 8
.col:
    mov al, [si]
    or al, al
    jz .sk          ; 0 = transparent
    cmp al, 1
    jne .wh
    mov byte [es:di], 0x00   ; black border
    jmp .sk
.wh:
    mov byte [es:di], 0x0F   ; white fill
.sk:
    inc si
    inc di
    loop .col
    pop di
    pop cx
    add di, 320
    loop .row

    pop ds
    pop es
    popa
    ret

; ============================================================
; GFX_DRAW_BG - simple shaded background (blue gradient)
; ============================================================
gfx_draw_bg:
    push es
    push di
    push ax
    push bx
    push cx
    mov ax, 0xA000
    mov es, ax
    xor di, di
    mov bx, 200          ; row counter
.r:
    ; pick color based on row index
    mov al, 0            ; row counter from top
    mov cx, 200
    sub cx, bx
    ; color = 17 + (cx / 25)  -> roughly 17..24
    mov ax, cx
    shr ax, 5
    add al, 17
    mov ah, al
    mov cx, 320/2
    rep stosw
    dec bx
    jnz .r
    pop cx
    pop bx
    pop ax
    pop di
    pop es
    ret

; gfx_hline_bar: draw a filled horizontal bar
; AX=row, BL=color, fills 320 pixels wide
gfx_hline_bar:
    push es
    push di
    push ax
    push cx
    mov cx, ax
    mov ax, 0xA000
    mov es, ax
    mov ax, cx
    imul ax, ax, 320
    mov di, ax
    mov al, bl
    mov ah, bl
    mov cx, 320/2
    rep stosw
    pop cx
    pop ax
    pop di
    pop es
    ret

; gfx_box: draw an outlined box
; AX=x, BX=y, CX=w, DX=h, BP=color (lo byte)
gfx_box:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    push ax
    push bx
    push cx
    push dx
    ; top edge
    mov si, cx           ; width
.te:
    mov cx, ax
    mov dx, bx
    push ax
    mov ax, bp
    call gfx_putpixel
    pop ax
    inc ax
    dec si
    jnz .te
    pop dx
    pop cx
    pop bx
    pop ax

    push ax
    push bx
    push cx
    push dx
    ; bottom edge
    mov si, cx
    add bx, dx
    dec bx
.be:
    mov cx, ax
    mov dx, bx
    push ax
    mov ax, bp
    call gfx_putpixel
    pop ax
    inc ax
    dec si
    jnz .be
    pop dx
    pop cx
    pop bx
    pop ax

    push ax
    push bx
    push cx
    push dx
    ; left edge
    mov si, dx
.le:
    mov cx, ax
    mov dx, bx
    push ax
    mov ax, bp
    call gfx_putpixel
    pop ax
    inc bx
    dec si
    jnz .le
    pop dx
    pop cx
    pop bx
    pop ax

    push ax
    push bx
    push cx
    push dx
    ; right edge
    mov si, dx
    add ax, cx
    dec ax
.re:
    mov cx, ax
    mov dx, bx
    push ax
    mov ax, bp
    call gfx_putpixel
    pop ax
    inc bx
    dec si
    jnz .re
    pop dx
    pop cx
    pop bx
    pop ax

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; SNAKE GAME (graphics mode)
;  - 32x18 grid of 8x8 cells, centered at (32,16)
;  - Arrows steer, ESC quits, food = red, snake = green, head = bright
; ============================================================
SNAKE_CELL    equ 8
SNAKE_COLS    equ 32
SNAKE_ROWS    equ 18
SNAKE_OX      equ 32
SNAKE_OY      equ 20
SNAKE_MAX     equ 256

gfx_app_snake_entry:
    mov ax, 0x0013
    int 0x10
    call gfx_app_snake
    mov ax, 0x0003
    int 0x10
    ret

gfx_app_snake:
    xor al, al
    call gfx_fill

    mov bp, snk_title
    mov cx, 16
    mov dh, 0
    mov dl, 12
    mov bl, 0x0E
    call gfx_print

    mov bp, snk_hint
    mov cx, 28
    mov dh, 24
    mov dl, 6
    mov bl, 0x0F
    call gfx_print

    ; Border around play area
    mov ax, SNAKE_OX-1
    mov bx, SNAKE_OY-1
    mov cx, SNAKE_COLS*SNAKE_CELL+2
    mov dx, SNAKE_ROWS*SNAKE_CELL+2
    mov bp, 0x0F
    call gfx_box

    ; Initialize snake state
    mov word [snk_len], 4
    mov word [snk_head], 3
    mov word [snk_dir], 1                   ; right
    mov word [snk_score], 0

    ; place starting body  cells (0..3) horizontally at row 9
    mov byte [snk_body+0*2+0], 8
    mov byte [snk_body+0*2+1], 9
    mov byte [snk_body+1*2+0], 9
    mov byte [snk_body+1*2+1], 9
    mov byte [snk_body+2*2+0], 10
    mov byte [snk_body+2*2+1], 9
    mov byte [snk_body+3*2+0], 11
    mov byte [snk_body+3*2+1], 9

    call snk_place_food

    ; Initial draw
    call snk_redraw_all

.sloop:
    ; Read key non-blocking
    mov ah, 0x01
    int 0x16
    jz .no_key
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    je .quit
    cmp ah, 0x48
    jne .nu
    cmp word [snk_dir], 2
    je .no_key
    mov word [snk_dir], 0
    jmp .no_key
.nu:
    cmp ah, 0x4D
    jne .nr
    cmp word [snk_dir], 3
    je .no_key
    mov word [snk_dir], 1
    jmp .no_key
.nr:
    cmp ah, 0x50
    jne .nd
    cmp word [snk_dir], 0
    je .no_key
    mov word [snk_dir], 2
    jmp .no_key
.nd:
    cmp ah, 0x4B
    jne .no_key
    cmp word [snk_dir], 1
    je .no_key
    mov word [snk_dir], 3
.no_key:

    call snk_step
    cmp al, 0
    je .quit

    ; delay ~ frame
    mov cx, 0x0008
.do:
    push cx
    mov cx, 0xFFFF
.di:
    dec cx
    jnz .di
    pop cx
    loop .do
    jmp .sloop

.quit:
    ; Game over banner
    mov bp, snk_over
    mov cx, 9
    mov dh, 12
    mov dl, 16
    mov bl, 0x0C
    call gfx_print

    mov bp, snk_press
    mov cx, 18
    mov dh, 14
    mov dl, 12
    mov bl, 0x0F
    call gfx_print

    mov ah, 0
    int 0x16
    ret

; snk_step: advance one tick. AL=0 means game over.
snk_step:
    push bx
    push cx
    push dx
    push si
    push di

    ; Compute new head from old head + dir
    mov bx, [snk_head]
    shl bx, 1
    mov al, [snk_body+bx+0]         ; head X
    mov ah, [snk_body+bx+1]         ; head Y

    mov dx, [snk_dir]
    cmp dx, 0
    jne .nu
    dec ah
    jmp .gotnh
.nu:
    cmp dx, 1
    jne .nd
    inc al
    jmp .gotnh
.nd:
    cmp dx, 2
    jne .nl
    inc ah
    jmp .gotnh
.nl:
    dec al
.gotnh:
    ; collision with wall?
    cmp al, 0
    jl .die
    cmp al, SNAKE_COLS-1
    jg .die
    cmp ah, 0
    jl .die
    cmp ah, SNAKE_ROWS-1
    jg .die

    mov [snk_nx], al
    mov [snk_ny], ah

    ; collision with self? scan body
    mov si, snk_body
    mov dx, [snk_len]
    sub dx, 1                       ; check all except tail (tail will move)
.ck:
    cmp dx, 0
    jle .nocoll
    mov bl, [si]
    cmp bl, [snk_nx]
    jne .ckn
    mov bl, [si+1]
    cmp bl, [snk_ny]
    jne .ckn
    jmp .die
.ckn:
    add si, 2
    dec dx
    jmp .ck
.nocoll:

    ; Did we hit food?
    mov al, [snk_nx]
    mov ah, [snk_ny]
    cmp al, [snk_fx]
    jne .nofood
    cmp ah, [snk_fy]
    jne .nofood

    ; Grow: shift body right by 2 bytes (push new head at front conceptually).
    ; Easier: store body as array [0..len-1] where last is head.
    ; To grow: append new head; do not move tail.
    mov cx, [snk_len]
    cmp cx, SNAKE_MAX-1
    jge .nogrow
    mov bx, cx
    shl bx, 1
    mov al, [snk_nx]
    mov [snk_body+bx], al
    mov al, [snk_ny]
    mov [snk_body+bx+1], al
    inc word [snk_len]
    mov [snk_head], cx
    inc word [snk_score]
    call snk_place_food
    call snk_redraw_all
    jmp .ok
.nogrow:
    call snk_redraw_all
    jmp .ok

.nofood:
    ; Move: shift everything left by one slot
    mov cx, [snk_len]
    dec cx
    mov si, snk_body+2
    mov di, snk_body
.mv:
    cmp cx, 0
    je .mvd
    mov al, [si]
    mov [di], al
    mov al, [si+1]
    mov [di+1], al
    add si, 2
    add di, 2
    dec cx
    jmp .mv
.mvd:
    mov cx, [snk_len]
    dec cx
    mov bx, cx
    shl bx, 1
    mov al, [snk_nx]
    mov [snk_body+bx], al
    mov al, [snk_ny]
    mov [snk_body+bx+1], al
    mov [snk_head], cx
    call snk_redraw_all

.ok:
    mov al, 1
    jmp .done
.die:
    xor al, al
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

snk_redraw_all:
    pusha
    push es

    mov ax, 0xA000
    mov es, ax

    ; Clear play area
    mov cx, SNAKE_ROWS
    mov bx, SNAKE_OY
.cr:
    push cx
    mov cx, SNAKE_COLS
    mov dx, SNAKE_OX
.cc:
    push cx
    push dx
    mov ax, dx
    mov dx, bx
    ; draw 8x8 black cell at (ax, dx)
    push bx
    mov cx, 8
.cy:
    push cx
    mov cx, 8
    push ax
    mov di, dx
    imul di, di, 320
    add di, ax
    pop ax
.cx:
    mov byte [es:di], 0
    inc di
    loop .cx
    inc dx
    pop cx
    loop .cy
    pop bx
    pop dx
    pop cx
    add dx, SNAKE_CELL
    loop .cc
    pop cx
    add bx, SNAKE_CELL
    loop .cr

    pop es

    ; Draw food
    mov al, [snk_fx]
    mov ah, 0
    mov cx, ax
    imul cx, cx, SNAKE_CELL
    add cx, SNAKE_OX
    mov al, [snk_fy]
    mov ah, 0
    mov dx, ax
    imul dx, dx, SNAKE_CELL
    add dx, SNAKE_OY
    mov al, 0x0C            ; red
    call snk_fill_cell

    ; Draw body
    mov bx, [snk_len]
    xor si, si              ; index 0
.db:
    cmp si, bx
    jge .dbd
    mov ax, si
    shl ax, 1
    mov di, ax
    mov al, [snk_body+di]
    mov ah, 0
    mov cx, ax
    imul cx, cx, SNAKE_CELL
    add cx, SNAKE_OX
    mov al, [snk_body+di+1]
    mov ah, 0
    mov dx, ax
    imul dx, dx, SNAKE_CELL
    add dx, SNAKE_OY
    ; color: head bright green (0x0A), body darker green (0x02)
    push bx
    push si
    mov ax, [snk_head]
    cmp si, ax
    jne .body_col
    mov al, 0x0A
    jmp .draw_seg
.body_col:
    mov al, 0x02
.draw_seg:
    pop si
    pop bx
    call snk_fill_cell
    inc si
    jmp .db
.dbd:

    ; Score
    call snk_show_score
    popa
    ret

snk_fill_cell:
    ; AL=color, CX=x, DX=y; draw 8x8
    push es
    push di
    push ax
    push bx
    push cx
    push dx
    push si

    mov bx, 0xA000
    mov es, bx
    mov si, 8           ; row count
    mov ah, al          ; save color in AH
.r:
    push cx
    mov bx, dx
    imul bx, bx, 320
    add bx, cx
    mov di, bx
    mov cx, 8
    mov al, ah
.c:
    mov [es:di], al
    inc di
    loop .c
    inc dx
    pop cx
    dec si
    jnz .r

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop di
    pop es
    ret

snk_place_food:
    pusha
.try:
    xor ah, ah
    int 0x1A                ; CX:DX = ticks
    mov ax, dx
    xor ah, ah
    mov bl, SNAKE_COLS
    div bl                  ; AH = AX mod COLS
    mov [snk_fx], ah

    mov ax, cx
    xor ah, ah
    mov bl, SNAKE_ROWS
    div bl
    mov [snk_fy], ah

    ; Make sure it isn't on the snake
    mov si, snk_body
    mov cx, [snk_len]
.ck:
    cmp cx, 0
    je .ok
    mov al, [si]
    cmp al, [snk_fx]
    jne .nxt
    mov al, [si+1]
    cmp al, [snk_fy]
    jne .nxt
    ; collision -> retry
    add si, 2               ; (cleanup not strictly needed)
    jmp .try
.nxt:
    add si, 2
    dec cx
    jmp .ck
.ok:
    popa
    ret

snk_show_score:
    pusha
    ; Print SCORE: NNN at top-right corner
    mov bp, snk_scorelbl
    mov cx, 7
    mov dh, 0
    mov dl, 32
    mov bl, 0x0F
    call gfx_print
    ; Render number
    mov ax, [snk_score]
    ; Convert to up-to-3 digit decimal at (row 0, col 39) using BIOS teletype
    mov ah, 0x02
    mov bh, 0
    mov dh, 0
    mov dl, 39
    int 0x10
    mov ax, [snk_score]
    call snk_print_dec
    popa
    ret

snk_print_dec:
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov bx, 10
    cmp ax, 0
    jne .pl
    mov al, '0'
    call putc_at_cursor
    jmp .pd
.pl:
    cmp ax, 0
    je .em
    xor dx, dx
    div bx
    push dx
    inc cx
    jmp .pl
.em:
    cmp cx, 0
    je .pd
    pop ax
    add al, '0'
    call putc_at_cursor
    dec cx
    jmp .em
.pd:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================
; STARFIELD demo
; ============================================================
STAR_COUNT  equ 48

gfx_app_starfield:
    xor al, al
    call gfx_fill

    mov bp, sf_hint
    mov cx, 18
    mov dh, 24
    mov dl, 11
    mov bl, 0x0F
    call gfx_print

    ; Initialize stars from RTC
    mov cx, STAR_COUNT
    mov di, sf_stars
.init:
    push cx
    xor ah, ah
    int 0x1A
    mov ax, dx
    xor dx, dx
    mov bx, 320
    div bx
    mov [di+0], dx          ; x
    mov ax, cx
    xor dx, dx
    mov bx, 200
    div bx
    mov [di+2], dx          ; y
    pop cx
    push cx
    mov ax, cx
    and ax, 0x7F
    add ax, 1
    mov [di+4], ax          ; z (depth/speed)
    add di, 6
    pop cx
    loop .init

.sf_loop:
    mov ah, 0x01
    int 0x16
    jz .nk
    mov ah, 0x00
    int 0x16
    cmp ah, 0x01
    je .done
.nk:
    ; Erase old stars: redraw each black, then move, then draw white
    mov cx, STAR_COUNT
    mov di, sf_stars
.advance:
    push cx
    push di
    ; erase
    mov cx, [di+0]
    mov dx, [di+2]
    xor al, al
    call gfx_putpixel
    ; advance
    mov ax, [di+4]
    shr ax, 4
    add ax, 1
    add [di+0], ax
    mov ax, [di+0]
    cmp ax, 320
    jl .ok
    ; recycle: reset x to 0, randomize y
    mov word [di+0], 0
    xor ah, ah
    int 0x1A
    mov ax, dx
    xor dx, dx
    mov bx, 200
    div bx
    mov [di+2], dx
.ok:
    ; draw with brightness depending on z
    mov cx, [di+0]
    mov dx, [di+2]
    mov al, 0x0F
    mov bx, [di+4]
    cmp bx, 50
    jg .br
    mov al, 0x07
    cmp bx, 20
    jg .br
    mov al, 0x08
.br:
    call gfx_putpixel
    pop di
    pop cx
    add di, 6
    loop .advance

    ; small delay
    mov cx, 0x0002
.do:
    push cx
    mov cx, 0xFFFF
.di:
    dec cx
    jnz .di
    pop cx
    loop .do
    jmp .sf_loop
.done:
    ret

; ============================================================
; TOMMY'S C — English-like mini language
;   Programs live in ed_buf, one statement per line.
;   See str_manual for syntax.
; ============================================================
TC_BLK_IF    equ 1
TC_BLK_REP   equ 2

; tc_word: DI = 0-terminated keyword, SI = cursor.
;   If SI starts with the keyword followed by space/0/CR, advances SI past
;   the keyword and returns ZF=1. Otherwise SI is unchanged and ZF=0.
;   Trashes AL.
tc_word:
    push bx
    push di
    mov bx, si
.tw_l:
    mov al, [di]
    or al, al
    jz .tw_eos
    cmp al, [si]
    jne .tw_no
    inc si
    inc di
    jmp .tw_l
.tw_eos:
    mov al, [si]
    or al, al
    je .tw_yes
    cmp al, ' '
    je .tw_yes
    cmp al, 0x0D
    je .tw_yes
.tw_no:
    mov si, bx
    pop di
    pop bx
    mov al, 1
    or al, al               ; ZF=0
    ret
.tw_yes:
    pop di
    pop bx
    xor al, al              ; ZF=1
    ret

; tc_read_name: copies a sequence of letters at SI into tc_name_buf
;   (null-terminated, up to 8 chars). Advances SI past the name.
tc_read_name:
    push cx
    push di
    mov di, tc_name_buf
    mov cx, 8
.rn:
    mov al, [si]
    cmp al, 'A'
    jb .done
    cmp al, 'Z'
    jbe .store
    cmp al, 'a'
    jb .done
    cmp al, 'z'
    ja .done
.store:
    mov [di], al
    inc di
    inc si
    dec cx
    jnz .rn
.done:
    mov byte [di], 0
    pop di
    pop cx
    ret

; tc_find_var: search tc_var_names for tc_name_buf.
;   Returns AX = slot index, or 0xFFFF if not found.
tc_find_var:
    push si
    push di
    push cx
    push bx
    mov bx, tc_var_names
    xor cx, cx
.fv:
    cmp cx, 16
    jge .nope
    cmp byte [bx], 0
    je .next
    mov si, tc_name_buf
    mov di, bx
.cmp:
    mov al, [si]
    cmp al, [di]
    jne .ne
    or al, al
    jz .eq
    inc si
    inc di
    jmp .cmp
.ne:
    jmp .next
.eq:
    mov ax, cx
    jmp .done
.next:
    add bx, 9
    inc cx
    jmp .fv
.nope:
    mov ax, 0xFFFF
.done:
    pop bx
    pop cx
    pop di
    pop si
    ret

; tc_get_or_create_var: like tc_find_var but creates a new slot if missing.
;   Returns AX = slot index (0 if table is full).
tc_get_or_create_var:
    call tc_find_var
    cmp ax, 0xFFFF
    jne .got
    push si
    push di
    push cx
    push bx
    mov bx, tc_var_names
    xor cx, cx
.cr:
    cmp cx, 16
    jge .full
    cmp byte [bx], 0
    je .alloc
    add bx, 9
    inc cx
    jmp .cr
.alloc:
    mov si, tc_name_buf
    mov di, bx
    push cx
    mov cx, 9
    rep movsb
    pop cx
    mov bx, cx
    shl bx, 1
    add bx, tc_var_vals
    mov word [bx], 0
    mov ax, cx
    jmp .done2
.full:
    xor ax, ax
.done2:
    pop bx
    pop cx
    pop di
    pop si
.got:
    ret

; tc_find_var_or_zero: returns AX = value of variable in tc_name_buf,
;   or 0 if it doesn't exist.
tc_find_var_or_zero:
    call tc_find_var
    cmp ax, 0xFFFF
    je .zero
    shl ax, 1
    push bx
    mov bx, ax
    add bx, tc_var_vals
    mov ax, [bx]
    pop bx
    ret
.zero:
    xor ax, ax
    ret

; tc_eval: parse a number or variable name at SI. Returns AX = value.
;   Advances SI past the token.
tc_eval:
    push bx
    push cx
    mov al, [si]
    cmp al, '-'
    je .neg
    cmp al, '0'
    jb .var
    cmp al, '9'
    ja .var
    call parse_dec
    jmp .done3
.neg:
    inc si
    call parse_dec
    neg ax
    jmp .done3
.var:
    call tc_read_name
    call tc_find_var_or_zero
.done3:
    pop cx
    pop bx
    ret

; tc_print_num: prints AX as decimal at column 0 of current shell row.
tc_print_num:
    push ax
    push bx
    push dx
    mov bx, ax
    mov dh, [sh_row]
    mov dl, 0
    call setcursor
    mov ax, bx
    call print_dec_at_cursor
    pop dx
    pop bx
    pop ax
    ret

; tc_err_unknown: print "?" error in red on current row.
tc_err_unknown:
    push si
    push bx
    push dx
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_tc_err
    call print_at
    call sh_newline
    pop dx
    pop bx
    pop si
    ret

; tc_line_ptr: SI := ed_buf + tc_pc * ED_LINE_LEN
tc_line_ptr:
    push ax
    mov ax, [tc_pc]
    imul ax, ax, ED_LINE_LEN
    add ax, ed_buf
    mov si, ax
    pop ax
    ret

; tc_push_if: push an IF block onto the block stack.
tc_push_if:
    push ax
    push bx
    mov ax, [tc_bp]
    cmp ax, 16
    jge .full
    imul bx, ax, 5
    add bx, tc_blk_stack
    mov byte [bx], TC_BLK_IF
    inc word [tc_bp]
.full:
    pop bx
    pop ax
    ret

; tc_push_rep: push a REP block. BX = counter, tc_pc = repeat line.
tc_push_rep:
    push ax
    push di
    mov ax, [tc_bp]
    cmp ax, 16
    jge .full
    imul ax, ax, 5
    add ax, tc_blk_stack
    mov di, ax
    mov byte [di], TC_BLK_REP
    mov ax, [tc_pc]
    mov [di+1], ax
    mov [di+3], bx
    inc word [tc_bp]
.full:
    pop di
    pop ax
    ret

; tc_skip_block: advance tc_pc forward past the matching 'end',
;   tracking nested if/repeat. Stops on the 'end' line itself
;   (the main loop will then advance past it).
tc_skip_block:
    push cx
    mov cx, 1
.sk:
    inc word [tc_pc]
    mov ax, [tc_pc]
    cmp ax, [ed_lines]
    jge .done
    call tc_line_ptr
    call skip_spaces
    mov al, [si]
    or al, al
    je .sk
    cmp al, ';'
    je .sk
    mov di, tc_kw_if
    call tc_word
    je .open
    mov di, tc_kw_repeat
    call tc_word
    je .open
    mov di, tc_kw_end
    call tc_word
    je .close
    jmp .sk
.open:
    inc cx
    jmp .sk
.close:
    dec cx
    jnz .sk
.done:
    pop cx
    ret

; tc_exec_line: execute the statement on the current line.
tc_exec_line:
    call tc_line_ptr
    call skip_spaces
    mov al, [si]
    or al, al
    je .ret
    cmp al, ';'
    je .ret

    mov di, tc_kw_say
    call tc_word
    je .do_say
    mov di, tc_kw_ask
    call tc_word
    je .do_ask
    mov di, tc_kw_let
    call tc_word
    je .do_let
    mov di, tc_kw_add
    call tc_word
    je .do_add
    mov di, tc_kw_take
    call tc_word
    je .do_take
    mov di, tc_kw_times
    call tc_word
    je .do_times
    mov di, tc_kw_divide
    call tc_word
    je .do_divide
    mov di, tc_kw_modulo
    call tc_word
    je .do_modulo
    mov di, tc_kw_if
    call tc_word
    je .do_if
    mov di, tc_kw_repeat
    call tc_word
    je .do_repeat
    mov di, tc_kw_end
    call tc_word
    je .do_end
    mov di, tc_kw_stop
    call tc_word
    je .do_stop

    call tc_err_unknown
.ret:
    ret

.do_say:
    call skip_spaces
    mov al, [si]
    cmp al, '"'
    je .say_str
    cmp al, 0
    je .say_blank
    call tc_eval
    call tc_print_num
    call sh_newline
    ret
.say_blank:
    call sh_newline
    ret
.say_str:
    inc si
    push di
    mov di, tc_str_buf
.sy_copy:
    mov al, [si]
    or al, al
    je .sy_end
    cmp al, '"'
    je .sy_end
    mov [di], al
    inc di
    inc si
    jmp .sy_copy
.sy_end:
    mov byte [di], 0
    pop di
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_BRIGHT
    mov si, tc_str_buf
    call print_at
    call sh_newline
    ret

.do_ask:
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    push ax
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_tc_prompt
    call print_at
    mov dh, [sh_row]
    mov dl, 4
    call setcursor
    push di
    mov di, tc_str_buf
    mov cx, 20
    call readline_echo
    pop di
    call sh_newline
    mov si, tc_str_buf
    call skip_spaces
    call tc_eval
    pop bx
    shl bx, 1
    add bx, tc_var_vals
    mov [bx], ax
    ret

.do_let:
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    push ax
    call skip_spaces
    mov di, tc_kw_be
    call tc_word
    call skip_spaces
    call tc_eval
    pop bx
    shl bx, 1
    add bx, tc_var_vals
    mov [bx], ax
    ret

.do_add:
    call skip_spaces
    call tc_eval
    push ax
    call skip_spaces
    mov di, tc_kw_to
    call tc_word
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    mov bx, ax
    shl bx, 1
    add bx, tc_var_vals
    pop ax
    add [bx], ax
    ret

.do_take:
    call skip_spaces
    call tc_eval
    push ax
    call skip_spaces
    mov di, tc_kw_from
    call tc_word
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    mov bx, ax
    shl bx, 1
    add bx, tc_var_vals
    pop ax
    sub [bx], ax
    ret

.do_times:
    call skip_spaces
    call tc_eval
    push ax
    call skip_spaces
    mov di, tc_kw_by
    call tc_word
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    mov bx, ax
    shl bx, 1
    add bx, tc_var_vals
    pop ax
    mov cx, [bx]
    imul ax, cx
    mov [bx], ax
    ret

.do_divide:
    ; divide N by x  ->  x = x / N
    call skip_spaces
    call tc_eval            ; AX = N (divisor)
    push ax
    call skip_spaces
    mov di, tc_kw_by
    call tc_word
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    mov bx, ax
    shl bx, 1
    add bx, tc_var_vals
    pop cx                  ; CX = divisor
    cmp cx, 0
    je .dv_skip
    mov ax, [bx]
    xor dx, dx
    div cx
    mov [bx], ax
.dv_skip:
    ret

.do_modulo:
    ; modulo N by x  ->  x = x mod N
    call skip_spaces
    call tc_eval            ; AX = N (modulus)
    push ax
    call skip_spaces
    mov di, tc_kw_by
    call tc_word
    call skip_spaces
    call tc_read_name
    call tc_get_or_create_var
    mov bx, ax
    shl bx, 1
    add bx, tc_var_vals
    pop cx                  ; CX = modulus
    cmp cx, 0
    je .mo_skip
    mov ax, [bx]
    xor dx, dx
    div cx
    mov [bx], dx            ; DX = remainder
.mo_skip:
    ret

.do_if:
    call skip_spaces
    call tc_read_name
    call tc_find_var_or_zero
    push ax
    call skip_spaces
    mov di, tc_kw_is
    call tc_word
    call skip_spaces
    xor cx, cx
    mov di, tc_kw_not
    call tc_word
    jne .if_cmp
    mov cx, 1
    call skip_spaces
.if_cmp:
    call tc_eval
    pop bx
    cmp bx, ax
    jne .if_ne
    ; equal
    cmp cx, 0
    je .if_take
    jmp .if_skip
.if_ne:
    cmp cx, 1
    je .if_take
    jmp .if_skip
.if_take:
    call tc_push_if
    ret
.if_skip:
    call tc_skip_block
    ret

.do_repeat:
    call skip_spaces
    call tc_eval
    cmp ax, 0
    jle .rp_zero
    mov bx, ax
    call tc_push_rep
    ret
.rp_zero:
    call tc_skip_block
    ret

.do_end:
    cmp word [tc_bp], 0
    je .end_done
    mov ax, [tc_bp]
    dec ax
    imul ax, ax, 5
    add ax, tc_blk_stack
    mov bx, ax
    mov al, [bx]
    cmp al, TC_BLK_REP
    je .end_rep
    ; IF block: pop and continue
    dec word [tc_bp]
.end_done:
    ret
.end_rep:
    dec word [bx+3]
    cmp word [bx+3], 0
    jle .end_rep_pop
    mov ax, [bx+1]
    mov [tc_pc], ax
    ret
.end_rep_pop:
    dec word [tc_bp]
    ret

.do_stop:
    mov byte [tc_stop_flag], 1
    ret

; tc_run: run the program currently in ed_buf.
tc_run:
    mov word [tc_pc], 0
    mov word [tc_bp], 0
    mov byte [tc_stop_flag], 0

    mov di, tc_var_names
    mov cx, 16*9
    xor al, al
    rep stosb
    mov di, tc_var_vals
    mov cx, 16
    xor ax, ax
    rep stosw

    call clrscr
    call draw_titlebar
    call draw_win_titlebar
    call draw_statusbar

    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_tc_hdr
    call print_at

    mov dh, 3
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline

    mov byte [sh_row], 5

.next:
    cmp byte [tc_stop_flag], 0
    jne .end
    mov ax, [tc_pc]
    cmp ax, [ed_lines]
    jge .end

    call tc_exec_line

    inc word [tc_pc]
    jmp .next

.end:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_tc_done
    call print_at
    mov ah, 0x00
    int 0x16

    call clrscr
    call draw_titlebar
    call draw_statusbar
    mov dh, 2
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_shell_greet
    call print_at
    mov dh, 3
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_shell_hint
    call print_at
    mov dh, 4
    mov dl, 0
    mov bl, COL_CYAN
    mov cx, 80
    mov al, 0xC4
    call draw_hline
    mov byte [sh_row], 6
    ret

; ============================================================
; FILE SAVE / LOAD — persist ed_buf to disk at LBA 65 (23 sectors).
; ============================================================
tc_save:
    call sh_newline
    mov ax, cs
    mov [file_dap_seg], ax
    mov ah, 0x43
    mov al, 0
    mov dl, [boot_drive]
    mov si, file_dap
    int 0x13
    jc .err
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_tc_save_ok
    call print_at
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_tc_save_err
    call print_at
    call sh_newline
    ret

tc_load:
    call sh_newline
    mov ax, cs
    mov [file_dap_seg], ax
    push di
    push cx
    mov di, ed_buf
    mov cx, MAX_ED_LINES * ED_LINE_LEN
    xor al, al
    rep stosb
    pop cx
    pop di
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, file_dap
    int 0x13
    jc .err
    call tc_recount_lines
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_tc_load_ok
    call print_at
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_tc_load_err
    call print_at
    call sh_newline
    ret

; Recount ed_lines based on contents of ed_buf.
tc_recount_lines:
    push bx
    push cx
    push ax
    mov cx, MAX_ED_LINES
.rc:
    cmp cx, 0
    je .none
    dec cx
    mov ax, cx
    imul ax, ax, ED_LINE_LEN
    add ax, ed_buf
    mov bx, ax
    mov ax, ED_LINE_LEN
.scan:
    cmp byte [bx], 0
    jne .found
    inc bx
    dec ax
    jnz .scan
    jmp .rc
.found:
    inc cx
    mov [ed_lines], cx
    jmp .ret_lines
.none:
    mov word [ed_lines], 1
.ret_lines:
    pop ax
    pop cx
    pop bx
    ret

; ============================================================
; ============================================================
; TOMMYFS - persistent on-disk file system
;
; Layout:
;   LBA 100         Superblock (magic "TMFS")
;   LBA 101         Directory  (16 entries * 32 bytes)
;   LBA 102+        File data  (each slot = 24 sectors = 12288 bytes)
;
; Directory entry (32 bytes):
;   off 0      in-use flag (0=free, 1=used)
;   off 1..16  zero-terminated name (up to 15 chars)
;   off 17..18 file size in bytes (uint16)
;   off 19..31 reserved
;
; LBA of file slot N data = 102 + N*24    (0 <= N < 16)
; ============================================================

FS_LBA_SUPER  equ 100
FS_LBA_DIR    equ 101
FS_LBA_DATA   equ 102
FS_MAX_FILES  equ 16
FS_ENTRY_SIZE equ 32
FS_FILE_SECTS equ 23
FS_FILE_BYTES equ (FS_FILE_SECTS * 512)
FS_NAME_MAX   equ 15

; ----- fs_load_super: read LBA 100 into fs_disk_buf, set fs_ok = 1 on success -----
fs_load_super:
    pusha
    mov ax, cs
    mov [fs_dap_seg], ax
    mov word [fs_dap_count], 1
    mov word [fs_dap_off], fs_disk_buf
    mov dword [fs_dap_lba], FS_LBA_SUPER
    mov byte [fs_ok], 0
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, fs_dap
    int 0x13
    jc .d
    mov byte [fs_ok], 1
.d: popa
    ret

; ----- fs_save_super: write fs_disk_buf to LBA 100 -----
fs_save_super:
    pusha
    mov ax, cs
    mov [fs_dap_seg], ax
    mov word [fs_dap_count], 1
    mov word [fs_dap_off], fs_disk_buf
    mov dword [fs_dap_lba], FS_LBA_SUPER
    mov byte [fs_ok], 0
    mov ah, 0x43
    mov al, 0
    mov dl, [boot_drive]
    mov si, fs_dap
    int 0x13
    jc .d
    mov byte [fs_ok], 1
.d: popa
    ret

; ----- fs_load_dir: read LBA 101 into fs_dir_buf, sets fs_ok -----
fs_load_dir:
    pusha
    mov ax, cs
    mov [fs_dap_seg], ax
    mov word [fs_dap_count], 1
    mov word [fs_dap_off], fs_dir_buf
    mov dword [fs_dap_lba], FS_LBA_DIR
    mov byte [fs_ok], 0
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, fs_dap
    int 0x13
    jc .d
    mov byte [fs_ok], 1
.d: popa
    ret

; ----- fs_save_dir: write fs_dir_buf to LBA 101 -----
fs_save_dir:
    pusha
    mov ax, cs
    mov [fs_dap_seg], ax
    mov word [fs_dap_count], 1
    mov word [fs_dap_off], fs_dir_buf
    mov dword [fs_dap_lba], FS_LBA_DIR
    mov byte [fs_ok], 0
    mov ah, 0x43
    mov al, 0
    mov dl, [boot_drive]
    mov si, fs_dap
    int 0x13
    jc .d
    mov byte [fs_ok], 1
.d: popa
    ret

; ----- fs_check: returns AL=1 if formatted, AL=0 otherwise -----
fs_check:
    call fs_load_super
    cmp byte [fs_ok], 1
    jne .no
    cmp dword [fs_disk_buf], 0x53464D54   ; "TMFS" little endian
    jne .no
    mov al, 1
    ret
.no:
    xor al, al
    ret

; ----- fs_format: build superblock + empty directory, write both -----
fs_format:
    pusha
    ; -- Build superblock --
    mov di, fs_disk_buf
    xor al, al
    mov cx, 512
    rep stosb
    mov dword [fs_disk_buf], 0x53464D54   ; "TMFS"
    mov word  [fs_disk_buf+4], 1          ; version
    mov word  [fs_disk_buf+6], FS_MAX_FILES
    mov dword [fs_disk_buf+8], FS_FILE_SECTS
    call fs_save_super

    ; -- Empty directory --
    mov di, fs_dir_buf
    xor al, al
    mov cx, 512
    rep stosb
    call fs_save_dir
    popa
    ret

; ----- fs_entry_ptr: BX <- pointer to entry at index AL (0..15) -----
fs_entry_ptr:
    push ax
    movzx bx, al
    shl bx, 5            ; * 32
    add bx, fs_dir_buf
    pop ax
    ret

; ----- fs_name_match: compare zero-terminated SI to DI, ZF set if equal -----
fs_name_match:
    push si
    push di
    push ax
.nm:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .no
    or al, al
    je .yes
    inc si
    inc di
    jmp .nm
.no:
    pop ax
    pop di
    pop si
    or ax, 1
    cmp ax, 0
    ret
.yes:
    pop ax
    pop di
    pop si
    xor ax, ax
    cmp ax, 0
    ret

; ----- fs_find: search dir for name pointed to by SI.
;       On hit: AL = index, ZF=1.  On miss: ZF=0. -----
fs_find:
    push bx
    push cx
    push si
    mov cx, FS_MAX_FILES
    xor al, al
.fl:
    push ax
    call fs_entry_ptr
    cmp byte [bx], 1
    jne .skip
    push si
    mov di, bx
    inc di                 ; entry name field
    call fs_name_match
    pop si
    je .found
.skip:
    pop ax
    inc al
    cmp al, FS_MAX_FILES
    jl .fl
    pop si
    pop cx
    pop bx
    or al, 1               ; clear ZF
    cmp al, 0
    ret
.found:
    add sp, 2               ; drop pushed ax (preserve our AL)
    pop si
    pop cx
    pop bx
    xor ah, ah
    cmp ah, 0               ; set ZF
    ret

; ----- fs_find_free: AL=first free index, ZF=1; else ZF=0 -----
fs_find_free:
    push bx
    xor al, al
.fl:
    call fs_entry_ptr
    cmp byte [bx], 0
    je .got
    inc al
    cmp al, FS_MAX_FILES
    jl .fl
    pop bx
    or al, 1
    cmp al, 0
    ret
.got:
    pop bx
    xor ah, ah
    cmp ah, 0
    ret

; ----- fs_file_lba: AL = slot index -> EAX = LBA of file data start -----
fs_file_lba:
    push bx
    movzx bx, al
    imul bx, bx, FS_FILE_SECTS
    add bx, FS_LBA_DATA
    movzx eax, bx
    pop bx
    ret

; ----- fs_read_slot: AL = slot index. Reads FS_FILE_SECTS sectors -> ed_buf -----
fs_read_slot:
    pusha
    call fs_file_lba
    mov ax, cs
    mov [fs_dap_seg], ax
    mov word [fs_dap_count], FS_FILE_SECTS
    mov word [fs_dap_off], ed_buf
    push eax
    pop dword [fs_dap_lba]
    mov byte [fs_ok], 0
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, fs_dap
    int 0x13
    jc .d
    mov byte [fs_ok], 1
.d: popa
    ret

; ----- fs_write_slot: AL = slot index. Writes ed_buf -> file data sectors -----
fs_write_slot:
    pusha
    call fs_file_lba
    mov ax, cs
    mov [fs_dap_seg], ax
    mov word [fs_dap_count], FS_FILE_SECTS
    mov word [fs_dap_off], ed_buf
    push eax
    pop dword [fs_dap_lba]
    mov byte [fs_ok], 0
    mov ah, 0x43
    mov al, 0
    mov dl, [boot_drive]
    mov si, fs_dap
    int 0x13
    jc .d
    mov byte [fs_ok], 1
.d: popa
    ret

; ----- fs_ensure_mounted: format if uninitialised -----
fs_ensure_mounted:
    call fs_check
    test al, al
    jnz .ok
    call fs_format
.ok:
    call fs_load_dir
    ret

; ============================================================
; CMD: fs_init - reformat the file system (asks for confirmation)
; ============================================================
cmd_fs_init:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_fs_init_q
    call print_at
    mov dh, [sh_row]
    mov dl, 30
    call setcursor
    mov ah, 0
    int 0x16
    cmp al, 'y'
    je .doit
    cmp al, 'Y'
    je .doit
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_NORMAL
    mov si, str_fs_cancel
    call print_at
    call sh_newline
    ret
.doit:
    call fs_format
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_fs_formatted
    call print_at
    call sh_newline
    ret

; ============================================================
; CMD: dir - list files in TommyFS
; ============================================================
cmd_dir:
    call sh_newline
    call fs_ensure_mounted
    cmp byte [fs_ok], 1
    jne .err

    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_dir_hdr
    call print_at
    call sh_newline

    mov word [fs_used], 0
    xor al, al
.lp:
    push ax
    call fs_entry_ptr
    cmp byte [bx], 1
    jne .next

    inc word [fs_used]
    ; print "  NAME............  NNNN bytes"
    mov dh, [sh_row]
    mov dl, 2
    call setcursor
    push bx
    inc bx                  ; -> name
    mov si, bx
    call print_str_at_cursor
    pop bx

    mov dh, [sh_row]
    mov dl, 22
    call setcursor
    mov ax, [bx+17]
    call print_dec_at_cursor
    mov si, str_dir_bytes
    call print_str_at_cursor
    call sh_newline

.next:
    pop ax
    inc al
    cmp al, FS_MAX_FILES
    jl .lp

    cmp word [fs_used], 0
    jne .footer
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_dir_empty
    call print_at
    call sh_newline
.footer:
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_YELLOW
    mov si, str_dir_used
    call print_at
    mov dh, [sh_row]
    mov dl, 9
    call setcursor
    mov ax, [fs_used]
    call print_dec_at_cursor
    mov si, str_dir_of
    call print_str_at_cursor
    mov ax, FS_MAX_FILES
    call print_dec_at_cursor
    mov si, str_dir_files
    call print_str_at_cursor
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_err
    call print_at
    call sh_newline
    ret

; ============================================================
; arg_after_cmd: SI points just past the command word.
; Skips spaces, copies word (up to 15 chars) into arg_name[].
; Returns CX = length.
; ============================================================
arg_after_cmd:
    push ax
    push di
    call skip_spaces
    mov di, arg_name
    xor cx, cx
.copy:
    mov al, [si]
    cmp al, 0
    je .done
    cmp al, ' '
    je .done
    cmp al, 0x0D
    je .done
    cmp cx, FS_NAME_MAX
    jge .skip
    mov [di], al
    inc di
.skip:
    inc si
    inc cx
    jmp .copy
.done:
    mov byte [di], 0
    pop di
    pop ax
    ret

; Skip first command word in cmd_buf, leaving SI at the rest
skip_first_word:
    mov si, cmd_buf
    call skip_spaces
.sw:
    mov al, [si]
    cmp al, 0
    je .done
    cmp al, ' '
    je .done
    cmp al, 0x0D
    je .done
    inc si
    jmp .sw
.done:
    ret

; ============================================================
; CMD: cat <name>
; ============================================================
cmd_cat:
    call sh_newline
    call fs_ensure_mounted
    call skip_first_word
    call arg_after_cmd
    cmp byte [arg_name], 0
    je .usage

    mov si, arg_name
    call fs_find
    jne .nf

    push ax
    call fs_entry_ptr
    mov ax, [bx+17]              ; size
    mov [cat_size], ax
    pop ax

    call fs_read_slot
    cmp byte [fs_ok], 1
    jne .err

    ; Print ed_buf, up to cat_size bytes, handling 0x0A as newlines
    mov si, ed_buf
    mov cx, [cat_size]
    cmp cx, 0
    je .empty
.line:
    mov dh, [sh_row]
    mov dl, 2
    call setcursor
.ch:
    cmp cx, 0
    je .pdone
    lodsb
    dec cx
    cmp al, 0
    je .pdone
    cmp al, 0x0A
    je .nl
    cmp al, 0x0D
    je .ch
    call putc_at_cursor
    jmp .ch
.nl:
    call sh_newline
    jmp .line
.pdone:
    call sh_newline
    ret
.empty:
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_cat_empty
    call print_at
    call sh_newline
    ret
.usage:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_cat_usage
    call print_at
    call sh_newline
    ret
.nf:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_nf
    call print_at
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_err
    call print_at
    call sh_newline
    ret

; ============================================================
; CMD: del <name>
; ============================================================
cmd_del:
    call sh_newline
    call fs_ensure_mounted
    call skip_first_word
    call arg_after_cmd
    cmp byte [arg_name], 0
    je .usage

    mov si, arg_name
    call fs_find
    jne .nf

    call fs_entry_ptr
    mov byte [bx], 0          ; clear in-use
    push bx
    add bx, 1
    mov di, bx
    xor al, al
    mov cx, FS_ENTRY_SIZE-1
    rep stosb
    pop bx
    call fs_save_dir

    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_del_ok
    call print_at
    call sh_newline
    ret
.usage:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_del_usage
    call print_at
    call sh_newline
    ret
.nf:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_nf
    call print_at
    call sh_newline
    ret

; ============================================================
; CMD: write <name>  - save ed_buf into named file
; ============================================================
cmd_write:
    call sh_newline
    call fs_ensure_mounted
    call skip_first_word
    call arg_after_cmd
    cmp byte [arg_name], 0
    je .usage

    ; If exists, overwrite. Else find free slot.
    mov si, arg_name
    call fs_find
    je .have_slot
    call fs_find_free
    jne .full
.have_slot:
    push ax                   ; save slot index

    ; Compute byte size used in ed_buf (look for trailing zeros)
    call ed_buf_size_used
    mov [write_size], ax

    pop ax
    push ax
    call fs_entry_ptr
    mov byte [bx], 1
    ; Copy name (up to 15 chars + null)
    push di
    push si
    push cx
    lea di, [bx+1]
    mov si, arg_name
    mov cx, FS_NAME_MAX+1
    rep movsb
    pop cx
    pop si
    pop di
    mov ax, [write_size]
    mov [bx+17], ax

    pop ax
    call fs_write_slot
    cmp byte [fs_ok], 1
    jne .err
    call fs_save_dir

    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_write_ok
    call print_at
    call sh_newline
    ret
.usage:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_write_usage
    call print_at
    call sh_newline
    ret
.full:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_full
    call print_at
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_err
    call print_at
    call sh_newline
    ret

; Compute used byte count in ed_buf (last non-zero+1, capped to FS_FILE_BYTES)
ed_buf_size_used:
    push bx
    push cx
    mov bx, MAX_ED_LINES * ED_LINE_LEN
.scan:
    cmp bx, 0
    je .done
    dec bx
    cmp byte [ed_buf + bx], 0
    je .scan
    inc bx
.done:
    mov ax, bx
    cmp ax, FS_FILE_BYTES
    jbe .ok
    mov ax, FS_FILE_BYTES
.ok:
    pop cx
    pop bx
    ret

; ============================================================
; CMD: read <name>  - load named file into ed_buf
; ============================================================
cmd_read:
    call sh_newline
    call fs_ensure_mounted
    call skip_first_word
    call arg_after_cmd
    cmp byte [arg_name], 0
    je .usage

    mov si, arg_name
    call fs_find
    jne .nf

    ; Clear ed_buf first
    push ax
    push di
    push cx
    mov di, ed_buf
    mov cx, MAX_ED_LINES * ED_LINE_LEN
    xor al, al
    rep stosb
    pop cx
    pop di
    pop ax

    call fs_read_slot
    cmp byte [fs_ok], 1
    jne .err
    call tc_recount_lines

    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_read_ok
    call print_at
    call sh_newline
    ret
.usage:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_read_usage
    call print_at
    call sh_newline
    ret
.nf:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_nf
    call print_at
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_err
    call print_at
    call sh_newline
    ret

; ============================================================
; CMD: df - disk usage summary
; ============================================================
cmd_df:
    call sh_newline
    call fs_ensure_mounted

    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_df_hdr
    call print_at
    call sh_newline

    ; count used files, sum bytes
    mov word [fs_used], 0
    mov word [fs_total_bytes], 0
    xor al, al
.lp:
    push ax
    call fs_entry_ptr
    cmp byte [bx], 1
    jne .next
    inc word [fs_used]
    mov cx, [bx+17]
    add [fs_total_bytes], cx
.next:
    pop ax
    inc al
    cmp al, FS_MAX_FILES
    jl .lp

    ; Files line
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_df_files
    call print_at
    mov dh, [sh_row]
    mov dl, 16
    call setcursor
    mov ax, [fs_used]
    call print_dec_at_cursor
    mov si, str_dir_of
    call print_str_at_cursor
    mov ax, FS_MAX_FILES
    call print_dec_at_cursor
    call sh_newline

    ; Used bytes line
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_df_used
    call print_at
    mov dh, [sh_row]
    mov dl, 16
    call setcursor
    mov ax, [fs_total_bytes]
    call print_dec_at_cursor
    mov si, str_dir_bytes
    call print_str_at_cursor
    call sh_newline

    ; Slot size line
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_df_slot
    call print_at
    mov dh, [sh_row]
    mov dl, 16
    call setcursor
    mov ax, FS_FILE_BYTES
    call print_dec_at_cursor
    mov si, str_dir_bytes
    call print_str_at_cursor
    call sh_newline
    ret

; ============================================================
; CMD: hist - print command history (oldest -> newest)
; ============================================================
cmd_hist:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_hist_hdr
    call print_at
    call sh_newline
    movzx cx, byte [hist_count]
    test cx, cx
    jnz .lp
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_hist_empty
    call print_at
    call sh_newline
    ret
.lp:
    movzx bx, byte [hist_count]
    sub bx, cx
    ; entry index = (hist_head - hist_count + bx) mod 8
    movzx ax, byte [hist_head]
    movzx dx, byte [hist_count]
    sub ax, dx
    add ax, bx
    and ax, 7
    imul ax, ax, MAX_CMD
    add ax, hist_buf

    mov dh, [sh_row]
    mov dl, 2
    push cx
    push ax
    mov bl, COL_NORMAL
    mov si, ax
    call print_at
    pop ax
    pop cx
    call sh_newline
    dec cx
    jnz .lp
    ret

; ============================================================
; CMD: clock - live clock until ESC pressed
; ============================================================
cmd_clock:
    call sh_newline
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_clock_hint
    call print_at
    call sh_newline
    mov byte [clk_row], 0
    mov al, [sh_row]
    mov [clk_row], al

.tick:
    ; Get time
    mov ah, 0x02
    int 0x1A

    mov dh, [clk_row]
    mov dl, 2
    call setcursor
    mov al, ch
    call print_bcd_at_cursor
    mov al, ':'
    call putc_at_cursor
    mov al, cl
    call print_bcd_at_cursor
    mov al, ':'
    call putc_at_cursor
    mov al, dh
    call print_bcd_at_cursor

    ; Wait ~250ms via tick count, polling keyboard
    mov ah, 0x00
    int 0x1A          ; CX:DX = ticks
    mov bx, dx
    add bx, 4         ; ~4 ticks ~= 220ms
.poll:
    mov ah, 0x01
    int 0x16
    jz .nokey
    mov ah, 0
    int 0x16
    cmp al, 27        ; ESC
    je .quit
.nokey:
    mov ah, 0x00
    int 0x1A
    cmp dx, bx
    jb .poll
    jmp .tick
.quit:
    call sh_newline
    ret

; ============================================================
; CMD: hexdump <name> - show first 128 bytes of file as hex
; ============================================================
cmd_hexdump:
    call sh_newline
    call fs_ensure_mounted
    call skip_first_word
    call arg_after_cmd
    cmp byte [arg_name], 0
    je .usage

    mov si, arg_name
    call fs_find
    jne .nf
    call fs_read_slot
    cmp byte [fs_ok], 1
    jne .err

    mov bx, 0          ; offset
    mov cx, 8          ; 8 rows of 16 bytes = 128 bytes
.row:
    mov dh, [sh_row]
    mov dl, 0
    call setcursor
    mov ax, bx
    call print_hex_word_at_cursor
    mov al, ':'
    call putc_at_cursor
    mov al, ' '
    call putc_at_cursor

    push cx
    mov cx, 16
.byte:
    push bx
    mov al, [ed_buf + bx]
    call print_hex_byte_at_cursor
    pop bx
    inc bx
    mov al, ' '
    call putc_at_cursor
    loop .byte
    pop cx
    call sh_newline
    loop .row
    ret
.usage:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_hex_usage
    call print_at
    call sh_newline
    ret
.nf:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_nf
    call print_at
    call sh_newline
    ret
.err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_err
    call print_at
    call sh_newline
    ret

; ============================================================
; CMD: ttt - tic-tac-toe game
;
; Board is a 3x3 grid; positions 1..9.
; Player X, computer O. Player picks number; computer plays simple
; corner/center/random strategy.
; ============================================================
cmd_ttt:
    call sh_newline

    ; Clear board
    push di
    push ax
    mov di, ttt_cells
    mov al, ' '
    mov cx, 9
    rep stosb
    pop ax
    pop di
    mov byte [ttt_turn], 'X'

    call ttt_draw_hdr
    call ttt_draw_board

.loop:
    cmp byte [ttt_turn], 'X'
    jne .ai

    ; Player input
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_ttt_prompt
    call print_at
    mov dh, [sh_row]
    mov dl, 14
    call setcursor
    mov ah, 0
    int 0x16
    cmp al, 27
    je .quit
    cmp al, '1'
    jl .loop
    cmp al, '9'
    jg .loop
    sub al, '1'             ; index 0..8
    movzx bx, al
    cmp byte [ttt_cells + bx], ' '
    jne .loop
    mov byte [ttt_cells + bx], 'X'
    call sh_newline
    call ttt_draw_board

    call ttt_check
    cmp al, 'X'
    je .won
    cmp al, 'D'
    je .draw
    mov byte [ttt_turn], 'O'
    jmp .loop

.ai:
    call ttt_ai_move
    call sh_newline
    call ttt_draw_board
    call ttt_check
    cmp al, 'O'
    je .lost
    cmp al, 'D'
    je .draw
    mov byte [ttt_turn], 'X'
    jmp .loop

.won:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_ttt_won
    call print_at
    call sh_newline
    ret
.lost:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_ttt_lost
    call print_at
    call sh_newline
    ret
.draw:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_ttt_draw
    call print_at
    call sh_newline
    ret
.quit:
    call sh_newline
    ret

ttt_draw_hdr:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_CYAN
    mov si, str_ttt_hdr
    call print_at
    call sh_newline
    ret

ttt_draw_board:
    ; Render 3x3 with separators, like:
    ;   X | O | X
    ;  ---+---+---
    push bx
    mov bx, 0
.row:
    mov dh, [sh_row]
    mov dl, 2
    call setcursor
    mov al, [ttt_cells + bx]
    call putc_at_cursor
    mov al, ' '
    call putc_at_cursor
    mov al, '|'
    call putc_at_cursor
    mov al, ' '
    call putc_at_cursor
    mov al, [ttt_cells + bx + 1]
    call putc_at_cursor
    mov al, ' '
    call putc_at_cursor
    mov al, '|'
    call putc_at_cursor
    mov al, ' '
    call putc_at_cursor
    mov al, [ttt_cells + bx + 2]
    call putc_at_cursor
    call sh_newline

    add bx, 3
    cmp bx, 9
    jge .done
    mov dh, [sh_row]
    mov dl, 2
    mov bl, COL_NORMAL
    mov si, str_ttt_sep
    call print_at
    call sh_newline
    jmp .row
.done:
    pop bx
    ret

; ttt_check: return AL = 'X', 'O', 'D' (draw), or ' ' (none)
ttt_check:
    push bx
    push cx
    push si
    mov si, ttt_wins
.lp:
    movzx bx, byte [si]
    cmp bx, 0xFF
    je .nowin
    mov al, [ttt_cells + bx]
    cmp al, ' '
    je .nx
    movzx bx, byte [si+1]
    cmp al, [ttt_cells + bx]
    jne .nx
    movzx bx, byte [si+2]
    cmp al, [ttt_cells + bx]
    jne .nx
    jmp .win
.nx:
    add si, 3
    jmp .lp
.nowin:
    ; check draw
    xor bx, bx
.d:
    cmp byte [ttt_cells + bx], ' '
    je .ng
    inc bx
    cmp bx, 9
    jl .d
    mov al, 'D'
    jmp .ret
.ng:
    mov al, ' '
    jmp .ret
.win:
    ; AL already holds winner
.ret:
    pop si
    pop cx
    pop bx
    ret

; ttt_ai_move: simple AI. Try win, block, center, corner, random.
ttt_ai_move:
    ; Try to win
    mov al, 'O'
    call ttt_try_complete
    cmp al, 0xFF
    jne .place
    ; Block X
    mov al, 'X'
    call ttt_try_complete
    cmp al, 0xFF
    jne .place
    ; Center
    cmp byte [ttt_cells + 4], ' '
    jne .corners
    mov al, 4
    jmp .place
.corners:
    cmp byte [ttt_cells + 0], ' '
    jne .c1
    mov al, 0
    jmp .place
.c1:
    cmp byte [ttt_cells + 2], ' '
    jne .c2
    mov al, 2
    jmp .place
.c2:
    cmp byte [ttt_cells + 6], ' '
    jne .c3
    mov al, 6
    jmp .place
.c3:
    cmp byte [ttt_cells + 8], ' '
    jne .anyside
    mov al, 8
    jmp .place
.anyside:
    xor bx, bx
.sl:
    cmp byte [ttt_cells + bx], ' '
    je .placed
    inc bx
    cmp bx, 9
    jl .sl
    ret
.placed:
    mov al, bl
.place:
    movzx bx, al
    mov byte [ttt_cells + bx], 'O'
    ret

; AL = player char to try completing (i.e. find win for that player).
; Returns AL = index of the move cell, or 0xFF if none.
ttt_try_complete:
    push bx
    push cx
    push dx
    push si
    mov dl, al                 ; target char
    mov si, ttt_wins
.lp:
    movzx bx, byte [si]
    cmp bx, 0xFF
    je .none
    mov ah, [ttt_cells + bx]
    movzx bx, byte [si+1]
    mov al, [ttt_cells + bx]
    movzx bx, byte [si+2]
    mov dh, [ttt_cells + bx]
    ; Count matches of dl and presence of one ' '
    xor cl, cl              ; matches
    xor ch, ch              ; blank index encoding (0/1/2 +1)
    cmp ah, dl
    jne .a2
    inc cl
.a2:
    cmp al, dl
    jne .a3
    inc cl
.a3:
    cmp dh, dl
    jne .ck
    inc cl
.ck:
    cmp cl, 2
    jne .nx
    ; find the blank one
    cmp ah, ' '
    jne .b2
    movzx ax, byte [si]
    jmp .got
.b2:
    cmp al, ' '
    jne .b3
    movzx ax, byte [si+1]
    jmp .got
.b3:
    cmp dh, ' '
    jne .nx
    movzx ax, byte [si+2]
.got:
    pop si
    pop dx
    pop cx
    pop bx
    ret
.nx:
    add si, 3
    jmp .lp
.none:
    mov al, 0xFF
    pop si
    pop dx
    pop cx
    pop bx
    ret

; Winning lines as triplets of cell indices, terminated by 0xFF
ttt_wins:
    db 0,1,2, 3,4,5, 6,7,8        ; rows
    db 0,3,6, 1,4,7, 2,5,8        ; cols
    db 0,4,8, 2,4,6               ; diags
    db 0xFF

; ============================================================
; CMD: rename <old> <new> - rename a TommyFS file
; ============================================================
cmd_rename:
    call sh_newline
    call fs_ensure_mounted
    call skip_first_word
    call arg_after_cmd          ; arg_name = old name
    cmp byte [arg_name], 0
    je .rn_usage
    ; save old name
    push si
    push di
    push cx
    mov si, arg_name
    mov di, rename_buf
    mov cx, FS_NAME_MAX + 1
    rep movsb
    pop cx
    pop di
    pop si
    call arg_after_cmd          ; arg_name = new name
    cmp byte [arg_name], 0
    je .rn_usage
    ; find old name
    mov si, rename_buf
    call fs_find
    jne .rn_nf
    ; update directory entry name field
    call fs_entry_ptr           ; BX -> entry
    push di
    push si
    push cx
    lea di, [bx+1]
    mov si, arg_name
    mov cx, FS_NAME_MAX + 1
    rep movsb
    pop cx
    pop si
    pop di
    call fs_save_dir
    cmp byte [fs_ok], 1
    jne .rn_err
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_GREEN
    mov si, str_rename_ok
    call print_at
    call sh_newline
    ret
.rn_usage:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_YELLOW
    mov si, str_rename_usage
    call print_at
    call sh_newline
    ret
.rn_nf:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_nf
    call print_at
    call sh_newline
    ret
.rn_err:
    mov dh, [sh_row]
    mov dl, 0
    mov bl, COL_RED
    mov si, str_fs_err
    call print_at
    call sh_newline
    ret

; ============================================================
; CMD: motd - cute banner
; ============================================================
cmd_motd:
    call sh_newline
    mov si, str_motd
    mov bl, COL_MAGENTA
    call sh_print_multiline
    call sh_newline
    ret

; ============================================================
; DATA
; ============================================================
boot_drive      db 0

; Config (persisted to LBA 64 on the boot drive)
cfg_magic       db 0            ; 0xAB = configured
cfg_username    times 33 db 0
cfg_pwhash      dd 0            ; FNV-1a 32-bit hash (4096 rounds, salted w/ username)
cfg_disk_ok     db 0            ; 1 = last disk op succeeded

; Hash function I/O
hp_pw_ptr       dw 0
hp_un_ptr       dw 0
hp_result       dd 0

; INT 13h Disk Address Packet (LBA mode)
dap:
                db 0x10         ; DAP size
                db 0            ; reserved
                dw 1            ; sector count
                dw cfg_disk_buf ; buffer offset
dap_buf_seg     dw 0            ; buffer segment (set to CS at boot)
                dd 64           ; LBA low (config sector)
                dd 0            ; LBA high

; Setup buffers
username        times 33 db 0
password        times 33 db 0
drive_choice    times 5  db 0
login_buf       times 33 db 0

; Drive enum
drv_idx         db 0
drv_cur         db 0
drv_tmp         db '0'
drv_row         db 14
align 4
drv_size_mb     dd 0
ext_buf         times 64 db 0
q_dl            db 0
q_max_cyl_lo    db 0
q_max_cyl_hi    db 0
q_max_head      db 0
q_spt           db 0

; Shell state
sh_row          db 6
cmd_buf         times MAX_CMD db 0

; Shell command history (ring buffer: 8 slots × 128 bytes)
hist_enabled    db 0
hist_count      db 0
hist_head       db 0
hist_view       db 0
hist_buf        times (8 * MAX_CMD) db 0

; Editor state
ed_line         dw 0
ed_col          dw 0
ed_top          dw 0
ed_lines        dw 1
ed_tmp_row      db 0
ed_exit_run     db 0
ed_mode         db 0         ; 0=normal  1=kernel editor  2=Tommy's C IDE
ed_footer_ptr   dw str_ed_keys
ed_buf          times (MAX_ED_LINES * ED_LINE_LEN) db 0
                times 76 db 0           ; pad so 23 sector save/load stays in-bounds

; Tommy's C interpreter state
tc_pc           dw 0
tc_bp           dw 0
tc_stop_flag    db 0
tc_name_buf     times 10 db 0
tc_str_buf      times 96 db 0
tc_var_names    times (16*9) db 0
tc_var_vals     times 16 dw 0
tc_blk_stack    times (16*5) db 0

; File DAP — 23 sectors at LBA 65, buffer = ed_buf
file_dap:
                db 0x10
                db 0
                dw 23
                dw ed_buf
file_dap_seg    dw 0
                dd 65
                dd 0

; Kernel editor DAP — 22 sectors from LBA 1 (the running kernel)
kedit_dap:
                db 0x10
                db 0
                dw 22
                dw ed_buf
kedit_dap_seg   dw 0
                dd 1
                dd 0

; Terminal scrollback ring buffer (SCRL_MAX lines × 160 bytes = 1600 bytes)
scrl_n          dw 0           ; lines stored in ring (0..SCRL_MAX)
scrl_head       dw 0           ; next-write index (0..SCRL_MAX-1)
scrl_off        dw 0           ; lines scrolled back from newest
scrl_mode       db 0           ; 0=normal  1=scroll view active
scrl_buf        times (SCRL_MAX * SCREEN_W * 2) db 0
; Screen save area for scroll mode (rows 5..22 = 18 rows × 160 bytes = 2880 bytes)
scrl_save       times (18 * SCREEN_W * 2) db 0

; Graphics-mode state
gfx_x           dw 0
gfx_y           dw 0
gfx_dx          dw 0
gfx_dy          dw 0
gfx_col         db 0x0A
clk_buf         times 9  db 0

; Mouse state
ms_ready        db 0
ms_x            dw 160
ms_y            dw 100
ms_btn          db 0
ms_pkt          times 3 db 0
ms_pkt_idx      db 0
ms_saved        db 0
ms_saved_x      dw 0
ms_saved_y      dw 0
ms_bg           times 64 db 0
ms_lbtn_prev    db 0
ms_rbtn_prev    db 0

; Mouse cursor sprite 8x8: 0=transparent, 1=black border, 2=white fill
ms_sprite:
    db 1,0,0,0,0,0,0,0
    db 1,1,0,0,0,0,0,0
    db 1,2,1,0,0,0,0,0
    db 1,2,2,1,0,0,0,0
    db 1,2,2,2,1,0,0,0
    db 1,2,2,2,2,1,0,0
    db 1,2,2,1,1,1,1,0
    db 1,1,0,1,2,2,1,0

; CPU info
cpu_vendor      times 16 db 0
cpu_sig         dd 0

; Calc state
calc_a          dw 0
calc_b          dw 0
calc_op         db 0

; Snake state
snk_body        times (SNAKE_MAX*2) db 0
snk_len         dw 0
snk_head        dw 0
snk_dir         dw 0
snk_score       dw 0
snk_fx          db 0
snk_fy          db 0
snk_nx          db 0
snk_ny          db 0

; Starfield state (x.w, y.w, z.w)
sf_stars        times (STAR_COUNT*6) db 0

; Tab completion state
tab_count       dw 0
tab_match_ptr   dw 0
rename_buf      times 16 db 0

; ----- TommyFS state -----
align 2
fs_ok            db 0
fs_used          dw 0
fs_total_bytes   dw 0
cat_size         dw 0
write_size       dw 0
arg_name         times 32 db 0
clk_row          db 0
align 2
fs_disk_buf      times 512 db 0
fs_dir_buf       times 512 db 0

; FS DAP (separate from the cfg dap so we don't clobber state)
fs_dap:
                 db 0x10
                 db 0
fs_dap_count     dw 1
fs_dap_off       dw 0
fs_dap_seg       dw 0
fs_dap_lba       dd 0
                 dd 0

; ----- Tic-tac-toe state -----
ttt_cells        times 9 db ' '
ttt_turn         db 'X'

; Sysinfo / cpuid / calc strings
str_si_hdr      db '  === System Information ===', 0
str_si_ram      db '  Conventional RAM:', 0
str_si_kb       db ' KB', 0
str_si_eq       db '  Equipment flags:', 0
str_si_drv      db '  Boot drive:', 0
str_si_vid      db '  Video mode:', 0

str_cp_hdr      db '  === CPU Information ===', 0
str_cp_vendor   db '  Vendor:', 0
str_cp_sig      db '  Sig:', 0

str_calc_badop  db '  unknown operator. use + - * /', 0
str_calc_div0   db '  divide by zero', 0
str_calc_eq     db '  = ', 0

; Snake strings
snk_title       db 'TOMMY SNAKE'                       ; cx=16 (padding)
                db '     '
snk_hint        db 'Arrows=move  ESC=quit'             ; cx=28 padded
                db '       '
snk_over        db 'GAME OVER'                         ; cx=9
snk_press       db 'press any key...'                  ; cx=18 padded
                db '  '
snk_scorelbl    db 'SCORE: '                           ; cx=7

; Starfield strings
sf_hint         db 'ESC = back to menu'                ; cx=18

; Graphics menu 5/6 already defined above (gfx_menu5/6)

; ============================================================
; STRINGS
; ============================================================
str_title       db "Tommy OS v2.0  -  x86 Assembly  -  type 'help'", 0
str_title_r     db 'gfx  edit  about', 0
str_status      db ' Tommy OS  |  help=commands  edit=editor  gfx=graphics  about=info', 0

str_welcome_big db 'Tommy OS - First Boot Setup', 0
str_welcome_sub db 'A small x86 16-bit assembly operating system.', 0

str_ask_name    db 'Your name:              ---->', 0
str_ask_pass    db 'Choose a password:      ---->', 0
str_pass_set    db '[ password set ]', 0
str_ask_drive   db 'Install to drive #:     ---->', 0
str_confirm     db 'Save settings? (Y/N): ', 0
str_drives_hdr  db 'Detected drives (pick the one with the right size):', 0
str_drive_line  db '  - drive ', 0
str_drv_pre     db '  drive', 0
str_drv_fdd     db 'floppy ', 0
str_drv_hdd     db 'disk   ', 0
str_drv_mb      db ' MB', 0
str_drv_unknown db '   ?  ', 0

str_install_ok  db 'Setup complete. Welcome.', 0
str_press_enter db 'Press ENTER to continue . . .', 0

str_no_wifi     db '[ standalone build - no network ]', 0
str_welcome_back db 'Signed in as ', 0
str_login_user  db 'Username:  ', 0
str_login_pass  db 'Password:  ', 0
str_wrong_pass  db 'Wrong password. Press ENTER to try again.', 0

str_logo1       db '   T O M M Y   O S    v 1.5   ', 0
str_logo2       db '    A small x86 assembly OS    ', 0
str_logo3       db '       16-bit real mode        ', 0
str_logo4       db '===============================', 0

str_shell_greet db '  Tommy OS v2.0  -  type help for commands, Up/Down for history', 0
str_shell_hint  db '  edit  ide  kedit  gfx  snake  ttt  -  Up/Down=history  PgUp/Dn=scroll', 0

str_unknown     db '  unknown command. type help for the list.', 0

str_help_title  db '=== Tommy OS Commands ===', 0
str_help_body   db '  Tip: Up / Down arrows recall previous commands.', 0x0A
                db '  -- Shell --', 0x0A
                db '  help           Show this list', 0x0A
                db '  clear / cls    Clear the screen', 0x0A
                db '  motd           Print the welcome banner', 0x0A
                db '  ver            OS version', 0x0A
                db '  about          About Tommy OS', 0x0A
                db '  echo <text>    Print text', 0x0A
                db '  history (hist) Show command history', 0x0A
                db '  whoami         Show your username', 0x0A
                db '  -- File system (TommyFS) --', 0x0A
                db '  dir            List files on disk', 0x0A
                db '  cat <name>     Print file contents', 0x0A
                db '  write <name>   Save editor buffer as file', 0x0A
                db '  read <name>    Load file into editor buffer', 0x0A
                db '  del <name>     Delete file', 0x0A
                db '  rename <o> <n> Rename file', 0x0A
                db '  hexdump <name> Show file as hex (first 128 bytes)', 0x0A
                db '  df             Show disk usage', 0x0A
                db '  fsinit         Reformat the file system', 0x0A
                db '  -- Apps --', 0x0A
                db '  edit           Open the text editor', 0x0A
                db '  ide            Open Tommy C IDE (green)', 0x0A
                db '  kedit          Kernel binary editor (red)', 0x0A
                db '  gfx            Enter graphics mode (mouse!)', 0x0A
                db '  snake          Play Snake', 0x0A
                db '  ttt            Play Tic-Tac-Toe', 0x0A
                db '  clock          Live updating clock', 0x0A
                db '  calc a + b     Tiny calculator (+ - * /)', 0x0A
                db '  -- System --', 0x0A
                db '  sysinfo        RAM / equipment / video', 0x0A
                db '  cpuid          CPU vendor + features', 0x0A
                db '  mem            Memory map', 0x0A
                db '  asm            Assembly info', 0x0A
                db '  date           Show today date', 0x0A
                db '  time           Show current time', 0x0A
                db '  uptime         BIOS tick count', 0x0A
                db '  random         Random number', 0x0A
                db '  beep           PC speaker beep', 0x0A
                db '  color          Cycle title colors', 0x0A
                db '  reboot         Reboot the machine', 0x0A
                db '  shutdown       Power off (ACPI)', 0x0A
                db '  -- Tommy C --', 0x0A
                db "  manual         Tommy's C language manual", 0x0A
                db "  run / tc       Run the editor buffer as Tommy's C", 0x0A
                db '  save / load    Quick save/load editor buffer', 0x0A, 0

str_ver         db '  Tommy OS v2.0 - x86 16-bit real mode - NASM - written from scratch', 0
str_about       db '  ----------------------------------------', 0x0A
                db '   Tommy OS              version 2.0', 0x0A
                db '   Kernel:  TommyOS 0.2  (x86 real mode)', 0x0A
                db '   Build:   NASM / BIOS / 1.44MB floppy', 0x0A
                db '  ----------------------------------------', 0x0A
                db '   Jesus is king.', 0
str_ls          db '  tommy_os.asm   kernel.asm   boot.asm   shell.asm', 0x0A
                db '  graphics.asm   editor.asm   readme.txt   bible.txt', 0
str_asm         db '  Tommy OS runs in x86 16-bit real mode.', 0x0A
                db '  Write assembly with edit. NASM syntax. Uses BIOS interrupts.', 0
str_mem         db '  0x00000-0x9FFFF  Conventional RAM (640 KB)', 0x0A
                db '  0xA0000-0xBFFFF  VGA memory', 0x0A
                db '  0x08000          Kernel base address', 0x0A
                db '  0x0FFFE          Stack pointer top', 0

str_date_l      db '  Date (Y-M-D): ', 0
str_time_l      db '  Time (H:M:S): ', 0
str_uptime_l    db '  Ticks since midnight: ', 0
str_random_l    db '  Random: ', 0
str_beep_l      db '  *beep*', 0
str_color_l     db '  Title color cycled.', 0

str_ed_title    db ' Tommy OS Editor v2.0  -  ^S=save  ^L=load  ^R=run  ESC=quit', 0
str_ed_keys     db ' ESC:quit  Arrows:nav  Enter:newline  Home/End:edges  ^S/L/R:save/load/run', 0
str_ed_saved    db ' saved to disk', 0
str_ed_loaded   db ' loaded from disk', 0

; Kernel editor strings
str_kd_title    db " Kernel Binary Editor  -  ^S=scratch  ^W=write-to-kernel!  ESC=quit", 0
str_kd_keys     db " ESC:quit  Arrows:nav  ^S=save-scratch  ^W=WRITE-KERNEL(dangerous!)  ^L=load", 0
str_kern_warn   db " Write ed_buf to kernel sectors? THIS OVERWRITES THE OS! (Y/N) ", 0
str_kern_saved  db " kernel sectors written.", 0
str_kern_save_err db " kernel write FAILED (disk error).", 0
str_kern_load_err db "  kernel load failed (disk error).", 0

; Tommy's C IDE strings
str_ide_title   db " Tommy's C IDE v2.0  -  ^S=save  ^L=load  ^R=run  ESC=quit", 0
str_ide_keys    db " say ask let add take times divide if repeat end stop  |  ^S/L/R=save/load/run", 0

; Scroll hint
str_scrl_hint   db " SCROLL MODE  -  PgUp=back  PgDn=forward  (any key = resume typing)", 0

; Graphics-mode menu strings  (byte counts must match cx values)
gfx_title       db 'TOMMY OS  GRAPHICS MODE'            ; cx=23
gfx_subtitle    db '320 x 200  -  256 colors'           ; cx=24
gfx_menu1       db '1  PAINT      mouse / arrows'       ; cx=28
gfx_menu2       db '2  BALL       bouncing demo'        ; cx=27
gfx_menu3       db '3  PALETTE    256 colors'           ; cx=24
gfx_menu4       db '4  CLOCK      live BIOS time'       ; cx=28
gfx_menu5       db '5  SNAKE      classic game'         ; cx=27
gfx_menu6       db '6  STARS      starfield demo'       ; cx=28
gfx_esc         db 'ESC = shell    click or 1-6'        ; cx=27
gfx_paint_hint  db 'arrows=draw  c=clear  ESC=back'     ; cx=30
gfx_ball_hint   db 'ESC=back to menu'                   ; cx=16
gfx_pal_hint    db 'ESC=back to menu'                   ; cx=16
gfx_clk_label   db 'TIME:'                              ; cx=5
gfx_clk_hint    db 'ESC=back to menu'                   ; cx=16

; Command tokens
s_help          db 'help', 0
s_clear         db 'clear', 0
s_cls           db 'cls', 0
s_ver           db 'ver', 0
s_about         db 'about', 0
s_whoami        db 'whoami', 0
s_echo          db 'echo', 0
s_ls            db 'ls', 0
s_edit          db 'edit', 0
s_asm           db 'asm', 0
s_mem           db 'mem', 0
s_gfx           db 'gfx', 0
s_graphics      db 'graphics', 0
s_date          db 'date', 0
s_time          db 'time', 0
s_uptime        db 'uptime', 0
s_random        db 'random', 0
s_beep          db 'beep', 0
s_color         db 'color', 0
s_sysinfo       db 'sysinfo', 0
s_cpuid         db 'cpuid', 0
s_calc          db 'calc', 0
s_snake         db 'snake', 0
s_reboot        db 'reboot', 0
s_shutdown      db 'shutdown', 0
s_run           db 'run', 0
s_tc            db 'tc', 0
s_manual        db 'manual', 0
s_save          db 'save', 0
s_load          db 'load', 0

; ----- New v1.3 command tokens -----
s_dir           db 'dir', 0
s_cat           db 'cat', 0
s_del           db 'del', 0
s_write         db 'write', 0
s_read          db 'read', 0
s_df            db 'df', 0
s_fsinit        db 'fsinit', 0
s_hist          db 'history', 0
s_hist2         db 'hist', 0
s_clock         db 'clock', 0
s_hex           db 'hexdump', 0
s_ttt           db 'ttt', 0
s_tictactoe     db 'tictactoe', 0
s_motd          db 'motd', 0
s_rename        db 'rename', 0

; ----- New v2.0 command tokens -----
s_kedit         db 'kedit', 0
s_ide           db 'ide', 0

; Tommy's C keywords
tc_kw_say       db 'say', 0
tc_kw_ask       db 'ask', 0
tc_kw_let       db 'let', 0
tc_kw_add       db 'add', 0
tc_kw_take      db 'take', 0
tc_kw_times     db 'times', 0
tc_kw_divide    db 'divide', 0
tc_kw_modulo    db 'modulo', 0
tc_kw_if        db 'if', 0
tc_kw_repeat    db 'repeat', 0
tc_kw_end       db 'end', 0
tc_kw_stop      db 'stop', 0
tc_kw_be        db 'be', 0
tc_kw_to        db 'to', 0
tc_kw_from      db 'from', 0
tc_kw_by        db 'by', 0
tc_kw_is        db 'is', 0
tc_kw_not       db 'not', 0

str_tc_hdr      db "  Tommy's C  -  running your program  (any key when done)", 0
str_tc_done     db '  -- program done -- press any key --', 0
str_tc_err      db '  ? I do not understand that line', 0
str_tc_prompt   db '  ? ', 0
str_tc_save_ok  db '  saved to disk.', 0
str_tc_save_err db '  save failed (no writable disk?).', 0
str_tc_load_ok  db '  loaded from disk.', 0
str_tc_load_err db '  load failed (no saved program?).', 0

str_manual      db "  === Tommy's C  -  Language Manual ===", 0x0A
                db '  Tommy C reads like English. One statement per line.', 0x0A
                db ' ', 0x0A
                db '  ---- Quick start ----', 0x0A
                db '    edit       open the editor and write your program', 0x0A
                db '    Ctrl-S     save your program (from inside the editor)', 0x0A
                db '    Ctrl-L     load your last saved program', 0x0A
                db '    Ctrl-R     save and run -- skips going back to shell', 0x0A
                db '    ESC        leave the editor (returns to shell)', 0x0A
                db ' ', 0x0A
                db '  ---- Shell commands ----', 0x0A
                db '    edit       open the editor', 0x0A
                db '    run / tc   run the editor buffer right now', 0x0A
                db '    save       save the editor buffer to disk', 0x0A
                db '    load       load the saved buffer from disk', 0x0A
                db '    write foo  save buffer as named file "foo" (TommyFS)', 0x0A
                db '    read  foo  load named file "foo" into the buffer', 0x0A
                db '    dir        list saved files', 0x0A
                db '    manual     show this page again', 0x0A
                db ' ', 0x0A
                db '  ---- Statements ----', 0x0A
                db '    say "hello"        print text (use \" for a quote)', 0x0A
                db '    say x              print a variable as a number', 0x0A
                db '    ask x              read a number from the user', 0x0A
                db '    let x be 5         create or set a variable', 0x0A
                db '    let y be x         copy one variable to another', 0x0A
                db '    add 3 to x         x = x + 3   (also: add y to x)', 0x0A
                db '    take 2 from x      x = x - 2', 0x0A
                db '    times 4 by x       x = x * 4', 0x0A
                db '    divide 4 by x      x = x / 4', 0x0A
                db '    modulo 4 by x      x = x mod 4', 0x0A
                db '    if x is 5          start a block if x equals 5', 0x0A
                db '    if x is not 0      start a block if x is not 0', 0x0A
                db '    repeat 5           run the block 5 times', 0x0A
                db '    repeat n           variables work here too', 0x0A
                db '    end                close an if or repeat block', 0x0A
                db '    stop               stop the program', 0x0A
                db '    ; a note           a comment line (ignored)', 0x0A
                db ' ', 0x0A
                db '  ---- Rules ----', 0x0A
                db '    - Variable names are letters only (x, age, total).', 0x0A
                db '    - Numbers fit in 16 bits (0 to 65535 unsigned).', 0x0A
                db '    - Anywhere you can write a number you can use a', 0x0A
                db '      variable instead.', 0x0A
                db '    - Indentation is for you, not the computer.', 0x0A
                db ' ', 0x0A
                db '  ---- Example: countdown ----', 0x0A
                db '    let n be 5', 0x0A
                db '    repeat n', 0x0A
                db '      say n', 0x0A
                db '      take 1 from n', 0x0A
                db '    end', 0x0A
                db '    say "blast off!"', 0x0A
                db '    stop', 0x0A
                db ' ', 0x0A
                db '  ---- Example: guess my number ----', 0x0A
                db '    let secret be 7', 0x0A
                db '    say "guess a number:"', 0x0A
                db '    ask guess', 0x0A
                db '    if guess is secret', 0x0A
                db '      say "right!"', 0x0A
                db '    end', 0x0A
                db '    if guess is not secret', 0x0A
                db '      say "nope, it was:"', 0x0A
                db '      say secret', 0x0A
                db '    end', 0x0A
                db '    stop', 0

; ----- TommyFS / new-command strings -----
str_fs_err       db '  filesystem error.', 0
str_fs_nf        db '  file not found.', 0
str_fs_full      db '  filesystem full (16 files max).', 0
str_fs_init_q    db '  Format filesystem? all files lost (Y/N) ', 0
str_fs_cancel    db '  cancelled.', 0
str_fs_formatted db '  filesystem formatted.', 0

str_dir_hdr      db '  === Files on disk ===', 0
str_dir_empty    db '  (no files)', 0
str_dir_used     db '  Used:', 0
str_dir_of       db ' of ', 0
str_dir_files    db ' slots used', 0
str_dir_bytes    db ' bytes', 0

str_cat_usage    db '  usage: cat <name>', 0
str_cat_empty    db '  (file is empty)', 0
str_del_usage    db '  usage: del <name>', 0
str_del_ok       db '  deleted.', 0
str_write_usage  db '  usage: write <name>', 0
str_write_ok     db '  written.', 0
str_read_usage   db '  usage: read <name>', 0
str_read_ok      db '  loaded into editor buffer.', 0

str_df_hdr       db '  === Disk usage ===', 0
str_df_files     db '  Files used:', 0
str_df_used      db '  Bytes used:', 0
str_df_slot      db '  Slot size:', 0

str_hex_usage    db '  usage: hexdump <name>', 0
str_rename_ok    db '  renamed.', 0
str_rename_usage db '  usage: rename <old> <new>', 0

str_hist_hdr     db '  === Command history ===', 0
str_hist_empty   db '  (no commands yet)', 0

str_clock_hint   db '  live clock (press ESC to exit)', 0

str_ttt_hdr      db '  === Tic Tac Toe === (you are X, type 1-9 or ESC)', 0
str_ttt_sep      db '  --+---+--', 0
str_ttt_prompt   db '  your move? ', 0
str_ttt_won      db '  YOU WIN!  praise Jesus.', 0
str_ttt_lost     db '  you lost! the computer wins.', 0
str_ttt_draw     db '  draw game!', 0

str_motd         db '   _____                                ___  ____', 0x0A
                 db '  |_   _|__  _ __ ___  _ __ ___  _   _ / _ \/ ___|', 0x0A
                 db '    | |/ _ \| `_ ` _ \| `_ ` _ \| | | | | | \___ \', 0x0A
                 db '    | | (_) | | | | | | | | | | | |_| | |_| |___) |', 0x0A
                 db '    |_|\___/|_| |_| |_|_| |_| |_|\__, |\___/|____/', 0x0A
                 db '                                 |___/', 0x0A
                 db '   Tommy OS  v2.0  - your own little x86 world.', 0

; Tab completion command list (alphabetical, double-null terminated)
tab_list:
    db 'about',0
    db 'asm',0
    db 'beep',0
    db 'calc',0
    db 'cat',0
    db 'clear',0
    db 'cls',0
    db 'clock',0
    db 'color',0
    db 'cpuid',0
    db 'date',0
    db 'df',0
    db 'del',0
    db 'dir',0
    db 'echo',0
    db 'edit',0
    db 'fsinit',0
    db 'gfx',0
    db 'ide',0
    db 'graphics',0
    db 'help',0
    db 'hexdump',0
    db 'hist',0
    db 'history',0
    db 'kedit',0
    db 'load',0
    db 'ls',0
    db 'manual',0
    db 'mem',0
    db 'motd',0
    db 'random',0
    db 'read',0
    db 'reboot',0
    db 'rename',0
    db 'run',0
    db 'save',0
    db 'shutdown',0
    db 'snake',0
    db 'sysinfo',0
    db 'tc',0
    db 'time',0
    db 'tictactoe',0
    db 'ttt',0
    db 'uptime',0
    db 'ver',0
    db 'whoami',0
    db 'write',0
    db 0                    ; end sentinel

; Mutable state for color command
title_color     db COL_TITLE

; 512-byte sector buffer for disk config persistence (LBA 64)
align 2
cfg_disk_buf    times 512 db 0

; ============================================================
; DESKTOP MAIN  (v2 top-level — replaces shell_main as the root)
; ============================================================
desktop_main:
    mov byte [desk_state], DS_DESKTOP
    call gfx_desktop_main
    ; gfx_desktop_main loops forever; falls through only on system halt
    ret

; ============================================================
; DESKTOP DRAW FULL — redraws entire desktop chrome + wallpaper
; ============================================================
desktop_draw_full:
    ret

; ============================================================
; DESKTOP BACKGROUND (rows 1-22): dark blue wallpaper
; ============================================================
draw_desktop_bg:
    push es
    push ax
    push cx
    push di

    mov ax, VGA_MEM
    mov es, ax
    mov di, 1 * SCREEN_W * 2   ; row 1
    mov cx, 22 * SCREEN_W       ; rows 1-22
    mov ax, (COL_DESK << 8) | 0x20
.bg_fill:
    stosw
    loop .bg_fill

    pop di
    pop cx
    pop ax
    pop es
    ret

; ============================================================
; DESKTOP ICONS (upper-right corner, macOS Finder style)
; ============================================================
draw_desktop_icons:
    ret

; ============================================================
; DESKTOP HINT — centre-screen prompt
; ============================================================
draw_desktop_hint:
    ret

; ============================================================
; WINDOW TITLE BAR (row 1) — Terminal style
; ============================================================
draw_win_titlebar:
; Row 1: [traffic lights] [title text] all on COL_WIN_TERM background
    push es
    push ax
    push cx
    push di

    ; Fill row 1 with blue window title bar colour
    mov ax, VGA_MEM
    mov es, ax
    mov di, 1 * SCREEN_W * 2
    mov cx, SCREEN_W
    mov ax, (COL_WIN_TERM << 8) | 0x20
.wt_fill:
    stosw
    loop .wt_fill

    pop di
    pop cx
    pop ax
    pop es

    ; Traffic lights: 2-char wide solid colour blocks at cols 2,5,8
    ; Red close
    mov dh, WIN_TITLE_ROW
    mov dl, 2
    mov bl, COL_TL_RED
    mov al, 0xDB            ; full block █
    call print_char_vga
    mov dl, 3
    call print_char_vga

    ; Yellow minimise
    mov dl, 5
    mov bl, COL_TL_YEL
    call print_char_vga
    mov dl, 6
    call print_char_vga

    ; Green maximise
    mov dl, 8
    mov bl, COL_TL_GRN
    call print_char_vga
    mov dl, 9
    call print_char_vga

    ; App title text
    mov dh, WIN_TITLE_ROW
    mov dl, 12
    mov bl, COL_WIN_TERM
    mov si, str_wt_terminal
    call print_at
    ret

; ============================================================
; WINDOW TITLE BAR (row 1) — Editor style (green)
; ============================================================
draw_win_titlebar_editor:
    push es
    push ax
    push cx
    push di

    mov ax, VGA_MEM
    mov es, ax
    mov di, 1 * SCREEN_W * 2
    mov cx, SCREEN_W
    mov ax, (COL_WIN_EDIT << 8) | 0x20
.we_fill:
    stosw
    loop .we_fill

    pop di
    pop cx
    pop ax
    pop es

    ; Traffic lights
    mov dh, WIN_TITLE_ROW
    mov dl, 2
    mov bl, COL_TL_RED
    mov al, 0xDB
    call print_char_vga
    mov dl, 3
    call print_char_vga
    mov dl, 5
    mov bl, COL_TL_YEL
    call print_char_vga
    mov dl, 6
    call print_char_vga
    mov dl, 8
    mov bl, COL_TL_GRN
    call print_char_vga
    mov dl, 9
    call print_char_vga

    mov dh, WIN_TITLE_ROW
    mov dl, 12
    mov bl, COL_WIN_EDIT
    mov si, str_wt_editor
    call print_at
    ret

; ============================================================
; ABOUT DIALOG (v2 style, centred on desktop)
; ============================================================
desktop_show_about:
    call draw_desktop_bg

    ; Draw a centred "window" using box chars
    ; Window: rows 4-19, cols 20-59  (40 wide, 16 tall)
    push es
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, VGA_MEM
    mov es, ax

    ; Fill interior rows 5-18, cols 21-58 with about-window bg (magenta)
    mov dh, 4
    mov dl, 20
    mov cx, 16             ; height
.ab_row:
    push cx
    push dx
    movzx di, dh
    imul di, di, SCREEN_W * 2
    movzx bx, dl
    shl bx, 1
    add di, bx
    mov cx, 40             ; width
    mov ax, (COL_WIN_ABOUT << 8) | 0x20
.ab_col:
    stosw
    loop .ab_col
    pop dx
    pop cx
    inc dh
    loop .ab_row

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop es

    ; Title bar row 4 — traffic lights
    mov dh, 4
    mov dl, 22
    mov bl, COL_TL_RED
    mov al, 0xDB
    call print_char_vga
    mov dl, 23
    call print_char_vga
    mov dl, 25
    mov bl, COL_TL_YEL
    call print_char_vga
    mov dl, 26
    call print_char_vga
    mov dl, 28
    mov bl, COL_TL_GRN
    call print_char_vga
    mov dl, 29
    call print_char_vga

    mov dh, 4
    mov dl, 32
    mov bl, COL_WIN_ABOUT
    mov si, str_wt_about
    call print_at

    ; About content
    mov dh, 6
    mov dl, 24
    mov bl, COL_WIN_ABOUT
    mov si, str_about2_logo
    call print_at

    mov dh, 8
    mov dl, 22
    mov bl, 0xF5
    mov si, str_about2_ver
    call print_at

    mov dh, 10
    mov dl, 22
    mov bl, 0xD5
    mov si, str_about2_line1
    call print_at

    mov dh, 11
    mov dl, 22
    mov bl, 0xD5
    mov si, str_about2_line2
    call print_at

    mov dh, 12
    mov dl, 22
    mov bl, 0xD5
    mov si, str_about2_line3
    call print_at

    mov dh, 14
    mov dl, 22
    mov bl, 0xD5
    mov si, str_about2_jesus
    call print_at

    mov dh, 17
    mov dl, 24
    mov bl, COL_WIN_ABOUT
    mov si, str_about2_close
    call print_at

    ; Wait for any key
    mov ah, 0x00
    int 0x16
    ret

; ============================================================
; GRAPHICAL DESKTOP  —  VGA mode 13h  320x200  256-colour
; ============================================================
; Palette indices 16-31 are reprogrammed by gfx_desk_pal
GC_BGEDGE  equ 16
GC_BGC     equ 23
GC_TOPBAR  equ 24
GC_DOCKBG  equ 25
GC_DOCKBD  equ 26
GC_ICON    equ 27
GC_SPOTBG  equ 29
GC_SPOTTX  equ 30

; ----------------------------------------------------------
gfx_desktop_main:
    mov ax, 0x0013
    int 0x10
    call mouse_init
    call wm_init_vfs
    call gfx_desk_pal
    call gfx_desk_draw
    call mouse_draw_cursor
gfx_dsk_loop:
    call mouse_poll             ; read PS/2 – do NOT restore cursor yet

    ; --- ongoing window drag ---
    cmp byte [wm_drag_wnd], 0xFF
    je .wdl_chk_rsz
    test byte [ms_btn], 0x01
    jz .wdl_end_drag
    call wm_do_drag             ; only sets dirty when pos changes
    jmp .wdl_aft
.wdl_end_drag:
    mov byte [wm_drag_wnd], 0xFF
    mov byte [wm_dirty], 1
    jmp .wdl_aft

    ; --- ongoing resize ---
.wdl_chk_rsz:
    cmp byte [wm_rsz_wnd], 0xFF
    je .wdl_newclk
    test byte [ms_btn], 0x01
    jz .wdl_end_rsz
    call wm_do_resize           ; only sets dirty when size changes
    jmp .wdl_aft
.wdl_end_rsz:
    mov byte [wm_rsz_wnd], 0xFF
    mov byte [wm_dirty], 1
    jmp .wdl_aft

    ; --- new click ---
.wdl_newclk:
    test byte [ms_btn], 0x01
    jz .wdl_btnup
    cmp byte [ms_lbtn_prev], 1
    je .wdl_aft
    mov ax, [ms_x]
    mov bx, [ms_y]
    call wm_hit_test
    test ah, ah
    jnz .wdl_hitwin
    call wm_dock_click
    jmp .wdl_aft
.wdl_hitwin:
    call wm_process_click
    jmp .wdl_aft
.wdl_btnup:
    mov byte [ms_lbtn_prev], 0
.wdl_aft:
    test byte [ms_btn], 0x01
    jz .wdl_clk
    mov byte [ms_lbtn_prev], 1
.wdl_clk:
    call gfx_desk_clk

    ; --- cursor/dirty update: ONLY when something changed ---
    mov ax, [ms_x]
    mov bx, [ms_y]
    cmp byte [wm_dirty], 0
    jne .wdl_do_upd
    cmp ax, [wm_last_ms_x]
    jne .wdl_do_upd
    cmp bx, [wm_last_ms_y]
    je .wdl_no_upd
.wdl_do_upd:
    call mouse_restore_bg       ; erase cursor before any VGA write
    mov [wm_last_ms_x], ax
    mov [wm_last_ms_y], bx
    cmp byte [wm_dirty], 0
    je .wdl_skip_rd
    mov byte [wm_dirty], 0
    call gfx_desk_draw
    call wm_draw_all
.wdl_skip_rd:
    call mouse_draw_cursor
.wdl_no_upd:

    ; --- keyboard ---
    mov ah, 0x01
    int 0x16
    jz gfx_dsk_loop
    mov ah, 0x00
    int 0x16
    cmp byte [wm_focus_wnd], 0xFF
    je .wdl_glbl
    call wm_key_dispatch
    jmp gfx_dsk_loop
.wdl_glbl:
    cmp al, 0x1B
    je gfx_dsk_loop
    cmp al, 0x20
    jb gfx_dsk_loop
    call mouse_restore_bg
    call gfx_spotlight
    mov byte [wm_dirty], 1
    jmp gfx_dsk_loop

; --- gd_2text: enter text mode for an app ---
gd_2text:
    push ax
    push bx
    mov ax, 0x0003
    int 0x10
    mov ax, 0x1003
    xor bx, bx
    int 0x10
    pop bx
    pop ax
    ret

; --- gd_2gfx: restore graphics desktop after app exits ---
gd_2gfx:
    push ax
    push bx
    mov byte [desk_state], DS_DESKTOP
    mov ax, 0x0013
    int 0x10
    call gfx_desk_pal
    call gfx_desk_draw
    call mouse_draw_cursor
    pop bx
    pop ax
    ret

;=======================================================
; WINDOW MANAGER  v2.02
;=======================================================
WND_SIZE  equ 24
MAX_WNDS  equ 3
WF_OPEN   equ 0x01
WF_MAX    equ 0x02
WT_FILES  equ 1
WT_EDIT   equ 2
WT_STORE  equ 3
WT_CODE   equ 4
WTB_H     equ 11
WMW_MIN_W equ 90
WMW_MIN_H equ 50
WH_TITLE  equ 1
WH_CLOSE  equ 2
WH_MAX    equ 3
WH_RESIZE equ 4
WH_CONT   equ 5
VFS_MAX   equ 3
VFS_NLEN  equ 14
VFS_BSIZ  equ 350

; --- wm_dock_click: handle dock clicks in windowed mode ---
wm_dock_click:
    pusha
    mov ax, [ms_x]
    mov bx, [ms_y]
    cmp bx, 148
    jl .wdc_ret
    cmp bx, 192
    jg .wdc_ret
    ; Folder x=68..108 -> File Manager
    cmp ax, 68
    jl .wdc_doc
    cmp ax, 108
    jg .wdc_doc
    mov al, WT_FILES
    mov ah, 0
    call wm_open_wnd
    jmp .wdc_ret
.wdc_doc:
    ; Doc x=116..156 -> Text Editor
    cmp ax, 116
    jl .wdc_code
    cmp ax, 156
    jg .wdc_code
    mov al, WT_EDIT
    mov ah, 0xFF
    call wm_open_wnd
    jmp .wdc_ret
.wdc_code:
    ; Code x=164..204 -> Tommy's C Editor
    cmp ax, 164
    jl .wdc_store
    cmp ax, 204
    jg .wdc_store
    mov al, WT_CODE
    mov ah, 0xFF
    call wm_open_wnd
    jmp .wdc_ret
.wdc_store:
    ; Store x=212..252 -> App Store
    cmp ax, 212
    jl .wdc_ret
    cmp ax, 252
    jg .wdc_ret
    mov al, WT_STORE
    mov ah, 0
    call wm_open_wnd
.wdc_ret:
    popa
    ret

; --- wm_open_wnd: AL=type  AH=file_idx (0xFF=auto-alloc) ---
wm_open_wnd:
    pusha
    mov cl, al          ; CL = type
    mov ch, ah          ; CH = file idx hint
    ; find free window slot
    xor bx, bx
.wop_l:
    cmp bx, MAX_WNDS
    jae .wop_done
    mov di, bx
    imul di, di, WND_SIZE
    add di, windows
    test byte [di+17], WF_OPEN
    jz .wop_got
    inc bx
    jmp .wop_l
.wop_got:
    ; stagger position: x=10+bx*14, y=18+bx*14
    mov ax, bx
    imul ax, ax, 14
    add ax, 10
    mov [di+0], ax
    mov ax, bx
    imul ax, ax, 14
    add ax, 18
    mov [di+2], ax
    cmp cl, WT_FILES
    je .wop_files
    cmp cl, WT_STORE
    je .wop_store
    cmp cl, WT_CODE
    je .wop_code
    ; WT_EDIT (fallthrough)
    mov word [di+4], 200
    mov word [di+6], 110
    mov word [di+18], wm_str_edit
    ; assign VFS file index
    cmp ch, 0xFF
    jne .wop_use_fi
    movzx ax, byte [wm_next_file]
    mov [di+20], ax
    inc byte [wm_next_file]
    mov al, [wm_next_file]
    cmp al, VFS_MAX
    jb .wop_geom
    mov byte [wm_next_file], 0
    jmp .wop_geom
.wop_use_fi:
    movzx ax, ch
    mov [di+20], ax
    jmp .wop_geom
.wop_store:
    mov word [di+4], 200
    mov word [di+6], 120
    mov word [di+18], wm_str_store
    mov word [di+20], 0
    jmp .wop_geom
.wop_code:
    mov word [di+4], 200
    mov word [di+6], 130
    mov word [di+18], wm_str_code
    movzx ax, byte [wm_next_file]
    mov [di+20], ax
    inc byte [wm_next_file]
    mov al, [wm_next_file]
    cmp al, VFS_MAX
    jb .wop_geom
    mov byte [wm_next_file], 0
    jmp .wop_geom
.wop_files:
    mov word [di+4], 180
    mov word [di+6], 110
    mov word [di+18], wm_str_files
    mov word [di+20], 0
.wop_geom:
    ; save restore coords (fields 8-15 = saved x,y,w,h)
    mov ax, [di+0]
    mov [di+8], ax
    mov ax, [di+2]
    mov [di+10], ax
    mov ax, [di+4]
    mov [di+12], ax
    mov ax, [di+6]
    mov [di+14], ax
    mov [di+16], cl     ; type
    mov byte [di+17], WF_OPEN
    mov [wm_focus_wnd], bl
    mov byte [wm_dirty], 1
.wop_done:
    popa
    ret

; --- wm_close_wnd: BL=window index ---
wm_close_wnd:
    pusha
    cmp bl, MAX_WNDS
    jae .wcl_done
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    mov byte [di+17], 0
    ; update focus
    movzx ax, byte [wm_focus_wnd]
    cmp al, bl
    jne .wcl_done
    mov byte [wm_focus_wnd], 0xFF
    xor cx, cx
.wcl_fl:
    cmp cx, MAX_WNDS
    jae .wcl_done
    movzx si, cl
    imul si, si, WND_SIZE
    add si, windows
    test byte [si+17], WF_OPEN
    jz .wcl_fnx
    mov [wm_focus_wnd], cl
    jmp .wcl_done
.wcl_fnx:
    inc cx
    jmp .wcl_fl
.wcl_done:
    mov byte [wm_dirty], 1
    popa
    ret

; --- wm_toggle_max: BL=window index ---
wm_toggle_max:
    pusha
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    test byte [di+17], WF_MAX
    jnz .wtm_restore
    ; save current, go fullscreen desktop area
    mov ax, [di+0]
    mov [di+8], ax
    mov ax, [di+2]
    mov [di+10], ax
    mov ax, [di+4]
    mov [di+12], ax
    mov ax, [di+6]
    mov [di+14], ax
    mov word [di+0], 0
    mov word [di+2], 15
    mov word [di+4], 320
    mov word [di+6], 133
    or byte [di+17], WF_MAX
    jmp .wtm_done
.wtm_restore:
    mov ax, [di+8]
    mov [di+0], ax
    mov ax, [di+10]
    mov [di+2], ax
    mov ax, [di+12]
    mov [di+4], ax
    mov ax, [di+14]
    mov [di+6], ax
    and byte [di+17], ~WF_MAX
.wtm_done:
    mov byte [wm_dirty], 1
    popa
    ret

; --- wm_hit_test: AX=x BX=y  ->  AH=area AL=wndidx (0xFF=none) ---
; Tests highest index first (topmost window).
wm_hit_test:
    push cx
    push dx
    push si
    push di
    mov cx, MAX_WNDS - 1
.wht_l:
    movzx di, cl
    imul di, di, WND_SIZE
    add di, windows
    test byte [di+17], WF_OPEN
    jz .wht_next
    ; bounding box check
    mov si, [di+0]          ; wx
    cmp ax, si
    jl .wht_next
    mov dx, [di+4]
    add dx, si
    cmp ax, dx
    jg .wht_next
    mov si, [di+2]          ; wy
    cmp bx, si
    jl .wht_next
    mov dx, [di+6]
    add dx, si
    cmp bx, dx
    jg .wht_next
    ; inside - check close button (wx+ww-10 .. wx+ww-2,  wy+2..wy+10)
    mov dx, [di+0]
    add dx, [di+4]
    sub dx, 10
    cmp ax, dx
    jl .wht_chk_max
    mov dx, [di+2]
    add dx, 2
    cmp bx, dx
    jl .wht_chk_title
    add dx, 8
    cmp bx, dx
    jg .wht_chk_title
    mov ah, WH_CLOSE
    mov al, cl
    jmp .wht_ret
.wht_chk_max:
    ; max button: wx+ww-20 .. wx+ww-12,  wy+2..wy+10
    mov dx, [di+0]
    add dx, [di+4]
    sub dx, 20
    cmp ax, dx
    jl .wht_chk_title
    add dx, 8
    cmp ax, dx
    jg .wht_chk_title
    mov dx, [di+2]
    add dx, 2
    cmp bx, dx
    jl .wht_chk_title
    add dx, 8
    cmp bx, dx
    jg .wht_chk_title
    mov ah, WH_MAX
    mov al, cl
    jmp .wht_ret
.wht_chk_title:
    mov dx, [di+2]
    add dx, WTB_H
    cmp bx, dx
    jg .wht_chk_resize
    mov ah, WH_TITLE
    mov al, cl
    jmp .wht_ret
.wht_chk_resize:
    ; resize handle: bottom-right 10x10
    mov dx, [di+0]
    add dx, [di+4]
    sub dx, 10
    cmp ax, dx
    jl .wht_cont
    mov dx, [di+2]
    add dx, [di+6]
    sub dx, 10
    cmp bx, dx
    jl .wht_cont
    mov ah, WH_RESIZE
    mov al, cl
    jmp .wht_ret
.wht_cont:
    mov ah, WH_CONT
    mov al, cl
    jmp .wht_ret
.wht_next:
    test cx, cx
    jz .wht_miss
    dec cx
    jmp .wht_l
.wht_miss:
    xor ah, ah
    mov al, 0xFF
.wht_ret:
    pop di
    pop si
    pop dx
    pop cx
    ret

; --- wm_process_click: AH=area AL=wndidx ---
wm_process_click:
    pusha
    mov bl, al
    mov [wm_focus_wnd], bl
    mov byte [wm_dirty], 1
    cmp ah, WH_CLOSE
    je .wpc_close
    cmp ah, WH_MAX
    je .wpc_max
    cmp ah, WH_TITLE
    je .wpc_drag
    cmp ah, WH_RESIZE
    je .wpc_resize
    ; WH_CONT
    call wm_cont_click
    jmp .wpc_done
.wpc_close:
    call wm_close_wnd
    jmp .wpc_done
.wpc_max:
    call wm_toggle_max
    jmp .wpc_done
.wpc_drag:
    mov [wm_drag_wnd], bl
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    mov ax, [ms_x]
    sub ax, [di+0]
    mov [wm_drag_ox], ax
    mov ax, [ms_y]
    sub ax, [di+2]
    mov [wm_drag_oy], ax
    jmp .wpc_done
.wpc_resize:
    mov [wm_rsz_wnd], bl
.wpc_done:
    popa
    ret

; --- wm_do_drag: move dragging window to follow mouse ---
wm_do_drag:
    pusha
    movzx bx, byte [wm_drag_wnd]
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    ; new_x = ms_x - drag_ox, clamped 0..(319-w)
    mov ax, [ms_x]
    sub ax, [wm_drag_ox]
    cmp ax, 0
    jge .wdd_xok
    xor ax, ax
.wdd_xok:
    mov cx, 319
    sub cx, [di+4]
    cmp ax, cx
    jle .wdd_xfin
    mov ax, cx
.wdd_xfin:
    cmp ax, [di+0]
    je .wdd_chy
    mov [di+0], ax
    mov byte [wm_dirty], 1
.wdd_chy:
    ; new_y = ms_y - drag_oy, clamped 15..(147-h)
    mov ax, [ms_y]
    sub ax, [wm_drag_oy]
    cmp ax, 15
    jge .wdd_yok
    mov ax, 15
.wdd_yok:
    mov cx, 147
    sub cx, [di+6]
    cmp ax, cx
    jle .wdd_yfin
    mov ax, cx
.wdd_yfin:
    cmp ax, [di+2]
    je .wdd_done
    mov [di+2], ax
    mov byte [wm_dirty], 1
.wdd_done:
    popa
    ret

; --- wm_do_resize: resize window by dragging bottom-right ---
wm_do_resize:
    pusha
    movzx bx, byte [wm_rsz_wnd]
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    ; new_w = ms_x - wx, clamped WMW_MIN_W..(319-wx)
    mov ax, [ms_x]
    sub ax, [di+0]
    cmp ax, WMW_MIN_W
    jge .wdr_wok
    mov ax, WMW_MIN_W
.wdr_wok:
    mov cx, 319
    sub cx, [di+0]
    cmp ax, cx
    jle .wdr_wfin
    mov ax, cx
.wdr_wfin:
    cmp ax, [di+4]
    je .wdr_chh
    mov [di+4], ax
    mov byte [wm_dirty], 1
.wdr_chh:
    ; new_h = ms_y - wy, clamped WMW_MIN_H..(147-wy)
    mov ax, [ms_y]
    sub ax, [di+2]
    cmp ax, WMW_MIN_H
    jge .wdr_hok
    mov ax, WMW_MIN_H
.wdr_hok:
    mov cx, 147
    sub cx, [di+2]
    cmp ax, cx
    jle .wdr_hfin
    mov ax, cx
.wdr_hfin:
    cmp ax, [di+6]
    je .wdr_done
    mov [di+6], ax
    mov byte [wm_dirty], 1
.wdr_done:
    popa
    ret

; --- wm_draw_all: draw all open windows back-to-front ---
wm_draw_all:
    push cx
    push di
    xor cx, cx
.wda_l:
    cmp cx, MAX_WNDS
    jae .wda_done
    movzx di, cl
    imul di, di, WND_SIZE
    add di, windows
    test byte [di+17], WF_OPEN
    jz .wda_next
    call wm_draw_one
.wda_next:
    inc cx
    jmp .wda_l
.wda_done:
    pop di
    pop cx
    ret

; --- wm_draw_one: DI -> window record ---
wm_draw_one:
    pusha
    ; content background fill
    mov ax, [di+0]
    mov bx, [di+2]
    mov cx, [di+4]
    mov dx, [di+6]
    mov bp, GC_SPOTBG
    call gd_fillrect
    ; border
    mov ax, [di+0]
    mov bx, [di+2]
    mov cx, [di+4]
    mov dx, [di+6]
    mov bp, GC_DOCKBD
    call gfx_box
    ; title bar fill - find this window's index to check focus
    ; compute index: (DI - windows) / WND_SIZE
    mov si, di
    sub si, windows
    xor cx, cx
.wdo_idx:
    cmp cx, MAX_WNDS
    jae .wdo_idx_done
    mov ax, cx
    imul ax, ax, WND_SIZE
    cmp ax, si
    je .wdo_idx_done
    inc cx
    jmp .wdo_idx
.wdo_idx_done:
    ; CX = this window's index
    movzx bp, byte [wm_focus_wnd]
    cmp bp, cx
    je .wdo_active_tb
    mov bp, GC_DOCKBD     ; inactive title bar
    jmp .wdo_tfill
.wdo_active_tb:
    mov bp, GC_TOPBAR     ; active title bar (dark)
.wdo_tfill:
    mov ax, [di+0]
    mov bx, [di+2]
    mov cx, [di+4]
    mov dx, WTB_H
    call gd_fillrect
    ; title text via BIOS: row = (wy+2)/8, col = (wx+3)/8
    mov ax, [di+2]
    add ax, 2
    shr ax, 3
    cmp ax, 24
    jle .wdo_row_ok
    mov ax, 24
.wdo_row_ok:
    mov dh, al
    mov ax, [di+0]
    add ax, 3
    shr ax, 3
    cmp ax, 39
    jle .wdo_col_ok
    mov ax, 39
.wdo_col_ok:
    mov dl, al
    mov ah, 0x02
    xor bh, bh
    int 0x10
    ; write title string with BIOS
    mov si, [di+18]
    ; recompute this window's index from DI
    mov bp, di
    sub bp, windows
    xor cx, cx
.wdo_ci2:
    cmp cx, MAX_WNDS
    jae .wdo_ci2_done
    mov ax, cx
    imul ax, ax, WND_SIZE
    cmp ax, bp
    je .wdo_ci2_done
    inc cx
    jmp .wdo_ci2
.wdo_ci2_done:
    movzx bp, byte [wm_focus_wnd]
    cmp bp, cx
    je .wdo_tactive
    mov bl, GC_ICON     ; inactive: near-white text
    jmp .wdo_twrite
.wdo_tactive:
    mov bl, GC_TOPBAR   ; active: dark text on dark bar? use icon colour
    mov bl, GC_ICON
.wdo_twrite:
.wdo_twl:
    mov al, [si]
    test al, al
    jz .wdo_tdone
    mov ah, 0x09
    xor bh, bh
    mov cx, 1
    int 0x10
    mov ah, 0x03
    xor bh, bh
    int 0x10
    inc dl
    cmp dl, 39
    jl .wdo_tadv
    mov dl, 39
.wdo_tadv:
    mov ah, 0x02
    xor bh, bh
    int 0x10
    inc si
    jmp .wdo_twl
.wdo_tdone:
    ; close button X at (wx+ww-10, wy+2)
    mov ax, [di+0]
    add ax, [di+4]
    sub ax, 10
    shr ax, 3
    mov cl, al          ; col
    mov ax, [di+2]
    add ax, 2
    shr ax, 3
    mov ch, al          ; row
    mov ah, 0x02
    xor bh, bh
    mov dh, ch
    mov dl, cl
    int 0x10
    mov ah, 0x09
    mov al, 'X'
    xor bh, bh
    mov bl, 28
    mov cx, 1
    int 0x10
    ; max button square at (wx+ww-20, wy+2)
    mov ax, [di+0]
    add ax, [di+4]
    sub ax, 20
    shr ax, 3
    mov cl, al
    mov ax, [di+2]
    add ax, 2
    shr ax, 3
    mov ch, al
    mov ah, 0x02
    xor bh, bh
    mov dh, ch
    mov dl, cl
    int 0x10
    mov ah, 0x09
    mov al, 0xFE
    xor bh, bh
    mov bl, GC_DOCKBD
    mov cx, 1
    int 0x10
    ; resize handle: 4x4 dot at bottom-right corner
    mov ax, [di+0]
    add ax, [di+4]
    sub ax, 1           ; right edge x
    push ax             ; save rx
    mov bx, [di+2]
    add bx, [di+6]
    sub bx, 1           ; bottom edge y
    pop cx              ; cx = rx, bx = ry
    ; draw 4 pixels going up-left from corner
    mov dx, bx
    sub dx, 3           ; start row
.wdo_rsz:
    cmp dx, bx
    jg .wdo_rsz_done
    mov ax, cx
    sub ax, 3           ; start col
.wdo_rsz_c:
    cmp ax, cx
    jg .wdo_rsz_next
    push cx
    push bx
    push dx
    mov cx, ax
    mov al, GC_DOCKBD
    call gfx_putpixel
    pop dx
    pop bx
    pop cx
    inc ax
    jmp .wdo_rsz_c
.wdo_rsz_next:
    inc dx
    jmp .wdo_rsz
.wdo_rsz_done:
    ; draw window content
    call wm_draw_content
    popa
    ret

; --- wm_draw_content: DI -> window record ---
wm_draw_content:
    pusha
    mov al, [di+16]
    cmp al, WT_FILES
    je .wdc_files
    cmp al, WT_EDIT
    je .wdc_edit
    cmp al, WT_STORE
    je .wdc_store
    cmp al, WT_CODE
    je .wdc_code
    jmp .wdc_done
.wdc_files:
    call fm_draw
    jmp .wdc_done
.wdc_edit:
    call te_draw
    jmp .wdc_done
.wdc_store:
    call as_draw
    jmp .wdc_done
.wdc_code:
    call tc_draw
.wdc_done:
    popa
    ret

; --- fm_draw: DI -> window record; file manager content ---
fm_draw:
    pusha
    ; content area starts at wy+WTB_H+1
    mov ax, [di+2]
    add ax, WTB_H + 2
    shr ax, 3           ; to text rows
    cmp ax, 23
    jle .fm_row_ok
    mov ax, 23
.fm_row_ok:
    mov dh, al          ; base text row
    mov ax, [di+0]
    add ax, 2
    shr ax, 3
    cmp ax, 38
    jle .fm_col_ok
    mov ax, 38
.fm_col_ok:
    mov dl, al          ; base text col
    ; position cursor and write header
    mov ah, 0x02
    xor bh, bh
    int 0x10
    push di
    mov si, fm_str_hdr
    mov bl, GC_ICON
.fm_hdr_l:
    mov al, [si]
    test al, al
    jz .fm_hdr_done
    mov ah, 0x09
    xor bh, bh
    mov cx, 1
    int 0x10
    mov ah, 0x03
    xor bh, bh
    int 0x10
    inc dl
    mov ah, 0x02
    xor bh, bh
    int 0x10
    inc si
    jmp .fm_hdr_l
.fm_hdr_done:
    pop di
    ; list files
    xor cx, cx
.fm_l:
    cmp cx, VFS_MAX
    jae .fm_done
    ; check if vfs slot has a name
    push cx
    movzx si, cl
    imul si, si, VFS_NLEN
    add si, vfs_names
    mov al, [si]
    test al, al
    jnz .fm_has_file
    ; empty slot - show placeholder
    movzx ax, dh
    add ax, cx
    inc ax
    cmp ax, 24
    jge .fm_skip_entry
    mov dh, al
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov ah, 0x09
    mov al, '-'
    xor bh, bh
    mov bl, GC_DOCKBD
    push cx
    mov cx, 1
    int 0x10
    pop cx
    jmp .fm_skip_entry
.fm_has_file:
    pop cx
    push cx
    ; compute row = base_row + 1 + file_index
    movzx ax, dh
    add ax, cx
    inc ax
    cmp ax, 24
    jge .fm_skip_entry
    mov dh, al
    mov ah, 0x02
    xor bh, bh
    int 0x10
    ; write filename (CX = file index)
    push cx
    movzx si, cl
    imul si, si, VFS_NLEN
    add si, vfs_names
.fm_fn_l:
    mov al, [si]
    test al, al
    jz .fm_fn_done
    mov ah, 0x09
    xor bh, bh
    mov bl, GC_ICON
    push si
    mov cx, 1
    int 0x10
    pop si
    mov ah, 0x03
    xor bh, bh
    int 0x10
    inc dl
    mov ah, 0x02
    xor bh, bh
    int 0x10
    inc si
    jmp .fm_fn_l
.fm_fn_done:
    pop cx
.fm_skip_entry:
    pop cx
    inc cx
    jmp .fm_l
.fm_done:
    popa
    ret

; --- te_draw: DI -> window record; text editor content ---
te_draw:
    pusha
    ; compute content area top-left in text grid
    mov ax, [di+2]
    add ax, WTB_H + 2
    shr ax, 3
    cmp ax, 23
    jle .te_row_ok
    mov ax, 23
.te_row_ok:
    mov dh, al
    mov ax, [di+0]
    add ax, 2
    shr ax, 3
    cmp ax, 38
    jle .te_col_ok
    mov ax, 38
.te_col_ok:
    mov dl, al
    mov ah, 0x02
    xor bh, bh
    int 0x10
    ; get VFS index for this window
    mov ax, [di+20]
    cmp ax, VFS_MAX
    jae .te_done
    ; display buffer contents line by line
    movzx si, al
    imul si, si, VFS_BSIZ
    add si, vfs_bufs
    mov ch, dh          ; starting row
    mov cl, dl          ; starting col
    ; compute max rows = (wy+wh - (wy+WTB_H+2)) / 8
    mov ax, [di+6]
    sub ax, WTB_H + 2
    shr ax, 3
    cmp ax, 0
    jle .te_done
    mov bp, ax          ; max rows
    xor bx, bx          ; char count in line
.te_loop:
    mov al, [si]
    test al, al
    jz .te_done
    cmp al, 0x0A
    je .te_newline
    ; write char
    push bp
    push si
    push bx
    mov ah, 0x09
    xor bh, bh
    mov bl, GC_ICON
    mov cx, 1
    int 0x10
    mov ah, 0x03
    xor bh, bh
    int 0x10
    inc dl
    ; check column wrap
    mov ax, [di+0]
    add ax, [di+4]
    shr ax, 3
    cmp ax, 40
    jl .te_col_lim
    mov ax, 40
.te_col_lim:
    cmp dl, al
    jl .te_adv
    ; wrap to next row
    mov dl, cl
    inc dh
    dec bp
    jle .te_done_restore
.te_adv:
    mov ah, 0x02
    xor bh, bh
    int 0x10
    pop bx
    pop si
    pop bp
    inc si
    inc bx
    jmp .te_loop
.te_done_restore:
    pop bx
    pop si
    pop bp
    jmp .te_done
.te_newline:
    mov dl, cl
    inc dh
    dec bp
    jle .te_done
    mov ah, 0x02
    xor bh, bh
    int 0x10
    inc si
    xor bx, bx
    jmp .te_loop
.te_done:
    popa
    ret

; --- te_key: DI -> window record, AL = keypress ---
te_key:
    pusha
    mov [wm_key_tmp], al    ; save key BEFORE any register clobber
    mov ax, [di+20]
    cmp ax, VFS_MAX
    jae .tk_done
    mov al, [wm_key_tmp]    ; restore key
    cmp al, 0x1B        ; ESC closes window
    jne .tk_noesc
    ; find window index and close
    mov si, di
    sub si, windows
    xor cx, cx
.tk_idx:
    cmp cx, MAX_WNDS
    jae .tk_done
    mov ax, cx
    imul ax, ax, WND_SIZE
    cmp ax, si
    je .tk_close
    inc cx
    jmp .tk_idx
.tk_close:
    mov bl, cl
    call wm_close_wnd
    jmp .tk_done
.tk_noesc:
    mov al, [wm_key_tmp]    ; ensure key is in AL for all checks below
    cmp al, 0x08        ; backspace
    jne .tk_noback
    movzx si, byte [di+20]
    imul si, si, VFS_BSIZ
    add si, vfs_bufs
    ; find end of buffer
    mov cx, VFS_BSIZ - 1
    xor bx, bx
.tk_bsf:
    cmp bx, cx
    jge .tk_bs_end
    cmp byte [si+bx], 0
    je .tk_bs_end
    inc bx
    jmp .tk_bsf
.tk_bs_end:
    test bx, bx
    jz .tk_done
    dec bx
    mov byte [si+bx], 0
    mov byte [wm_dirty], 1
    jmp .tk_done
.tk_noback:
    mov al, [wm_key_tmp]    ; restore key again
    cmp al, 0x0D        ; Enter -> newline
    jne .tk_norm
    mov al, 0x0A
.tk_norm:
    ; skip non-printable (except newline)
    cmp al, 0x0A
    je .tk_append_now
    cmp al, 0x20
    jb .tk_done
.tk_append_now:
    ; append char to VFS buffer
    movzx si, byte [di+20]
    imul si, si, VFS_BSIZ
    add si, vfs_bufs
    mov cx, VFS_BSIZ - 2
    xor bx, bx
.tk_find_end:
    cmp bx, cx
    jge .tk_done        ; buffer full
    cmp byte [si+bx], 0
    je .tk_append
    inc bx
    jmp .tk_find_end
.tk_append:
    mov [si+bx], al
    inc bx
    mov byte [si+bx], 0
    mov byte [wm_dirty], 1
.tk_done:
    popa
    ret

; --- wm_key_dispatch: AL=key, route to focused window ---
wm_key_dispatch:
    pusha
    mov [wm_key_tmp], al
    mov [wm_scan_tmp], ah       ; save scan code for F-key detection
    movzx bx, byte [wm_focus_wnd]
    cmp bx, MAX_WNDS
    jae .wkd_done
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    test byte [di+17], WF_OPEN
    jz .wkd_done
    cmp byte [wm_key_tmp], 0x1B
    jne .wkd_type
    call wm_close_wnd
    jmp .wkd_done
.wkd_type:
    mov al, [di+16]
    cmp al, WT_CODE
    jne .wkd_not_code
    ; F5 (scan 0x3F) runs Tommy's C; all other keys edit text
    cmp byte [wm_scan_tmp], 0x3F
    jne .wkd_code_key
    call wm_tc_run
    jmp .wkd_done
.wkd_code_key:
    mov al, [wm_key_tmp]
    call te_key
    jmp .wkd_done
.wkd_not_code:
    cmp al, WT_EDIT
    jne .wkd_done
    mov al, [wm_key_tmp]
    call te_key
.wkd_done:
    popa
    ret

; --- wm_cont_click: handle click in window content area ---
; BL=wndidx, ms_x/ms_y=click pos
wm_cont_click:
    pusha
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    mov byte [wm_dirty], 1
    cmp byte [di+16], WT_STORE
    je .wcc_store
    jmp .wcc_done
.wcc_store:
    ; row = (ms_y - (wy+WTB_H+2)) / 8
    mov ax, [ms_y]
    mov bx, [di+2]
    add bx, WTB_H + 2
    sub ax, bx
    cmp ax, 0
    jl .wcc_done
    shr ax, 3
    ; row 1=File Mgr, 2=Text Editor, 3=Snake, 4=Paint
    cmp ax, 1
    je .wcc_files
    cmp ax, 2
    je .wcc_edit
    cmp ax, 3
    je .wcc_snake
    cmp ax, 4
    je .wcc_paint
    jmp .wcc_done
.wcc_files:
    mov al, WT_FILES
    mov ah, 0
    call wm_open_wnd
    jmp .wcc_done
.wcc_edit:
    mov al, WT_EDIT
    mov ah, 0xFF
    call wm_open_wnd
    jmp .wcc_done
.wcc_snake:
    call wm_close_wnd           ; close store window (BL still valid)
    popa                        ; restore regs before mode switch
    call mouse_restore_bg
    call gfx_app_snake_entry
    call wm_restore_desk
    ret
.wcc_paint:
    call wm_close_wnd
    popa
    call mouse_restore_bg
    call gfx_app_paint
    call wm_restore_desk
    ret
.wcc_done:
    popa
    ret

; --- wm_init_vfs: pre-populate VFS with default files ---
wm_init_vfs:
    pusha
    push es
    push ds
    push cs
    pop ds
    push cs
    pop es
    ; file 0: "readme.txt"
    mov di, vfs_names
    mov si, wm_fn_readme
.wiv_cp0:
    lodsb
    stosb
    test al, al
    jnz .wiv_cp0
    ; readme content
    mov di, vfs_bufs
    mov si, wm_fc_readme
.wiv_cc0:
    lodsb
    stosb
    test al, al
    jnz .wiv_cc0
    ; file 1: "notes.txt" (empty)
    mov di, vfs_names + VFS_NLEN
    mov si, wm_fn_notes
.wiv_cp1:
    lodsb
    stosb
    test al, al
    jnz .wiv_cp1
    ; notes buffer already zero (BSS)
    ; file 2: "scratch.txt" (empty)
    mov di, vfs_names + VFS_NLEN*2
    mov si, wm_fn_scratch
.wiv_cp2:
    lodsb
    stosb
    test al, al
    jnz .wiv_cp2
    mov byte [vfs_count], 3
    pop ds
    pop es
    popa
    ret

; --- gd_dock_click: stub (replaced by wm_dock_click) ---
gd_dock_click:
    ret

; --- wm_restore_desk: return to windowed desktop after a full-screen app ---
wm_restore_desk:
    push ax
    push bx
    mov ax, 0x0013
    int 0x10
    call gfx_desk_pal
    mov byte [wm_dirty], 1
    pop bx
    pop ax
    ret

; --- gfx_desk_draw: composite all desktop layers ---
gfx_desk_draw:
    call gfx_grad_bg
    call gfx_topbar
    call gfx_dock_draw
    ret

; --- gfx_desk_pal: program DAC entries 16..31 ---
gfx_desk_pal:
    pusha
    mov dx, 0x3C8
    mov al, 16
    out dx, al
    inc dx
    mov si, gd_pal_dat
    mov cx, 16*3
.gdp:
    lodsb
    out dx, al
    loop .gdp
    popa
    ret

; --- gfx_grad_bg: vertical gradient bright-centre, dark-edges ---
gfx_grad_bg:
    push es
    push bx
    push cx
    push dx
    push di
    mov ax, 0xA000
    mov es, ax
    xor bx, bx
.ggb_row:
    cmp bx, 200
    jge .ggb_done
    mov ax, bx
    sub ax, 100
    jns .ggb_p
    neg ax
.ggb_p:
    xor cx, cx
    cmp ax, 13
    jl .ggb_g
    inc cx
    cmp ax, 26
    jl .ggb_g
    inc cx
    cmp ax, 39
    jl .ggb_g
    inc cx
    cmp ax, 52
    jl .ggb_g
    inc cx
    cmp ax, 65
    jl .ggb_g
    inc cx
    cmp ax, 78
    jl .ggb_g
    inc cx
    cmp ax, 91
    jl .ggb_g
    inc cx
.ggb_g:
    mov ax, 23
    sub ax, cx
    push bx
    imul bx, bx, 320
    mov di, bx
    pop bx
    mov ah, al
    mov cx, 160
    rep stosw
    inc bx
    jmp .ggb_row
.ggb_done:
    pop di
    pop dx
    pop cx
    pop bx
    pop es
    ret

; --- gfx_topbar: draw top bar area with floating labels ---
gfx_topbar:
    pusha
    push es
    mov ax, 0xA000
    mov es, ax
    xor di, di
    mov bx, 15
    mov ax, 0x1818          ; colour 24 in both bytes
.tb_f:
    mov cx, 160
    rep stosw
    dec bx
    jnz .tb_f
    ; Thin separator at row 15 (colour 31)
    mov cx, 160
    mov ax, 0x1F1F
    rep stosw
    pop es
    ; Write "Tommy_OS" at row 0, col 1
    mov ah, 0x02
    xor bh, bh
    xor dh, dh
    mov dl, 1
    int 0x10
    mov si, gd_str_brand
    call gd_wstr
    ; Write "v 2.0" at row 0, col 35
    mov ah, 0x02
    xor bh, bh
    xor dh, dh
    mov dl, 35
    int 0x10
    mov si, gd_str_ver
    call gd_wstr
    ; Clock (writes itself at col 16)
    call gfx_desk_clk
    popa
    ret

; --- gfx_desk_clk: read RTC and write HH:MM:SS at row 0 col 16 ---
; Throttled: only redraws when the seconds digit changes (~1 Hz).
; On a fast polling loop this drops ~26 BIOS calls/frame to 0.
gfx_desk_clk:
    pusha
    push es
    mov ah, 0x02
    int 0x1A
    jc .gdc_na              ; RTC unavailable → force redraw
    ; Compare current seconds (DH, BCD) to last-drawn seconds.
    cmp dh, [gd_last_sec]
    je .gdc_skip            ; same second → nothing to do
    mov [gd_last_sec], dh   ; record new second
    push cx
    push dx
    mov al, ch
    call mbclk_bcd
    mov [clk_buf2+0], ah
    mov [clk_buf2+1], al
    mov byte [clk_buf2+2], ':'
    pop dx
    push dx
    mov al, cl
    call mbclk_bcd
    mov [clk_buf2+3], ah
    mov [clk_buf2+4], al
    mov byte [clk_buf2+5], ':'
    mov al, dh
    call mbclk_bcd
    mov [clk_buf2+6], ah
    mov [clk_buf2+7], al
    mov byte [clk_buf2+8], 0
    pop dx
    pop cx
    jmp .gdc_wr
.gdc_na:
    ; RTC call failed: always redraw with "--:--:--" so the
    ; carry path never feeds a stale DH into [gd_last_sec].
    push es
    push ds
    pop es
    mov si, gd_str_nortc
    mov di, clk_buf2
    mov cx, 9
    rep movsb
    pop es
.gdc_wr:
    ; Clear the 9-char clock field with colour 24 pixels
    ; Field: pixel x=128..199 (72px), y=0..7 (8px = 1 char row)
    mov ax, 0xA000
    mov es, ax
    xor bx, bx
.gdc_cy:
    cmp bx, 8
    jge .gdc_txt
    push bx
    imul bx, bx, 320
    add bx, 128
    mov di, bx
    pop bx
    mov al, 24
    mov cx, 72
.gdc_cx:
    mov [es:di], al
    inc di
    loop .gdc_cx
    inc bx
    jmp .gdc_cy
.gdc_txt:
    pop es
    mov ah, 0x02
    xor bh, bh
    xor dh, dh
    mov dl, 16
    int 0x10
    mov si, clk_buf2
    call gd_wstr
    popa
    ret
.gdc_skip:
    ; Second unchanged – skip all pixel writes and BIOS calls.
    pop es
    popa
    ret

; --- gd_wstr: write null-terminated string at cursor, colour GC_ICON ---
; In mode 13h: AH=09h writes char; AH=03h gets cursor; AH=02h sets cursor.
gd_wstr:
    push ax
    push bx
    push cx
    push dx
.gwl:
    lodsb
    test al, al
    jz .gwd
    mov ah, 0x09
    xor bh, bh
    mov bl, GC_ICON
    mov cx, 1
    int 0x10
    mov ah, 0x03
    xor bh, bh
    int 0x10
    inc dl
    cmp dl, 40
    jl .gwadv
    xor dl, dl
    inc dh
.gwadv:
    mov ah, 0x02
    xor bh, bh
    int 0x10
    jmp .gwl
.gwd:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; --- gfx_dock_draw: draw the dock + 4 icons ---
gfx_dock_draw:
    pusha
    ; Dock background  x=40,y=148,w=240,h=44
    mov ax, 40
    mov bx, 148
    mov cx, 240
    mov dx, 44
    mov bp, GC_DOCKBG
    call gd_fillrect
    ; Dock outline
    mov ax, 40
    mov bx, 148
    mov cx, 240
    mov dx, 44
    mov bp, GC_DOCKBD
    call gfx_box
    ; Folder cx=88 cy=170
    mov ax, 88
    mov bx, 170
    call gd_icon_folder
    ; Document cx=136 cy=170
    mov ax, 136
    mov bx, 170
    call gd_icon_doc
    ; Code editor cx=184 cy=170
    mov ax, 184
    mov bx, 170
    call gd_icon_code
    ; App Store cx=232 cy=170
    mov ax, 232
    mov bx, 170
    call gd_icon_store
    popa
    ret

; --- gd_fillrect: fill rectangle  AX=x BX=y CX=w DX=h BP=colour ---
gd_fillrect:
    pusha
    push es
    mov si, 0xA000
    mov es, si
    mov si, ax          ; SI = left-edge x
.gfr_r:
    test dx, dx
    jz .gfr_done
    push bx
    imul bx, bx, 320
    add bx, si
    mov di, bx
    pop bx
    push cx
    mov ax, bp          ; AL = colour byte
.gfr_p:
    mov [es:di], al
    inc di
    dec cx
    jnz .gfr_p
    pop cx
    inc bx
    dec dx
    jmp .gfr_r
.gfr_done:
    pop es
    popa
    ret

; --- gd_icon_code: terminal/code icon centred at AX=cx BX=cy ---
gd_icon_code:
    pusha
    push es
    mov di, 0xA000
    mov es, di
    sub ax, 7           ; left edge
    sub bx, 5           ; top edge
    push ax
    push bx
    ; outer terminal box (14x10)
    mov cx, 14
    mov dx, 10
    mov bp, GC_DOCKBD
    call gfx_box
    ; dark inner fill
    pop bx
    pop ax
    push ax
    push bx
    inc ax
    inc bx
    mov cx, 12
    mov dx, 8
    mov bp, GC_SPOTBG
    call gd_fillrect
    ; three code-line bars
    pop bx
    pop ax
    add ax, 2
    add bx, 2
    push bx
    mov cx, 5
    mov dx, 1
    mov bp, GC_ICON
    call gd_fillrect        ; bar 1 (5px)
    pop bx
    add bx, 3
    push bx
    mov cx, 8
    call gd_fillrect        ; bar 2 (8px)
    pop bx
    add bx, 3
    mov cx, 4
    call gd_fillrect        ; bar 3 (4px)
    pop es
    popa
    ret

; --- gd_icon_store: shopping-bag icon centred at AX=cx BX=cy ---
gd_icon_store:
    pusha
    push es
    mov di, 0xA000
    mov es, di
    push ax             ; save center-x
    push bx             ; save center-y
    ; bag body (14x9) top-left = (cx-7, cy-1)
    sub ax, 7
    sub bx, 1
    mov cx, 14
    mov dx, 9
    mov bp, GC_DOCKBD
    call gfx_box        ; body outline
    inc ax
    inc bx
    mov cx, 12
    mov dx, 7
    mov bp, GC_TOPBAR
    call gd_fillrect    ; body fill
    ; handle bars above bag
    pop bx              ; center-y
    pop ax              ; center-x
    push ax
    push bx
    sub ax, 4           ; left post x
    sub bx, 6           ; handle top y
    mov cx, 1
    mov dx, 5
    mov bp, GC_DOCKBD
    call gd_fillrect    ; left bar
    pop bx
    pop ax
    add ax, 3           ; right post x
    sub bx, 6
    call gd_fillrect    ; right bar (cx=1 dx=5 bp still set)
    pop es
    popa
    ret

; --- gd_icon_folder: draw folder icon centred at AX=cx BX=cy ---
gd_icon_folder:
    pusha
    mov si, ax
    mov di, bx
    ; Tab: 16x6 at (cx-16, cy-14), colour 28 (warm highlight)
    mov ax, si
    sub ax, 16
    mov bx, di
    sub bx, 14
    mov cx, 16
    mov dx, 6
    mov bp, 28
    call gd_fillrect
    ; Body: 34x24 at (cx-17, cy-7), colour 27
    mov ax, si
    sub ax, 17
    mov bx, di
    sub bx, 7
    mov cx, 34
    mov dx, 24
    mov bp, GC_ICON
    call gd_fillrect
    popa
    ret

; --- gd_icon_doc: draw document icon centred at AX=cx BX=cy ---
gd_icon_doc:
    pusha
    mov si, ax
    mov di, bx
    ; Full page: 26x32 at (cx-13, cy-16)
    mov ax, si
    sub ax, 13
    mov bx, di
    sub bx, 16
    mov cx, 26
    mov dx, 32
    mov bp, GC_ICON
    call gd_fillrect
    ; Folded corner (top-right 7x7): paint over with dock bg
    mov ax, si
    add ax, 6
    mov bx, di
    sub bx, 16
    mov cx, 7
    mov dx, 7
    mov bp, GC_DOCKBG
    call gd_fillrect
    ; Three "text" lines cut into page (dock bg = dark strips)
    ; Line 1
    mov ax, si
    sub ax, 8
    mov bx, di
    sub bx, 7
    mov cx, 16
    mov dx, 2
    mov bp, GC_DOCKBG
    call gd_fillrect
    ; Line 2
    mov ax, si
    sub ax, 8
    mov bx, di
    sub bx, 1
    mov cx, 16
    mov dx, 2
    call gd_fillrect
    ; Line 3
    mov ax, si
    sub ax, 8
    mov bx, di
    add bx, 5
    mov cx, 16
    mov dx, 2
    call gd_fillrect
    popa
    ret

; --- gd_icon_gear: draw gear/settings icon centred at AX=cx BX=cy ---
gd_icon_gear:
    pusha
    mov si, ax
    mov di, bx
    ; Outer body 20x20, colour 27
    mov ax, si
    sub ax, 10
    mov bx, di
    sub bx, 10
    mov cx, 20
    mov dx, 20
    mov bp, GC_ICON
    call gd_fillrect
    ; Erase 4x4 corners to round the body
    mov bp, GC_DOCKBG
    mov cx, 4
    mov dx, 4
    mov ax, si
    sub ax, 10
    mov bx, di
    sub bx, 10
    call gd_fillrect                ; TL
    mov ax, si
    add ax, 6
    mov bx, di
    sub bx, 10
    call gd_fillrect                ; TR
    mov ax, si
    sub ax, 10
    mov bx, di
    add bx, 6
    call gd_fillrect                ; BL
    mov ax, si
    add ax, 6
    mov bx, di
    add bx, 6
    call gd_fillrect                ; BR
    ; Centre hole 8x8
    mov ax, si
    sub ax, 4
    mov bx, di
    sub bx, 4
    mov cx, 8
    mov dx, 8
    call gd_fillrect
    ; 4 teeth: N / S / W / E  (4x6 or 6x4)
    mov bp, GC_ICON
    ; N
    mov ax, si
    sub ax, 2
    mov bx, di
    sub bx, 16
    mov cx, 4
    mov dx, 6
    call gd_fillrect
    ; S
    mov ax, si
    sub ax, 2
    mov bx, di
    add bx, 10
    call gd_fillrect
    ; W
    mov ax, si
    sub ax, 16
    mov bx, di
    sub bx, 2
    mov cx, 6
    mov dx, 4
    call gd_fillrect
    ; E
    mov ax, si
    add ax, 10
    mov bx, di
    sub bx, 2
    call gd_fillrect
    popa
    ret

; ============================================================
; Tommy's C Interpreter  (F5 to run from the Code window)
; Syntax: print "string" | print EXPR | var NAME = EXPR | NAME = EXPR
; EXPR: integer | variable | EXPR +/- integer | EXPR * integer
; ============================================================

; --- wm_tc_run: interpret Tommy's C source in focused window ---
wm_tc_run:
    pusha
    push es
    push ds
    pop es
    mov di, tc_out_buf
    xor al, al
    mov cx, 96
    rep stosb
    mov di, tc_vars
    mov cx, TC_VAR_SLOTS * TC_VAR_SIZE
    rep stosb
    pop es
    mov word [tc_out_len], 0
    movzx bx, byte [wm_focus_wnd]
    cmp bx, MAX_WNDS
    jae .tcr_show
    movzx di, bl
    imul di, di, WND_SIZE
    add di, windows
    movzx si, word [di+20]
    cmp si, VFS_MAX
    jae .tcr_show
    imul si, si, VFS_BSIZ
    add si, vfs_bufs
.tcr_main:
    cmp byte [si], ' '
    jne .tcr_nsp
    inc si
    jmp .tcr_main
.tcr_nsp:
    cmp byte [si], 0
    je .tcr_show
    cmp byte [si], 0x0A
    je .tcr_nl
    cmp byte [si], '#'
    je .tcr_skip
    ; read first word into tc_tok
    mov di, tc_tok
    mov cx, 9
.tcr_rw:
    mov al, [si]
    cmp al, ' '
    jbe .tcr_rwe
    cmp al, '='
    je .tcr_rwe
    mov [di], al
    inc si
    inc di
    dec cx
    jnz .tcr_rw
.tcr_rwe:
    mov byte [di], 0
    mov di, tc_kw_print
    call tc_cmpstr
    je .tcr_print
    mov di, tc_kw_var
    call tc_cmpstr
    je .tcr_var_decl
    jmp .tcr_assign
.tcr_print:
.tcr_prsp:
    cmp byte [si], ' '
    jne .tcr_prnsp
    inc si
    jmp .tcr_prsp
.tcr_prnsp:
    cmp byte [si], '"'
    je .tcr_prstr
    call wm_tc_eval
    call tc_out_newline
    call tc_out_num
    jmp .tcr_skip
.tcr_prstr:
    inc si
    call tc_out_newline
.tcr_prsl:
    mov al, [si]
    test al, al
    jz .tcr_show
    cmp al, '"'
    je .tcr_prse
    cmp al, 0x0A
    je .tcr_skip
    call tc_out_char
    inc si
    jmp .tcr_prsl
.tcr_prse:
    inc si
    jmp .tcr_skip
.tcr_var_decl:
.tcr_vdsp:
    cmp byte [si], ' '
    jne .tcr_vdnsp
    inc si
    jmp .tcr_vdsp
.tcr_vdnsp:
    mov di, tc_tok
    mov cx, 7
.tcr_vdnm:
    mov al, [si]
    cmp al, ' '
    jbe .tcr_vdnme
    cmp al, '='
    je .tcr_vdnme
    mov [di], al
    inc si
    inc di
    dec cx
    jnz .tcr_vdnm
.tcr_vdnme:
    mov byte [di], 0
.tcr_vdeq:
    mov al, [si]
    cmp al, '='
    je .tcr_vdeqf
    test al, al
    jz .tcr_show
    cmp al, 0x0A
    je .tcr_skip
    inc si
    jmp .tcr_vdeq
.tcr_vdeqf:
    inc si
.tcr_vdvs:
    cmp byte [si], ' '
    jne .tcr_vdvns
    inc si
    jmp .tcr_vdvs
.tcr_vdvns:
    call wm_tc_eval
    call tc_store_var
    jmp .tcr_skip
.tcr_assign:
.tcr_aseq:
    mov al, [si]
    cmp al, '='
    je .tcr_aseqf
    test al, al
    jz .tcr_show
    cmp al, 0x0A
    je .tcr_skip
    inc si
    jmp .tcr_aseq
.tcr_aseqf:
    inc si
.tcr_assp:
    cmp byte [si], ' '
    jne .tcr_asnsp
    inc si
    jmp .tcr_assp
.tcr_asnsp:
    call wm_tc_eval
    call tc_store_var
.tcr_skip:
.tcr_skl:
    mov al, [si]
    test al, al
    jz .tcr_show
    cmp al, 0x0A
    je .tcr_nl
    inc si
    jmp .tcr_skl
.tcr_nl:
    inc si
    jmp .tcr_main
.tcr_show:
    call tc_show_output
    popa
    ret

; --- wm_tc_eval: evaluate expression at [SI], advance SI, return AX ---
wm_tc_eval:
    push bx
    push cx
.tce_sp:
    cmp byte [si], ' '
    jne .tce_nsp
    inc si
    jmp .tce_sp
.tce_nsp:
    cmp byte [si], '0'
    jb .tce_var
    cmp byte [si], '9'
    ja .tce_var
    xor ax, ax
.tce_dig:
    mov cl, [si]
    cmp cl, '0'
    jb .tce_op
    cmp cl, '9'
    ja .tce_op
    imul ax, ax, 10
    sub cl, '0'
    movzx cx, cl
    add ax, cx
    inc si
    jmp .tce_dig
.tce_var:
    mov di, tc_tok2
    mov cx, 7
.tce_vrd:
    mov al, [si]
    cmp al, 'A'
    jb .tce_vrd_done
    cmp al, 'Z'
    jle .tce_vrd_ok
    cmp al, 'a'
    jb .tce_vrd_done
    cmp al, 'z'
    ja .tce_vrd_done
.tce_vrd_ok:
    mov [di], al
    inc si
    inc di
    dec cx
    jnz .tce_vrd
.tce_vrd_done:
    mov byte [di], 0
    call tc_load_var
.tce_op:
.tce_osp:
    cmp byte [si], ' '
    jne .tce_onsp
    inc si
    jmp .tce_osp
.tce_onsp:
    cmp byte [si], '+'
    je .tce_add
    cmp byte [si], '-'
    je .tce_sub
    cmp byte [si], '*'
    je .tce_mul
    pop cx
    pop bx
    ret
.tce_add:
    inc si
    push ax
    call wm_tc_eval
    pop bx
    add ax, bx
    pop cx
    pop bx
    ret
.tce_sub:
    inc si
    push ax
    call wm_tc_eval
    pop bx
    sub bx, ax
    mov ax, bx
    pop cx
    pop bx
    ret
.tce_mul:
    inc si
    push ax
    call wm_tc_eval
    pop bx
    imul ax, bx
    pop cx
    pop bx
    ret

; --- tc_cmpstr: compare [tc_tok] with [DI], ZF=1 if equal ---
tc_cmpstr:
    push si
    push di
    push bx
    mov si, tc_tok
.tcs_l:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .tcs_ne
    test al, al
    jz .tcs_eq
    inc si
    inc di
    jmp .tcs_l
.tcs_eq:
    pop bx
    pop di
    pop si
    xor ax, ax      ; ZF=1
    ret
.tcs_ne:
    pop bx
    pop di
    pop si
    or al, 1        ; ZF=0
    ret

; --- tc_store_var: store AX in variable named [tc_tok] ---
tc_store_var:
    mov [tc_stv_val], ax
    push bx
    push cx
    push si
    push di
    mov bx, tc_vars
    xor cx, cx
.tsv_l:
    cmp cx, TC_VAR_SLOTS
    jae .tsv_new
    push bx
    push cx
    mov si, tc_tok
    mov di, bx
.tsv_cmp:
    mov al, [si]
    cmp al, [di]
    jne .tsv_no
    test al, al
    jz .tsv_found
    inc si
    inc di
    jmp .tsv_cmp
.tsv_no:
    pop cx
    pop bx
    add bx, TC_VAR_SIZE
    inc cx
    jmp .tsv_l
.tsv_found:
    pop cx
    pop bx
    add bx, TC_VAR_NLEN
    mov ax, [tc_stv_val]
    mov [bx], ax
    pop di
    pop si
    pop cx
    pop bx
    ret
.tsv_new:
    mov bx, tc_vars
    xor cx, cx
.tsv_el:
    cmp cx, TC_VAR_SLOTS
    jae .tsv_fail
    cmp byte [bx], 0
    je .tsv_got
    add bx, TC_VAR_SIZE
    inc cx
    jmp .tsv_el
.tsv_got:
    mov si, tc_tok
    mov di, bx
    mov cx, TC_VAR_NLEN
.tsv_cp:
    mov al, [si]
    mov [di], al
    test al, al
    jz .tsv_cp_done
    inc si
    inc di
    dec cx
    jnz .tsv_cp
.tsv_cp_done:
    add bx, TC_VAR_NLEN
    mov ax, [tc_stv_val]
    mov [bx], ax
    pop di
    pop si
    pop cx
    pop bx
    ret
.tsv_fail:
    pop di
    pop si
    pop cx
    pop bx
    ret

; --- tc_load_var: AX = value of variable named [tc_tok2] (0 if not found) ---
tc_load_var:
    push bx
    push cx
    push si
    push di
    mov bx, tc_vars
    xor cx, cx
.tlv_l:
    cmp cx, TC_VAR_SLOTS
    jae .tlv_not
    push bx
    push cx
    mov si, tc_tok2
    mov di, bx
.tlv_cmp:
    mov al, [si]
    cmp al, [di]
    jne .tlv_no
    test al, al
    jz .tlv_found
    inc si
    inc di
    jmp .tlv_cmp
.tlv_no:
    pop cx
    pop bx
    add bx, TC_VAR_SIZE
    inc cx
    jmp .tlv_l
.tlv_found:
    pop cx
    pop bx
    add bx, TC_VAR_NLEN
    mov ax, [bx]
    pop di
    pop si
    pop cx
    pop bx
    ret
.tlv_not:
    xor ax, ax
    pop di
    pop si
    pop cx
    pop bx
    ret

; --- tc_out_char: append AL to tc_out_buf ---
tc_out_char:
    push bx
    movzx bx, word [tc_out_len]
    cmp bx, 94
    jae .toc_done
    mov [tc_out_buf + bx], al
    inc word [tc_out_len]
.toc_done:
    pop bx
    ret

; --- tc_out_newline: append LF if buffer non-empty and last != LF ---
tc_out_newline:
    push ax
    push bx
    movzx bx, word [tc_out_len]
    test bx, bx
    jz .ton_done
    dec bx
    cmp byte [tc_out_buf + bx], 0x0A
    je .ton_done
    mov al, 0x0A
    call tc_out_char
.ton_done:
    pop bx
    pop ax
    ret

; --- tc_out_num: convert AX to decimal string and append ---
tc_out_num:
    push ax
    push bx
    push cx
    push dx
    test ax, ax
    jns .tonum_pos
    push ax
    mov al, '-'
    call tc_out_char
    pop ax
    neg ax
.tonum_pos:
    mov bx, 10
    xor cx, cx
.tonum_d:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .tonum_d
.tonum_p:
    pop dx
    mov al, dl
    add al, '0'
    call tc_out_char
    dec cx
    jnz .tonum_p
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; --- tc_show_output: show tc_out_buf in overlay, wait for key ---
tc_show_output:
    pusha
    ; background box x=30,y=48,w=260,h=104
    mov ax, 30
    mov bx, 48
    mov cx, 260
    mov dx, 104
    mov bp, GC_SPOTBG
    call gd_fillrect
    mov ax, 30
    mov bx, 48
    mov cx, 260
    mov dx, 104
    mov bp, GC_DOCKBD
    call gfx_box
    ; header at row 6, col 4
    mov ah, 0x02
    xor bh, bh
    mov dh, 6
    mov dl, 4
    int 0x10
    mov si, tc_str_hdr
    call gd_wstr
    ; output lines starting at row 8
    mov si, tc_out_buf
    mov dh, 8
    mov dl, 4
.tso_check:
    cmp byte [si], 0
    je .tso_wait
    mov ah, 0x02
    xor bh, bh
    int 0x10
.tso_char:
    mov al, [si]
    test al, al
    jz .tso_wait
    cmp al, 0x0A
    je .tso_nl
    mov ah, 0x09
    xor bh, bh
    mov bl, GC_SPOTTX
    mov cx, 1
    int 0x10
    inc dl
    mov ah, 0x02
    xor bh, bh
    int 0x10
    inc si
    jmp .tso_char
.tso_nl:
    inc si
    inc dh
    cmp dh, 18
    jae .tso_wait
    mov dl, 4
    jmp .tso_check
.tso_wait:
    mov ah, 0x02
    xor bh, bh
    mov dh, 19
    mov dl, 4
    int 0x10
    mov si, tc_str_anykey
    call gd_wstr
    xor ax, ax
    int 0x16
    mov byte [wm_dirty], 1
    popa
    ret

; --- as_draw: DI -> window record; App Store content ---
as_draw:
    pusha
    mov ax, [di+2]
    add ax, WTB_H + 2
    shr ax, 3
    cmp ax, 23
    jle .asd_row_ok
    mov ax, 23
.asd_row_ok:
    mov dh, al
    mov ax, [di+0]
    add ax, 2
    shr ax, 3
    cmp ax, 38
    jle .asd_col_ok
    mov ax, 38
.asd_col_ok:
    mov dl, al
    ; row 0: header
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov si, as_str_hdr
    call gd_wstr
    inc dh
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov si, as_str_fm
    call gd_wstr
    inc dh
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov si, as_str_te
    call gd_wstr
    inc dh
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov si, as_str_sn
    call gd_wstr
    inc dh
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov si, as_str_pt
    call gd_wstr
    popa
    ret

; --- tc_draw: DI -> window record; Tommy's C code editor ---
tc_draw:
    call te_draw        ; same as text editor (F5 to run)
    ret

; --- gfx_spotlight: centered input overlay for running commands ---
gfx_spotlight:
    pusha
    ; Draw background box  x=50,y=72,w=220,h=56
    mov ax, 50
    mov bx, 72
    mov cx, 220
    mov dx, 56
    mov bp, GC_SPOTBG
    call gd_fillrect
    ; Outer border (colour 26)
    mov ax, 50
    mov bx, 72
    mov cx, 220
    mov dx, 56
    mov bp, GC_DOCKBD
    call gfx_box
    ; Inner border (colour 27)
    mov ax, 52
    mov bx, 74
    mov cx, 216
    mov dx, 52
    mov bp, GC_ICON
    call gfx_box
    ; Header text at row 9, col 14
    mov ah, 0x02
    xor bh, bh
    mov dh, 9
    mov dl, 14
    int 0x10
    mov si, gd_str_spot
    call gd_wstr
    ; Prompt ">" at row 10, col 7
    mov ah, 0x02
    xor bh, bh
    mov dh, 10
    mov dl, 7
    int 0x10
    mov ah, 0x09
    mov al, '>'
    xor bh, bh
    mov bl, GC_ICON
    mov cx, 1
    int 0x10
    ; Position cursor at col 9, row 10
    mov ah, 0x02
    xor bh, bh
    mov dh, 10
    mov dl, 9
    int 0x10
    ; Init input state
    mov word [gd_slen], 0
    mov byte [gd_scol], 9
.spl:
    xor ax, ax
    int 0x16
    cmp al, 0x1B
    je .spout
    cmp al, 0x0D
    je .spexec
    cmp al, 0x08
    je .spbs
    cmp al, 0x20
    jl .spl
    mov bx, [gd_slen]
    cmp bx, 37
    jge .spl
    mov si, gd_sbuf
    add si, bx
    mov [si], al
    inc word [gd_slen]
    mov ah, 0x09
    xor bh, bh
    mov bl, GC_SPOTTX
    mov cx, 1
    int 0x10
    inc byte [gd_scol]
    mov ah, 0x02
    xor bh, bh
    mov dh, 10
    mov dl, [gd_scol]
    int 0x10
    jmp .spl
.spbs:
    cmp word [gd_slen], 0
    je .spl
    dec word [gd_slen]
    dec byte [gd_scol]
    mov ah, 0x02
    xor bh, bh
    mov dh, 10
    mov dl, [gd_scol]
    int 0x10
    mov ah, 0x09
    mov al, ' '
    xor bh, bh
    mov bl, GC_SPOTBG
    mov cx, 1
    int 0x10
    mov ah, 0x02
    xor bh, bh
    mov dh, 10
    mov dl, [gd_scol]
    int 0x10
    jmp .spl
.spexec:
    ; Null-terminate buffer
    mov bx, [gd_slen]
    mov si, gd_sbuf
    add si, bx
    mov byte [si], 0
    ; Copy input to cmd_buf
    push es
    push ds
    pop es
    mov si, gd_sbuf
    mov di, cmd_buf
    mov cx, MAX_CMD
    rep movsb
    pop es
    ; Switch to text mode and run command
    call gd_2text
    call exec_cmd
    ; Wait for key before returning to desktop
    xor ax, ax
    int 0x16
    call gd_2gfx
.spout:
    popa
    ret

; ============================================================
; NEW STRING DATA (v2 additions)
; ============================================================

; Menu bar strings
str_mb_brand    db ' Tommy OS ', 0
str_mb_file     db 'File', 0
str_mb_edit     db 'Edit', 0
str_mb_view     db 'View', 0
str_mb_apps     db 'Apps', 0
str_mb_help     db 'Help', 0
str_mb_clock_na db '--:--:--', 0

; Desktop strings
str_desk_title  db 'Welcome to Tommy OS v2.0', 0
str_desk_hint1  db ' 1  or  T  -  Terminal (shell + filesystem)', 0
str_desk_hint2  db ' 2  or  E  -  Text Editor + IDE', 0
str_desk_hint3  db ' 3  or  G  -  Graphics Mode (paint, demos)', 0
str_desk_hint4  db ' 4  or  S  -  Snake  (arrow keys)', 0
str_desk_hint5  db ' 5  or  A  -  About Tommy OS', 0

; Dock strings
str_dock_l      db 0xB3, 0          ; │
str_dock_r      db 0xB3, 0          ; │
str_dock_term   db ' >_ Terminal  ', 0
str_dock_edit   db ' ✎  Editor   ', 0
str_dock_gfx    db ' ◆  Graphics ', 0
str_dock_games  db ' ♟  Games    ', 0
str_dock_about  db ' ?  About    ', 0

; Window title bar strings
str_wt_terminal db 'Terminal  -  ESC=desktop  type help for commands', 0
str_wt_editor   db 'Text Editor v2.0  -  ^S=save  ^L=load  ^R=run  ESC=quit', 0
str_wt_about    db 'About Tommy OS', 0

; Desktop icon strings
str_icon_hd     db 0xDB, 0xDB, 0xDB, 0xDB, 0xDB, 0xDB, 0          ; ██████
str_icon_hd_lbl db 'TommyOS HD', 0
str_icon_trash  db 0xBA, 0x20, 0x20, 0x20, 0xBA, 0          ; █   █
str_icon_trash_lbl db 'Trash', 0

; About dialog strings
str_about2_logo  db 'T O M M Y   O S', 0
str_about2_ver   db 'Version 2.0  -  macOS-style Desktop', 0
str_about2_line1 db 'Architecture: x86 16-bit real mode', 0
str_about2_line2 db 'Language:     x86 Assembly (NASM)', 0
str_about2_line3 db 'Size:         64 KB flat binary', 0
str_about2_jesus db 'Jesus is King.', 0
str_about2_close db 'Press any key to close', 0

; Desktop state variable
desk_state      db DS_DESKTOP

; Clock buffer for menu bar
clk_buf2        times 10 db 0

; ---- GFX Desktop palette data: 16 entries × (R,G,B) each 0-63 ----
gd_pal_dat:
    db  0, 0,18   ; 16: bg edge (very dark blue)
    db  0, 3,26   ; 17
    db  0, 7,34   ; 18
    db  2,12,42   ; 19
    db  5,18,50   ; 20
    db  9,24,57   ; 21
    db 13,30,63   ; 22
    db 18,36,63   ; 23: bg centre (bright blue)
    db  2, 2,14   ; 24: top bar (near-black)
    db  8,10,22   ; 25: dock background
    db 28,30,44   ; 26: dock border
    db 52,56,63   ; 27: icon / text (near-white blue)
    db 60,58,30   ; 28: icon tab highlight (warm)
    db  6, 8,20   ; 29: spotlight background
    db 55,55,62   ; 30: spotlight text
    db 16,18,36   ; 31: top bar separator

; ---- GFX Desktop strings ----
gd_str_brand    db 'Tommy_OS', 0
gd_str_ver      db 'v 2.02', 0
gd_str_nortc    db '--:--:--', 0
gd_str_spot     db '  Run command (Enter=exec  ESC=cancel)', 0

; ---- GFX Spotlight input state ----
gd_sbuf         times 40 db 0
gd_slen         dw 0
gd_scol         db 0

; ---- Clock throttle: last drawn second (0xFF = never drawn) ----
gd_last_sec     db 0xFF

; ---- Window Manager data ----
wm_dirty        db 0            ; 1 = redraw needed
wm_drag_wnd     db 0xFF         ; 0xFF = none
wm_rsz_wnd      db 0xFF         ; 0xFF = none
wm_focus_wnd    db 0xFF         ; 0xFF = none
wm_drag_ox      dw 0
wm_drag_oy      dw 0
wm_next_file    db 0
wm_key_tmp      db 0            ; temp storage for key in wm_key_dispatch
wm_scan_tmp     db 0            ; scan code for F-key detection
wm_last_ms_x    dw 0xFFFF       ; last cursor x drawn (0xFFFF = force draw)
wm_last_ms_y    dw 0xFFFF       ; last cursor y drawn

; Window records: MAX_WNDS * WND_SIZE bytes
; Each record: [0]=x [2]=y [4]=w [6]=h [8]=saved_x [10]=saved_y
;              [12]=saved_w [14]=saved_h [16]=type [17]=flags
;              [18]=title_ptr [20]=file_idx
windows         times (3*24) db 0

; VFS: 3 files, each with 14-byte name and 350-byte buffer
vfs_names       times (3*14) db 0
vfs_bufs        times (3*350) db 0
vfs_count       db 0

; Window title strings
wm_str_files    db 'File Manager', 0
wm_str_edit     db 'Text Editor', 0
wm_str_store    db 'App Store', 0
wm_str_code     db "Tommy's C", 0

; File manager header string
fm_str_hdr      db 'Files:', 0

; VFS default filenames
wm_fn_readme    db 'readme.txt', 0
wm_fn_notes     db 'notes.txt', 0
wm_fn_scratch   db 'scratch.txt', 0

; readme.txt default content (null-terminated)
wm_fc_readme    db 'Tommy OS v2.02', 0x0A
                db '--------------', 0x0A
                db 'Folder  - browse files', 0x0A
                db 'Doc     - text editor', 0x0A
                db "Code    - Tommy's C IDE", 0x0A
                db 'Store   - app launcher', 0x0A
                db 'Drag title bar to move.', 0x0A
                db 'Drag corner to resize.', 0x0A
                db 'X=close  []=maximise', 0x0A
                db 'ESC=close focused window', 0x0A
                db "F5=run Tommy's C code", 0x0A
                db 0

; ---- App Store strings ----
as_str_hdr      db 'Available Apps:', 0
as_str_fm       db '  [>] File Manager', 0
as_str_te       db '  [>] Text Editor', 0
as_str_sn       db '  [>] Snake Game', 0
as_str_pt       db '  [>] Paint Mode', 0

; ---- Tommy's C interpreter ----
TC_VAR_SLOTS    equ 4
TC_VAR_NLEN     equ 8
TC_VAR_SIZE     equ 10          ; name(8) + int16 value(2)
tc_kw_print     db 'print', 0
tc_kw_var       db 'var', 0
tc_tok          times 10 db 0   ; first-word / assignment-target token
tc_tok2         times 10 db 0   ; expression variable name buffer
tc_stv_val      dw 0            ; tc_store_var scratch
tc_vars         times (TC_VAR_SLOTS * TC_VAR_SIZE) db 0
tc_out_buf      times 96 db 0   ; interpreter output (null-terminated)
tc_out_len      dw 0
tc_str_hdr      db "Tommy's C Output", 0
tc_str_anykey   db '  Press any key...', 0

; Pad to fill exactly 125 sectors (must match boot.asm)
times (125*512)-($-$$) db 0
