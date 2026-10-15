.intel_syntax noprefix
.code16
.arch i8086
.section .text
.global start

# By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
# Temporary DOS loader for the patched Commando 1.01 copies.
# INT 60h covers the direct video drawing pass.
# INT 61h selects CGA mode 4 and enables ColorPlus 320x200x16.
# INT 62h transfers changed low/high color words together to video RAM.
# INT 63h clears a scene before gameplay.
# INT 64h clears the extra video bank at other screen transitions.
# INT 65h clears the pre-play scene before active play starts.
# INT 66h/67h mark entry/exit of the attract-play state (02h).
# INT 68h/69h mark entry/exit of the player-play state (04h).

start:
    push cs
    pop ds
    push cs
    pop es
    cli
    lea sp, [stack_top]
    sti

    lea bx, [stack_top + 15]
    shr bx, 1
    shr bx, 1
    shr bx, 1
    shr bx, 1
    mov ah, 0x4a
    int 0x21
    jc memory_error

    call trace_begin

    mov ax, 0x3560
    int 0x21
    mov [old60], bx
    mov [old60 + 2], es
    mov ax, 0x3561
    int 0x21
    mov [old61], bx
    mov [old61 + 2], es
    mov ax, 0x3562
    int 0x21
    mov [old62], bx
    mov [old62 + 2], es
    mov ax, 0x3563
    int 0x21
    mov [old63], bx
    mov [old63 + 2], es
    mov ax, 0x3564
    int 0x21
    mov [old64], bx
    mov [old64 + 2], es
    mov ax, 0x3565
    int 0x21
    mov [old65], bx
    mov [old65 + 2], es
    mov ax, 0x3566
    int 0x21
    mov [old66], bx
    mov [old66 + 2], es
    mov ax, 0x3567
    int 0x21
    mov [old67], bx
    mov [old67 + 2], es
    mov ax, 0x3568
    int 0x21
    mov [old68], bx
    mov [old68 + 2], es
    mov ax, 0x3569
    int 0x21
    mov [old69], bx
    mov [old69 + 2], es

    lea dx, [frame_handler]
    mov ax, 0x2560
    int 0x21
    lea dx, [mode_handler]
    mov ax, 0x2561
    int 0x21
    lea dx, [copy_handler]
    mov ax, 0x2562
    int 0x21
    lea dx, [scene_handler]
    mov ax, 0x2563
    int 0x21
    lea dx, [screen_clear_handler]
    mov ax, 0x2564
    int 0x21
    lea dx, [intro_clear_handler]
    mov ax, 0x2565
    int 0x21
    lea dx, [demo_start_handler]
    mov ax, 0x2566
    int 0x21
    lea dx, [demo_leave_handler]
    mov ax, 0x2567
    int 0x21
    lea dx, [play_start_handler]
    mov ax, 0x2568
    int 0x21
    lea dx, [play_leave_handler]
    mov ax, 0x2569
    int 0x21

    push cs
    pop ds
    mov ax, cs
    mov [exec_block + 4], ax
    mov [exec_block + 8], ax
    mov [exec_block + 12], ax
    push cs
    pop es
    mov ax, 0x4b00
    lea dx, [game_name]
    lea bx, [exec_block]
    int 0x21
    jc game_error

    mov ah, 0x4d
    int 0x21
    push cs
    pop ds
    mov [exit_code], al
    mov [exit_type], ah
    call report_return
    jmp cleanup

game_error:
    push cs
    pop ds
    mov [dos_error], ax
    mov byte ptr [exit_code], 1
    call report_exec_error

cleanup:
    push cs
    pop ds
    lds dx, [old60]
    mov ax, 0x2560
    int 0x21
    push cs
    pop ds
    lds dx, [old61]
    mov ax, 0x2561
    int 0x21
    push cs
    pop ds
    lds dx, [old62]
    mov ax, 0x2562
    int 0x21
    push cs
    pop ds
    lds dx, [old63]
    mov ax, 0x2563
    int 0x21
    push cs
    pop ds
    lds dx, [old64]
    mov ax, 0x2564
    int 0x21
    push cs
    pop ds
    lds dx, [old65]
    mov ax, 0x2565
    int 0x21
    push cs
    pop ds
    lds dx, [old66]
    mov ax, 0x2566
    int 0x21
    push cs
    pop ds
    lds dx, [old67]
    mov ax, 0x2567
    int 0x21
    push cs
    pop ds
    lds dx, [old68]
    mov ax, 0x2568
    int 0x21
    push cs
    pop ds
    lds dx, [old69]
    mov ax, 0x2569
    int 0x21
    mov dx, 0x03dd
    xor al, al
    out dx, al
    in al, 0x61
    and al, 0xfc
    out 0x61, al
    push cs
    pop ds
    mov al, [exit_code]
    mov ah, 0x4c
    int 0x21

memory_error:
    lea dx, [memory_error_text]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21

# Called from a six-byte in-image trampoline after the original renderer.
# The game data segment remains in DS. The ISR preserves every register.
frame_handler:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    cld
    mov bp, sp
    test word ptr ss:[bp + 22], 0x0200
    jz frame_irq_off
    sti
frame_irq_off:
    inc word ptr cs:[frame_count]
    cmp byte ptr cs:[gameplay_active], 0
    je frame_colors_done
    call refresh_colors
    mov byte ptr cs:[force_full_high], 1
frame_colors_done:
    cmp byte ptr cs:[gameplay_active], 0
    je frame_sample_done
    mov byte ptr cs:[life_sample_type], 'D'
    call sample_life_pixels
frame_sample_done:
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

# Replaces only the zero-fill call at the pre-play scene setup. It keeps
# the original 16 KB RAM clear and forces a full paired transfer afterward.
# At entry, the caller's screen segment and fill byte are at SS:BP+8/+10.
scene_handler:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push di
    push es
    cld
    test word ptr ss:[bp + 6], 0x0200
    jz scene_irq_off
    sti
scene_irq_off:
    inc byte ptr cs:[scene_count]
    mov byte ptr cs:[gameplay_active], 1
    mov byte ptr cs:[force_full_high], 1
    mov ax, word ptr ss:[bp + 8]
    mov es, ax
    mov al, byte ptr ss:[bp + 10]
    mov ah, al
    xor di, di
    mov cx, 0x2000
    rep stosw
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    pop bp
    iret

# Replaces REP STOSW inside the common RAM-screen clear. The playfield
# setup bypasses this through INT 63h. Other clears restore the extra bank
# while retaining the active-play state, since some happen during a round.
screen_clear_handler:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push di
    push es
    cld
    test word ptr ss:[bp + 6], 0x0200
    jz screen_irq_off
    sti
screen_irq_off:
    rep stosw
    inc byte ptr cs:[clear_count]
    cmp byte ptr cs:[mode_count], 0
    je screen_clear_done
    mov ax, 0xbc00
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 0x2000
    rep stosw
    mov byte ptr cs:[previous_count], 0
    mov byte ptr cs:[force_full_high], 1
screen_clear_done:
    pop es
    pop di
    pop cx
    pop bx
    pop ax
    pop bp
    iret

# The clear at EXE offset 63A5h ends the pre-play sequence. Recreate its
# RAM clear and remove old soldiers before the actual gameplay begins.
intro_clear_handler:
    push bp
    mov bp, sp
    push ax
    push cx
    push di
    push es
    cld
    test word ptr ss:[bp + 6], 0x0200
    jz round_irq_off
    sti
round_irq_off:
    inc byte ptr cs:[intro_clear_count]
    mov byte ptr cs:[gameplay_active], 0
    mov byte ptr cs:[previous_count], 0
    mov byte ptr cs:[force_full_high], 1
    mov ax, word ptr ss:[bp + 8]
    mov es, ax
    mov al, byte ptr ss:[bp + 10]
    mov ah, al
    xor di, di
    mov cx, 0x2000
    rep stosw
    cmp byte ptr cs:[mode_count], 0
    je round_clear_done
    mov ax, 0xbc00
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 0x2000
    rep stosw
round_clear_done:
    pop es
    pop di
    pop cx
    pop ax
    pop bp
    iret

# Replaces MOV word ptr DS:[FE32h],0 at EXE offset 3601h. State 02h
# uses the game's attract-play path after the pre-play sequence.
demo_start_handler:
    mov word ptr ds:[0xfe32], 0
    inc byte ptr cs:[demo_start_count]
    mov byte ptr cs:[gameplay_active], 1
    mov byte ptr cs:[previous_count], 0
    mov byte ptr cs:[force_full_high], 1
    iret

# Replaces the state-02h jump at EXE offset 369Bh. Resume at its original
# target, 35C8h (runtime IP 33C8h).
demo_leave_handler:
    push bp
    mov bp, sp
    push ax
    push cx
    push di
    push es
    inc byte ptr cs:[demo_leave_count]
    mov byte ptr cs:[gameplay_active], 0
    call clear_video_on_leave
    mov word ptr ss:[bp + 2], 0x33c8
    pop es
    pop di
    pop cx
    pop ax
    pop bp
    iret

# State 04h is the player-controlled round. Preserve its original write.
play_start_handler:
    mov byte ptr ds:[0xfa19], 4
    inc byte ptr cs:[play_start_count]
    mov byte ptr cs:[gameplay_active], 1
    mov byte ptr cs:[previous_count], 0
    mov byte ptr cs:[force_full_high], 1
    iret

# Leave the player round through the original back edge to EXE 358Ch.
play_leave_handler:
    push bp
    mov bp, sp
    push ax
    push cx
    push di
    push es
    inc byte ptr cs:[play_leave_count]
    mov byte ptr cs:[gameplay_active], 0
    call clear_video_on_leave
    mov word ptr ss:[bp + 2], 0x338c
    pop es
    pop di
    pop cx
    pop ax
    pop bp
    iret

# Both round exits precede the menu or high-score redraw. Clear visible RAM
# now, because the next screen does not repaint every old soldier location.
clear_video_on_leave:
    mov byte ptr cs:[previous_count], 0
    mov byte ptr cs:[force_full_high], 1
    cmp byte ptr cs:[mode_count], 0
    je clear_video_done
    cld
    mov ax, 0xb800
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 0x2000
    rep stosw
    mov ax, 0xbc00
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 0x2000
    rep stosw
clear_video_done:
    ret

# Paint the precomputed upper-color sprites using their original masks.
# The game's own renderer draws their patched lower-color data.
refresh_colors:
    # Restore only the old colored footprints to the black upper-plane base.
    xor ax, ax
    mov al, byte ptr cs:[previous_count]
    mov word ptr cs:[remaining], ax
    mov word ptr cs:[object_ptr], offset previous_objects
previous_loop:
    cmp word ptr cs:[remaining], 0
    je previous_done
    mov si, word ptr cs:[object_ptr]
    mov ax, word ptr cs:[si]
    mov word ptr cs:[sprite_ptr], ax
    mov ax, word ptr cs:[si + 2]
    mov word ptr cs:[sprite_x], ax
    mov byte ptr cs:[plane_mode], 4
    mov ax, word ptr cs:[high_segment]
    mov es, ax
    push ds
    push cs
    pop ds
    call paint_plane
    pop ds
    add word ptr cs:[object_ptr], 4
    dec word ptr cs:[remaining]
    jmp previous_loop
previous_done:
    mov byte ptr cs:[previous_count], 0
    mov word ptr cs:[previous_write], 0
    mov si, word ptr ds:[0xf8fc]
    mov word ptr cs:[object_ptr], si
    mov ax, word ptr ds:[0xf8fe]
    mov word ptr cs:[remaining], ax
    cmp ax, 25
    ja colors_done
object_loop:
    cmp word ptr cs:[remaining], 0
    je colors_done
    mov si, word ptr cs:[object_ptr]
    mov dx, word ptr [si + 6]
    cmp dx, 0xffff
    je object_next
    mov bl, byte ptr [si + 4]
    mov bh, byte ptr [si + 5]
    mov word ptr cs:[sprite_ptr], dx
    mov byte ptr cs:[sprite_x], bl
    mov byte ptr cs:[sprite_y], bh
    cmp dx, 0x739a
    je rock_object
    cmp dx, 0x804a
    jb soldier_object
    cmp dx, 0x84ae
    jbe effects_object
soldier_object:
    cmp dx, 0x1e12
    jb object_next
    cmp dx, 0x3a0e
    jbe enemy_object
    cmp dx, 0x3dac
    jb object_next
    cmp dx, 0x5848
    ja object_next
    jmp hero_object

enemy_object:
    mov ax, dx
    sub ax, 0x1e12
    add ax, offset enemy_high_data
    jmp paint_precomputed

hero_object:
    mov ax, dx
    sub ax, 0x3dac
    add ax, offset hero_high_data
    jmp paint_precomputed

rock_object:
    mov ax, dx
    sub ax, 0x739a
    add ax, offset rock_high_data
    jmp paint_precomputed

effects_object:
    mov ax, dx
    sub ax, 0x804a
    add ax, offset effects_high_data

paint_precomputed:
    mov word ptr cs:[sprite_ptr], ax
    mov byte ptr cs:[plane_mode], 5
    mov ax, word ptr cs:[high_segment]
    mov es, ax
    push ds
    push cs
    pop ds
    call paint_plane
    pop ds

save_object:
    mov bx, word ptr cs:[previous_write]
    mov ax, word ptr cs:[sprite_ptr]
    mov word ptr cs:[previous_objects + bx], ax
    mov ax, word ptr cs:[sprite_x]
    mov word ptr cs:[previous_objects + bx + 2], ax
    add word ptr cs:[previous_write], 4
    inc byte ptr cs:[previous_count]
object_next:
    add word ptr cs:[object_ptr], 8
    dec word ptr cs:[remaining]
    jmp object_loop
colors_done:
    ret

# DS:SI reads the original sprite. ES:DI updates one ColorPlus plane.
# Sprite headers contain height and byte width. Odd x uses a second image
# within the same sprite, selected by the leading offset word.
paint_plane:
    xor ax, ax
    mov al, byte ptr cs:[sprite_y]
    shr ax, 1
    mov bx, 80
    mul bx
    xor bx, bx
    mov bl, byte ptr cs:[sprite_x]
    shr bx, 1
    add ax, bx
    mov di, ax
    test byte ptr cs:[sprite_y], 1
    jz sprite_even_row
    add di, 0x2000
    mov byte ptr cs:[row_parity], 1
    jmp sprite_row_ready
sprite_even_row:
    mov byte ptr cs:[row_parity], 0
sprite_row_ready:
    cmp byte ptr cs:[shadow_active], 0
    je sprite_no_shadow
    add di, offset high_shadow
sprite_no_shadow:

    mov si, word ptr cs:[sprite_ptr]
    test byte ptr cs:[sprite_x], 1
    jz even_sprite
    mov bx, word ptr [si]
    add si, 2
    add si, bx
    jmp sprite_header
even_sprite:
    add si, 2
sprite_header:
    lodsw
    mov byte ptr cs:[row_count], al
    mov byte ptr cs:[byte_width], ah
    mov byte ptr cs:[row_index], 0
    or al, al
    jz paint_done
    or ah, ah
    jz paint_done

sprite_row:
    mov word ptr cs:[row_start], di
    cmp byte ptr cs:[shadow_active], 0
    je sprite_no_dirty
    push ax
    push bx
    xor bx, bx
    mov bl, byte ptr cs:[sprite_y]
    add bl, byte ptr cs:[row_index]
    mov al, byte ptr cs:[sprite_x]
    shr al, 1
    cmp al, byte ptr cs:[dirty_min + bx]
    jae dirty_min_ok
    mov byte ptr cs:[dirty_min + bx], al
dirty_min_ok:
    add al, byte ptr cs:[byte_width]
    cmp al, byte ptr cs:[dirty_max + bx]
    jbe dirty_max_ok
    mov byte ptr cs:[dirty_max + bx], al
dirty_max_ok:
    pop bx
    pop ax
sprite_no_dirty:
    xor cx, cx
    mov cl, byte ptr cs:[byte_width]
sprite_byte:
    lodsw
    mov dl, al
    cmp byte ptr cs:[plane_mode], 4
    jne combine_pixel
    xor ah, ah
combine_pixel:
    mov al, dl
    not al
    and ah, al
    mov al, byte ptr es:[di]
    and al, dl
    or al, ah
    mov byte ptr es:[di], al
    inc di
    loop sprite_byte

    mov di, word ptr cs:[row_start]
    cmp byte ptr cs:[row_parity], 0
    jne next_even_row
    add di, 0x2000
    mov byte ptr cs:[row_parity], 1
    jmp row_advanced
next_even_row:
    sub di, 0x2000
    add di, 80
    mov byte ptr cs:[row_parity], 0
row_advanced:
    inc byte ptr cs:[row_index]
    dec byte ptr cs:[row_count]
    jnz sprite_row
paint_done:
    ret

# The trace is written only at DOS-safe boundaries, never inside a hook.
# A read-only game disk simply leaves logging disabled.
trace_begin:
    push ax
    push bx
    push cx
    push dx
    push ds
    push cs
    pop ds
    lea dx, [trace_name]
    xor cx, cx
    mov ah, 0x3c
    int 0x21
    jc trace_begin_done
    mov bx, ax
    lea dx, [trace_start]
    mov cx, trace_start_end - trace_start
    mov ah, 0x40
    int 0x21
    mov ah, 0x3e
    int 0x21
trace_begin_done:
    pop ds
    pop dx
    pop cx
    pop bx
    pop ax
    ret

# DS:DX and CX describe one line to append.
trace_append:
    push ax
    push bx
    push cx
    push dx
    lea dx, [trace_name]
    mov ax, 0x3d01
    int 0x21
    jc trace_append_done
    mov bx, ax
    xor cx, cx
    xor dx, dx
    mov ax, 0x4202
    int 0x21
    pop dx
    pop cx
    push cx
    push dx
    mov ah, 0x40
    int 0x21
    mov ah, 0x3e
    int 0x21
trace_append_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

report_return:
    lea di, [return_type]
    mov al, [exit_type]
    call format_byte
    lea di, [return_code]
    mov al, [exit_code]
    call format_byte
    lea di, [return_mode]
    mov al, [mode_count]
    call format_byte
    lea di, [return_frames]
    mov al, [frame_count + 1]
    call format_byte
    mov al, [frame_count]
    call format_byte
    lea di, [return_copy]
    mov al, [copy_count]
    call format_byte
    lea di, [return_scene]
    mov al, [scene_count]
    call format_byte
    lea di, [return_clear]
    mov al, [clear_count]
    call format_byte
    lea di, [return_intro]
    mov al, [intro_clear_count]
    call format_byte
    lea di, [return_demo_start]
    mov al, [demo_start_count]
    call format_byte
    lea di, [return_demo_leave]
    mov al, [demo_leave_count]
    call format_byte
    lea di, [return_play_start]
    mov al, [play_start_count]
    call format_byte
    lea di, [return_play_leave]
    mov al, [play_leave_count]
    call format_byte
    lea si, [life_low_bytes]
    lea di, [life_low_text]
    mov cx, 16
format_life_low:
    mov al, [si]
    call format_byte
    inc si
    loop format_life_low
    lea si, [life_high_bytes]
    lea di, [life_high_text]
    mov cx, 16
format_life_high:
    mov al, [si]
    call format_byte
    inc si
    loop format_life_high
    lea dx, [trace_return]
    mov cx, trace_return_end - trace_return
    call trace_append
    mov bx, 1
    mov ah, 0x40
    int 0x21
    ret

report_exec_error:
    lea di, [error_number]
    mov al, [dos_error + 1]
    call format_byte
    mov al, [dos_error]
    call format_byte
    lea dx, [trace_error]
    mov cx, trace_error_end - trace_error
    call trace_append
    mov bx, 1
    mov ah, 0x40
    int 0x21
    ret

format_byte:
    push bx
    mov bl, al
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call format_nibble
    mov al, bl
    and al, 0x0f
    call format_nibble
    pop bx
    ret
format_nibble:
    and al, 0x0f
    cmp al, 10
    jb format_digit
    add al, 7
format_digit:
    add al, '0'
    mov [di], al
    inc di
    ret

# Replaces only the graphics-mode call at EXE offset 6C1Dh.
mode_handler:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov bp, sp
    test word ptr ss:[bp + 22], 0x0200
    jz mode_irq_off
    sti
mode_irq_off:
    inc byte ptr cs:[mode_count]
    mov ax, 4
    int 0x10
    mov dx, 0x03dd
    mov al, 0x10
    out dx, al
    cld
    mov ax, 0xbc00
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 0x2000
    rep stosw
    push cs
    pop es
    mov di, offset high_shadow
    mov cx, 0x2000
    rep stosw
    mov byte ptr cs:[previous_count], 0
    mov word ptr cs:[high_segment], 0xbc00
    mov byte ptr cs:[shadow_active], 0
    mov byte ptr cs:[force_full_high], 1
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

# Replaces the game's full B800 copy call at EXE offset 6CA2h.
# At interrupt entry, [SS:SP+6] is the caller's source-segment argument.
copy_handler:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    cld
    test word ptr ss:[bp + 6], 0x0200
    jz copy_irq_off
    sti
copy_irq_off:
    inc byte ptr cs:[copy_count]
    mov ax, word ptr [bp + 8]
    mov word ptr ds:[0x9241], ax
    mov byte ptr cs:[shadow_active], 1
    mov ax, cs
    mov word ptr cs:[high_segment], ax
    mov al, byte ptr cs:[force_full_high]
    mov byte ptr cs:[overlay_full], al
    call clear_dirty_rows
    cmp byte ptr cs:[overlay_full], 0
    je static_overlay_done
    cmp byte ptr cs:[gameplay_active], 0
    je static_overlay_done
    push ds
    mov ax, word ptr [bp + 8]
    mov ds, ax
    xor bx, bx
static_overlay_loop:
    call overlay_classify_byte
    inc bx
    cmp bx, 0x4000
    jb static_overlay_loop
    pop ds
static_overlay_done:
    mov byte ptr cs:[overlay_full], 0
    cmp byte ptr cs:[gameplay_active], 0
    je copy_colors_done
    call refresh_colors
copy_colors_done:
    mov ax, word ptr [bp + 8]
    mov ds, ax
    mov ax, 0xb800
    mov es, ax
    xor si, si
    xor di, di
    mov byte ptr cs:[scan_row], 0
    call copy_bank_rows
    mov byte ptr cs:[scan_row], 1
    call copy_bank_rows
    call copy_changed_low
    cmp byte ptr cs:[gameplay_active], 0
    je copy_sample_done
    mov byte ptr cs:[life_sample_type], 'C'
    call sample_life_pixels
copy_sample_done:
    pop es
    pop ds
    mov word ptr cs:[high_segment], 0xbc00
    mov byte ptr cs:[shadow_active], 0
    mov dx, 0x03dd
    mov al, 0x10
    out dx, al
    inc word ptr cs:[frame_count]
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    pop bp
    iret

clear_dirty_rows:
    push cs
    pop es
    mov di, offset dirty_min
    mov cx, 200
    mov al, 80
    rep stosb
    mov di, offset dirty_max
    mov cx, 200
    xor al, al
    rep stosb
    cmp byte ptr cs:[force_full_high], 0
    je dirty_ready
    mov di, offset high_shadow
    xor ax, ax
    mov cx, 0x2000
    rep stosw
    mov byte ptr cs:[previous_count], 0
    mov di, offset dirty_min
    mov cx, 200
    xor al, al
    rep stosb
    mov di, offset dirty_max
    mov cx, 200
    mov al, 80
    rep stosb
    mov byte ptr cs:[force_full_high], 0
dirty_ready:
    ret

# Transfer high-plane sprite footprints and the matching lower words first.
# B800:4000 addresses the upper plane without changing ES in the inner loop.
copy_bank_rows:
copy_scanline:
    xor bx, bx
    mov bl, byte ptr cs:[scan_row]
    mov al, byte ptr cs:[dirty_min + bx]
    and al, 0xfe
    mov byte ptr cs:[dirty_word_start], al
    mov al, byte ptr cs:[dirty_max + bx]
    cmp al, byte ptr cs:[dirty_min + bx]
    jbe copy_next_line
    inc al
    and al, 0xfe
    mov byte ptr cs:[dirty_word_end], al
    xor cx, cx
    mov cl, al
    sub cl, byte ptr cs:[dirty_word_start]
    shr cx, 1
    xor bx, bx
    mov bl, byte ptr cs:[dirty_word_start]
    add bx, si
    jcxz copy_next_line
copy_dirty_word:
    mov ax, word ptr [bx]
    mov word ptr cs:[low_shadow + bx], ax
    mov dx, word ptr cs:[high_shadow + bx]
    mov word ptr es:[bx + 0x4000], dx
    mov word ptr es:[bx], ax
    add bx, 2
    loop copy_dirty_word
copy_next_line:
    add si, 80
    add byte ptr cs:[scan_row], 2
    cmp byte ptr cs:[scan_row], 200
    jb copy_scanline
    add si, 192
    ret

# REPE CMPSW skips unchanged RAM words. Any other changing game graphics
# are transferred as paired low/high words. Padding is compared too.
copy_changed_low:
    push cs
    pop es
    xor si, si
    mov di, offset low_shadow
    mov cx, 0x2000
compare_words:
    repe cmpsw
    jz compare_done
    mov bx, si
    sub bx, 2
    call overlay_classify_byte
    inc bx
    call overlay_classify_byte
    dec bx
    mov ax, word ptr [bx]
    mov word ptr es:[di - 2], ax
    mov dx, word ptr cs:[high_shadow + bx]
    push ax
    mov ax, 0xb800
    mov es, ax
    pop ax
    mov word ptr es:[bx + 0x4000], dx
    mov word ptr es:[bx], ax
    push cs
    pop es
    or cx, cx
    jnz compare_words
compare_done:
    ret

# Diagnostic only: read 16 fixed score-panel bytes from both video banks.
# This makes no video writes and avoids another costly screen scan.
sample_life_pixels:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, 0xb800
    mov ds, ax
    mov ax, 0xbc00
    mov es, ax
    mov si, offset life_sample_offsets
    mov di, offset life_low_bytes
    mov bx, offset life_high_bytes
    mov cx, 16
sample_life_next:
    mov bp, word ptr cs:[si]
    mov al, byte ptr ds:[bp]
    mov byte ptr cs:[di], al
    mov al, byte ptr es:[bp]
    mov byte ptr cs:[bx], al
    add si, 2
    inc di
    inc bx
    loop sample_life_next
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

# Recolor only known static-art coordinates in the game's RAM screen, before
# each lower/upper word reaches video RAM. A full scene pass visits every
# byte once. Later passes touch only words changed by the game, including
# score digits. The tables preserve already-colored low-1 pixels in place.
# DS:BX is one screen byte; CS holds the upper-bank shadow and tables.
overlay_classify_byte:
    cmp byte ptr cs:[gameplay_active], 0
    je overlay_return
    push ax
    push cx
    push dx
    push si
    mov ax, bx
    and ax, 0x1fff
    xor dx, dx
    mov cx, 80
    div cx
    cmp ax, 100
    jae overlay_done
    shl ax, 1
    test bx, 0x2000
    jz overlay_row_ready
    inc ax
overlay_row_ready:
    cmp dx, 11
    jb overlay_side
    cmp dx, 69
    jae overlay_side

    # Cyan score frame, SCORE label, score digits, and life digits. Brighten
    # the five small life marks left of the number. The larger soldier icon
    # retains its original red/yellow artwork.
    cmp ax, 152
    jb overlay_upper_frame
    cmp ax, 199
    ja overlay_upper_frame
    cmp dx, 14
    jb overlay_cyan
    cmp dx, 66
    jae overlay_cyan
    cmp ax, 160
    jbe overlay_cyan
    cmp ax, 192
    jae overlay_cyan
    cmp ax, 158
    jb overlay_done
    cmp ax, 191
    ja overlay_done
    cmp dx, 18
    jb overlay_done
    cmp dx, 40
    jb overlay_cyan
    cmp dx, 60
    jb overlay_life_marks
    cmp dx, 66
    jae overlay_done
    cmp ax, 180
    jb overlay_icon
    jmp overlay_cyan

overlay_upper_frame:
    cmp byte ptr cs:[overlay_full], 0
    je overlay_done
    cmp ax, 8
    jb overlay_done
    cmp ax, 145
    ja overlay_done
    cmp dx, 14
    jb overlay_cyan
    cmp dx, 66
    jae overlay_cyan
    cmp ax, 18
    jbe overlay_cyan
    cmp ax, 143
    jae overlay_cyan
    jmp overlay_done

overlay_side:
    cmp byte ptr cs:[overlay_full], 0
    je overlay_done
    xor ah, ah
    mov al, byte ptr [bx]
    mov si, ax
    mov al, byte ptr cs:[screen_tables + si]
    mov byte ptr [bx], al
    mov al, byte ptr cs:[screen_tables + 512 + si]
    and al, byte ptr cs:[high_shadow + bx]
    or al, byte ptr cs:[screen_tables + 256 + si]
    mov byte ptr cs:[high_shadow + bx], al
    jmp overlay_done

overlay_icon:
    mov byte ptr cs:[high_shadow + bx], 0
    jmp overlay_done

overlay_life_marks:
    mov al, byte ptr [bx]
    mov byte ptr cs:[high_shadow + bx], al
    jmp overlay_done

overlay_cyan:
    xor ah, ah
    mov al, byte ptr [bx]
    mov si, ax
    mov al, byte ptr cs:[screen_tables + 768 + si]
    mov byte ptr [bx], al
    mov al, byte ptr cs:[screen_tables + 1280 + si]
    and al, byte ptr cs:[high_shadow + bx]
    or al, byte ptr cs:[screen_tables + 1024 + si]
    mov byte ptr cs:[high_shadow + bx], al
overlay_done:
    pop si
    pop dx
    pop cx
    pop ax
overlay_return:
    ret

old60: .word 0, 0
old61: .word 0, 0
old62: .word 0, 0
old63: .word 0, 0
old64: .word 0, 0
old65: .word 0, 0
old66: .word 0, 0
old67: .word 0, 0
old68: .word 0, 0
old69: .word 0, 0
exit_code: .byte 0
exit_type: .byte 0
dos_error: .word 0
mode_count: .byte 0
copy_count: .byte 0
scene_count: .byte 0
clear_count: .byte 0
intro_clear_count: .byte 0
demo_start_count: .byte 0
demo_leave_count: .byte 0
play_start_count: .byte 0
play_leave_count: .byte 0
life_low_bytes: .space 16
life_high_bytes: .space 16
frame_count: .word 0
object_ptr: .word 0
remaining: .word 0
sprite_ptr: .word 0
sprite_x: .byte 0
sprite_y: .byte 0
plane_mode: .byte 0
row_count: .byte 0
row_index: .byte 0
byte_width: .byte 0
row_parity: .byte 0
row_start: .word 0
previous_count: .byte 0
previous_write: .word 0
previous_objects: .space 100
high_segment: .word 0xbc00
shadow_active: .byte 0
force_full_high: .byte 1
gameplay_active: .byte 0
overlay_full: .byte 0
scan_row: .byte 0
dirty_word_start: .byte 0
dirty_word_end: .byte 0
dirty_min: .space 200
dirty_max: .space 200
life_sample_offsets:
    .word 0x1b61, 0x1b65, 0x3b61, 0x3b65
    .word 0x1c01, 0x1c05, 0x3c01, 0x3c05
    .word 0x1ca1, 0x1ca5, 0x3ca1, 0x3ca5
    .word 0x1d41, 0x1d45, 0x3d41, 0x3d45

game_name: .asciz "STARTC0.COM"
memory_error_text: .ascii "Unable to release DOS memory.\r\n$"
trace_name: .asciz "PLTRACE.TXT"
trace_start: .ascii "Plantronics loader reached DOS EXEC.\r\n"
trace_start_end:
trace_return: .ascii "Child returned: type="
return_type: .ascii "00"
    .ascii " code="
return_code: .ascii "00"
    .ascii " mode="
return_mode: .ascii "00"
    .ascii " frames="
return_frames: .ascii "0000"
    .ascii " copy="
return_copy: .ascii "00\r\n"
    .ascii "Scene builds: "
return_scene: .ascii "00\r\n"
    .ascii "Other clears: "
return_clear: .ascii "00\r\n"
    .ascii "Intro clears: "
return_intro: .ascii "00\r\n"
    .ascii "Attract starts: "
return_demo_start: .ascii "00\r\n"
    .ascii "Attract leaves: "
return_demo_leave: .ascii "00\r\n"
    .ascii "Player starts: "
return_play_start: .ascii "00\r\n"
    .ascii "Player leaves: "
return_play_leave: .ascii "00\r\n"
    .ascii "Life sample "
life_sample_type: .byte '0'
    .ascii " L="
life_low_text: .ascii "00000000000000000000000000000000"
    .ascii " H="
life_high_text: .ascii "00000000000000000000000000000000\r\n"
trace_return_end:
trace_error: .ascii "DOS EXEC failed: AX="
error_number: .ascii "0000\r\n"
trace_error_end:

exec_block:
    .word 0
    .word 0x80, 0
    .word 0x5c, 0
    .word 0x6c, 0

    .balign 16
enemy_high_data:
    .incbin "enemy_high.bin"
hero_high_data:
    .incbin "hero_high.bin"
rock_high_data:
    .incbin "rock_high.bin"
effects_high_data:
    .incbin "effects_high.bin"
screen_tables:
    .incbin "screen_tables.bin"
high_shadow:
    .space 0x4000
low_shadow:
    .space 0x4000
stack_space:
    .space 1024
stack_top:
