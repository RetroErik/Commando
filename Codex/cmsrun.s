.intel_syntax noprefix
.code16
.arch i8086
.ifndef SID_MODE
.set SID_MODE, 0
.endif
.section .text
.global start

# By Dag Erik Hagesæter / Retro Erik using Codex in VS Code
# 8086 DOS .COM loader and CMS bridge for Commando 1.01.
# The copied EXE and its duplicate in DAT replace OUT 61h with INT 60h
# and OUT 42h with INT 61h.
# Both vectors remain installed only while STARTC0.COM and its child run.
start:
    push cs
    pop ds
    push cs
    pop es
    cli
    lea sp, [stack_top]
    sti

    # Release unused COM allocation so DOS can load the original game.
    lea bx, [stack_top + 15]
    shr bx, 1
    shr bx, 1
    shr bx, 1
    shr bx, 1
    mov ah, 0x4a
    int 0x21
    jc memory_error

.if SID_MODE >= 4
    call sid_load_score
    jc score_error
.endif

    mov ax, 0x3560
    int 0x21
    mov word ptr [old60], bx
    mov word ptr [old60 + 2], es
    mov ax, 0x3561
    int 0x21
    mov word ptr [old61], bx
    mov word ptr [old61 + 2], es
.if SID_MODE
    mov ax, 0x3562
    int 0x21
    mov word ptr [old62], bx
    mov word ptr [old62 + 2], es
.endif
.if SID_MODE == 5
    mov ax, 0x3563
    int 0x21
    mov word ptr [old63], bx
    mov word ptr [old63 + 2], es
.endif

    lea dx, [gate_handler]
    mov ax, 0x2560
    int 0x21
    lea dx, [pitch_handler]
    mov ax, 0x2561
    int 0x21
.if SID_MODE
    lea dx, [sid_tick_handler]
    mov ax, 0x2562
    int 0x21
.endif
.if SID_MODE == 5
    lea dx, [music_toggle_handler]
    mov ax, 0x2563
    int 0x21
.endif

    call cms_init
    lea dx, [test_message]
    mov ah, 9
    int 0x21
.if SID_MODE == 0
    call cms_test_tone
.endif

    push cs
    pop ds
    push cs
    pop es
    mov ax, cs
    mov word ptr [exec_block + 4], ax
    mov word ptr [exec_block + 8], ax
    mov word ptr [exec_block + 12], ax
    mov ax, 0x4b00
    lea dx, [game_name]
    lea bx, [exec_block]
    int 0x21
    jc game_error

    # Save the child return code before uninstalling our temporary vectors.
    mov ah, 0x4d
    int 0x21
    push cs
    pop ds
    mov [exit_code], al
    jmp cleanup

game_error:
    push cs
    pop ds
    mov byte ptr [exit_code], 1
    lea dx, [game_error_text]
    mov ah, 9
    int 0x21

cleanup:
    call cms_silence
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
.if SID_MODE
    push cs
    pop ds
    lds dx, [old62]
    mov ax, 0x2562
    int 0x21
.endif
.if SID_MODE == 5
    push cs
    pop ds
    lds dx, [old63]
    mov ax, 0x2563
    int 0x21
.endif
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

.if SID_MODE >= 4
score_error:
    push cs
    pop ds
    lea dx, [score_error_text]
    mov ah, 9
    int 0x21
    mov ax, 0x4c01
    int 0x21

# Keep the long score in two DOS-owned blocks outside the COM segment.
sid_load_score:
    mov ah, 0x48
    mov bx, 3750
    int 0x21
    jc sid_load_fail
    mov [score_seg0], ax
    mov ah, 0x48
    mov bx, 3370
    int 0x21
    jc sid_load_fail
    mov [score_seg1], ax
    mov ax, 0x3d00
    lea dx, [score_name]
    int 0x21
    jc sid_load_fail
    mov [score_handle], ax
    mov bx, ax
    mov ax, [score_seg0]
    mov ds, ax
    xor dx, dx
    mov cx, 60000
    mov ah, 0x3f
    int 0x21
    push cs
    pop ds
    jc sid_load_fail
    cmp ax, 60000
    jne sid_load_fail
    mov bx, [score_handle]
    mov ax, [score_seg1]
    mov ds, ax
    xor dx, dx
    mov cx, 53907
    mov ah, 0x3f
    int 0x21
    push cs
    pop ds
    jc sid_load_fail
    cmp ax, 53907
    jne sid_load_fail
    mov bx, [score_handle]
    mov ah, 0x3e
    int 0x21
    clc
    ret
sid_load_fail:
    stc
    ret
.endif

# Write SAA1099 register AL with value AH on chip 0 at base 220h.
cms_write:
    push dx
    mov dx, 0x221
    out dx, al
    dec dx
    mov al, ah
    out dx, al
    pop dx
    ret

.if SID_MODE >= 2
# The second SAA1099 is addressed at 222h/223h on a Game Blaster.
cms_write_second:
    push dx
    mov dx, 0x223
    out dx, al
    dec dx
    mov al, ah
    out dx, al
    pop dx
    ret
.endif

cms_init:
    mov al, 0x1c
    mov ah, 1
    call cms_write
    mov al, 0x15
    xor ah, ah
    call cms_write
    mov al, 0x14
    call cms_write
    mov al, 0x00
    mov ah, 0xcc
    call cms_write
    mov al, 0x08
    xor ah, ah
    call cms_write
    mov al, 0x10
    call cms_write
.if SID_MODE
.if SID_MODE >= 2
    mov al, 0x03
    mov ah, 0x99
    call cms_write
    mov al, 0x16
    mov ah, 0x30
    call cms_write
    mov al, 0x1c
    mov ah, 1
    call cms_write_second
    mov al, 0x14
    xor ah, ah
    call cms_write_second
    mov al, 0x15
    call cms_write_second
    mov al, 0x00
    mov ah, 0x99
    call cms_write_second
    mov al, 0x03
    call cms_write_second
    mov al, 0x16
    mov ah, 0x33
    call cms_write_second
.else
    mov al, 0x01
    mov ah, 0x99
    call cms_write
    mov al, 0x02
    call cms_write
    mov al, 0x03
    call cms_write
    mov al, 0x16
    mov ah, 0x22
    call cms_write
.endif
.endif
    ret

cms_silence:
    mov al, 0x14
    xor ah, ah
    call cms_write
    mov al, 0x15
    call cms_write
    mov al, 0x1c
    call cms_write
.if SID_MODE >= 2
    mov al, 0x14
    xor ah, ah
    call cms_write_second
    mov al, 0x15
    call cms_write_second
    mov al, 0x1c
    call cms_write_second
.endif
    ret

# A short middle-C tone verifies the CMS port before the game starts.
.if SID_MODE == 0
cms_test_tone:
    push bx
    push es
    mov al, 0x10
    mov ah, 2
    call cms_write
    mov al, 0x08
    mov ah, 33
    call cms_write
    mov al, 0x14
    mov ah, 1
    call cms_write
    mov ax, 0x40
    mov es, ax
    mov bx, word ptr es:[0x6c]
test_wait:
    mov ax, word ptr es:[0x6c]
    sub ax, bx
    cmp ax, 12
    jb test_wait
    mov al, 0x14
    xor ah, ah
    call cms_write
    pop es
    pop bx
    ret
.endif

.if SID_MODE == 5
# The patched game music setter calls INT 63h when M is pressed. Return AX=0
# so the game's own tune remains muted, and change only the CMS music level.
music_toggle_handler:
    push dx
    push ds
    push cs
    pop ds
    xor byte ptr [sid_music_enabled], 1
    call sid_apply_music_volume
    pop ds
    pop dx
    xor ax, ax
    iret

sid_apply_music_volume:
    mov ah, [sid_current_volumes]
    cmp byte ptr [sid_music_enabled], 0
    jne sid_apply_first
    xor ah, ah
sid_apply_first:
    mov al, 0x03
    call cms_write
    mov ah, [sid_current_volumes + 1]
    cmp byte ptr [sid_music_enabled], 0
    jne sid_apply_second
    xor ah, ah
sid_apply_second:
    mov al, 0x00
    call cms_write_second
    mov ah, [sid_current_volumes + 2]
    cmp byte ptr [sid_music_enabled], 0
    jne sid_apply_third
    xor ah, ah
sid_apply_third:
    mov al, 0x03
    call cms_write_second
    ret
.endif

# Preserve the original speaker gate state, without driving the speaker.
gate_handler:
    push ax
    push dx
    push ds
    push cs
    pop ds
.if SID_MODE
    and al, 3
    mov ah, [sid_freq_mask]
    and ah, 0xfe
    cmp al, 3
    jne gate_sid_write
    or ah, 1
gate_sid_write:
    mov [sid_freq_mask], ah
    mov al, 0x14
    call cms_write
.else
    and al, 3
    cmp al, 3
    mov ah, 0
    jne gate_write
    mov ah, 1
gate_write:
    mov al, 0x14
    call cms_write
.endif
    pop ds
    pop dx
    pop ax
    iret

# The game writes PIT channel 2 low byte, then high byte. Recover its
# original divisor and translate it into an SAA1099 octave and tone value.
pitch_handler:
    push ax
    push bx
    push cx
    push dx
    push ds
    push cs
    pop ds
    cmp byte ptr [pitch_phase], 0
    jne pitch_high
    mov [pitch_low], al
    mov byte ptr [pitch_phase], 1
    jmp pitch_done

pitch_high:
    mov byte ptr [pitch_phase], 0
    mov ah, al
    mov al, [pitch_low]
    mov bx, ax
    or bx, bx
    jz pitch_min
    cmp bx, 19
    jb pitch_max

    # 1,193,182 / PIT divisor = approximate pitch in Hz.
    mov dx, 0x12
    mov ax, 0x34de
    div bx
    cmp ax, 61
    jb pitch_min
    xor cx, cx
pitch_octave:
    cmp ax, 122
    jbe pitch_tone
    shr ax, 1
    inc cl
    cmp cl, 7
    jb pitch_octave
    jmp pitch_tone

pitch_min:
    xor cx, cx
    xor bx, bx
    jmp pitch_output
pitch_max:
    mov cx, 7
    mov bx, 255
    jmp pitch_output

pitch_tone:
    # SAA1099 frequency ~= 31250 * 2^octave / (511 - tone).
    mov bx, ax
    mov ax, 31250
    xor dx, dx
    div bx
    mov bx, 511
    sub bx, ax
    jns pitch_output
    xor bx, bx

pitch_output:
    mov al, 0x10
.if SID_MODE
    mov ah, [sid_oct01]
    and ah, 0xf0
    or ah, cl
    mov [sid_oct01], ah
.else
    mov ah, cl
.endif
    call cms_write
    mov al, 0x08
    mov ah, bl
    call cms_write

pitch_done:
    pop ds
    pop dx
    pop cx
    pop bx
    pop ax
    iret

.if SID_MODE
# Replaces the game's near CALL to its sound tick in the IRQ0 handler.
# Run that original tick first, then advance the precompiled SID score.
sid_tick_handler:
    push ax
    push bp
    mov bp, sp
    mov ax, [bp + 6]
    mov word ptr cs:[game_tick_ptr + 2], ax
    pop bp
    pop ax
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    # The original sound tick ends in a near RET. Enter its CS with RETF,
    # let that RET reach an existing CB byte in the same immutable code,
    # then return here through that one-byte RETF. A regular far CALL
    # would leave its saved CS on the stack after the game's near RET.
    push cs
    mov ax, offset sid_after_game_tick
    push ax
    mov ax, 0x6cf8
    push ax
    push word ptr cs:[game_tick_ptr + 2]
    mov ax, 0x69a5
    push ax
    retf
sid_after_game_tick:
    push cs
    pop ds
    call sid_tick
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

# The game timer runs about 109 Hz; the C64 PAL score advances at 50 Hz.
sid_tick:
    add byte ptr [sid_phase], 50
    cmp byte ptr [sid_phase], 109
    jb sid_tick_done
    sub byte ptr [sid_phase], 109
    cmp byte ptr [sid_skip], 0
    je sid_read_frame
    dec byte ptr [sid_skip]
    ret
sid_read_frame:
    mov si, [sid_cursor]
.if SID_MODE >= 4
    mov ax, [score_seg0]
    cmp byte ptr [sid_bank], 0
    je sid_score_segment_ready
    mov ax, [score_seg1]
sid_score_segment_ready:
    mov es, ax
    call sid_score_byte
    mov dl, al
.else
    mov dl, [si]
    inc si
.endif
    cmp dl, 0xff
    jne sid_frame_command
.if SID_MODE >= 4
    mov byte ptr [sid_bank], 0
    mov ax, [score_seg0]
    mov es, ax
    xor si, si
    call sid_score_byte
    mov dl, al
.else
    lea si, [sid_score]
    mov dl, [si]
    inc si
.endif
sid_frame_command:
    test dl, 0x80
    jz sid_frame_events
    and dl, 0x7f
    dec dl
    mov [sid_skip], dl
    jmp sid_save_cursor
sid_frame_events:
    test dl, 1
    jz sid_frame_voice2
.if SID_MODE >= 4
    call sid_score_byte
    mov dh, al
    call sid_score_byte
    mov ah, al
    mov al, dh
.else
    mov al, [si]
    inc si
    mov ah, [si]
    inc si
.endif
    mov bl, 1
    call sid_voice
sid_frame_voice2:
    test dl, 2
    jz sid_frame_voice3
.if SID_MODE >= 4
    call sid_score_byte
    mov dh, al
    call sid_score_byte
    mov ah, al
    mov al, dh
.else
    mov al, [si]
    inc si
    mov ah, [si]
    inc si
.endif
    mov bl, 2
    call sid_voice
sid_frame_voice3:
    test dl, 4
    jz sid_save_cursor
.if SID_MODE >= 4
    call sid_score_byte
    mov dh, al
    call sid_score_byte
    mov ah, al
    mov al, dh
.else
    mov al, [si]
    inc si
    mov ah, [si]
    inc si
.endif
    mov bl, 3
    call sid_voice
sid_save_cursor:
    mov [sid_cursor], si
sid_tick_done:
    ret

.if SID_MODE >= 4
# Return the next byte in AL. Crossing byte 60000 switches to score block 1.
sid_score_byte:
    mov al, es:[si]
    inc si
    cmp si, 60000
    jne sid_score_byte_done
    cmp byte ptr [sid_bank], 0
    jne sid_score_byte_done
    mov byte ptr [sid_bank], 1
    push ax
    mov ax, [score_seg1]
    mov es, ax
    pop ax
    xor si, si
sid_score_byte_done:
    ret
.endif

# AL=tone, AH=active/noise/octave (and envelope level in mode 3).
# BL identifies SID voice 1..3.
sid_voice:
.if SID_MODE >= 2
    jmp sid_voice_clocked_noise
.else
    push ax
    push bx
    push cx
    push dx
    mov [sid_voice_tone], al
    mov [sid_voice_state], ah
    mov al, bl
    add al, 8
    mov ah, [sid_voice_tone]
    call cms_write
    mov cl, [sid_voice_state]
    and cl, 7
    cmp bl, 1
    jne sid_octave_23
    shl cl, 1
    shl cl, 1
    shl cl, 1
    shl cl, 1
    mov ah, [sid_oct01]
    and ah, 0x0f
    or ah, cl
    mov [sid_oct01], ah
    mov al, 0x10
    call cms_write
    jmp sid_update_masks
sid_octave_23:
    cmp bl, 3
    jne sid_octave_2
    shl cl, 1
    shl cl, 1
    shl cl, 1
    shl cl, 1
    mov ah, [sid_oct23]
    and ah, 0x0f
    or ah, cl
    jmp sid_write_oct23
sid_octave_2:
    mov ah, [sid_oct23]
    and ah, 0xf0
    or ah, cl
sid_write_oct23:
    mov [sid_oct23], ah
    mov al, 0x11
    call cms_write
sid_update_masks:
    xor bh, bh
    mov cl, [sid_bit_table + bx]
    mov ch, cl
    not ch
    and [sid_freq_mask], ch
    and [sid_noise_mask], ch
    mov dh, [sid_voice_state]
    test dh, 0x80
    jz sid_write_masks
    test dh, 0x40
    jz sid_tone_enable
    or [sid_noise_mask], cl
    jmp sid_write_masks
sid_tone_enable:
    or [sid_freq_mask], cl
sid_write_masks:
    mov al, 0x14
    mov ah, [sid_freq_mask]
    call cms_write
    mov al, 0x15
    mov ah, [sid_noise_mask]
    call cms_write
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.endif

.if SID_MODE >= 2
# Voice 1 uses chip 0 channel 3; voices 2/3 use chip 1 channels 0/3.
# Each channel can clock its own noise generator through register 16h.
sid_voice_clocked_noise:
    push ax
    push bx
    push cx
    push dx
    mov [sid_voice_tone], al
    mov [sid_voice_state], ah
.if SID_MODE >= 3
    # The score stores a three-bit envelope level in state bits 3-5.
    mov al, ah
    and al, 0x38
    shr al, 1
    shr al, 1
    shr al, 1
    push bx
    xor bh, bh
    mov bl, al
    mov ah, [sid_volume_table + bx]
    pop bx
.if SID_MODE == 5
    push bx
    xor bh, bh
    dec bl
    mov [sid_current_volumes + bx], ah
    pop bx
    cmp byte ptr [sid_music_enabled], 0
    jne sid_volume_active
    xor ah, ah
sid_volume_active:
.endif
    cmp bl, 1
    jne sid_volume_second_chip
    mov al, 0x03
    call cms_write
    jmp sid_volume_done
sid_volume_second_chip:
    mov al, 0x00
    cmp bl, 2
    je sid_volume_write_second
    mov al, 0x03
sid_volume_write_second:
    call cms_write_second
sid_volume_done:
.endif
    cmp bl, 1
    jne sid_second_chip
    mov al, 0x0b
    mov ah, [sid_voice_tone]
    call cms_write
    mov cl, [sid_voice_state]
    and cl, 7
    shl cl, 1
    shl cl, 1
    shl cl, 1
    shl cl, 1
    mov ah, [sid_oct23]
    and ah, 0x0f
    or ah, cl
    mov [sid_oct23], ah
    mov al, 0x11
    call cms_write
    and byte ptr [sid_freq_mask], 0xf7
    mov byte ptr [sid_noise_mask], 0
    mov dl, [sid_voice_state]
    test dl, 0x80
    jz sid_first_masks
    test dl, 0x40
    jz sid_first_tone
    mov byte ptr [sid_noise_mask], 8
    jmp sid_first_masks
sid_first_tone:
    or byte ptr [sid_freq_mask], 8
sid_first_masks:
    mov al, 0x14
    mov ah, [sid_freq_mask]
    call cms_write
    mov al, 0x15
    mov ah, [sid_noise_mask]
    call cms_write
    jmp sid_clocked_done

sid_second_chip:
    cmp bl, 2
    jne sid_third_voice
    mov bl, 1
    mov al, 0x08
    mov ah, [sid_voice_tone]
    call cms_write_second
    mov cl, [sid_voice_state]
    and cl, 7
    mov ah, [sid_second_oct01]
    and ah, 0xf0
    or ah, cl
    mov [sid_second_oct01], ah
    mov al, 0x10
    call cms_write_second
    jmp sid_second_masks
sid_third_voice:
    mov bl, 8
    mov al, 0x0b
    mov ah, [sid_voice_tone]
    call cms_write_second
    mov cl, [sid_voice_state]
    and cl, 7
    shl cl, 1
    shl cl, 1
    shl cl, 1
    shl cl, 1
    mov ah, [sid_second_oct23]
    and ah, 0x0f
    or ah, cl
    mov [sid_second_oct23], ah
    mov al, 0x11
    call cms_write_second
sid_second_masks:
    mov cl, bl
    not cl
    and [sid_second_freq_mask], cl
    and [sid_second_noise_mask], cl
    mov dl, [sid_voice_state]
    test dl, 0x80
    jz sid_write_second_masks
    test dl, 0x40
    jz sid_second_tone
    or [sid_second_noise_mask], bl
    jmp sid_write_second_masks
sid_second_tone:
    or [sid_second_freq_mask], bl
sid_write_second_masks:
    mov al, 0x14
    mov ah, [sid_second_freq_mask]
    call cms_write_second
    mov al, 0x15
    mov ah, [sid_second_noise_mask]
    call cms_write_second
sid_clocked_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.endif
.endif

old60: .word 0, 0
old61: .word 0, 0
.if SID_MODE
old62: .word 0, 0
.if SID_MODE == 5
old63: .word 0, 0
.endif
game_tick_ptr: .word 0x69a5, 0
.if SID_MODE >= 4
sid_cursor: .word 0
sid_bank: .byte 0
score_seg0: .word 0
score_seg1: .word 0
score_handle: .word 0
.else
sid_cursor: .word sid_score
.endif
sid_phase: .byte 0
sid_skip: .byte 0
sid_freq_mask: .byte 0
sid_noise_mask: .byte 0
sid_oct01: .byte 0
sid_oct23: .byte 0
sid_voice_tone: .byte 0
sid_voice_state: .byte 0
sid_bit_table: .byte 0, 2, 4, 8
.if SID_MODE >= 2
sid_second_freq_mask: .byte 0
sid_second_noise_mask: .byte 0
sid_second_oct01: .byte 0
sid_second_oct23: .byte 0
.endif
.if SID_MODE >= 3
sid_volume_table: .byte 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x77, 0x99
.endif
.if SID_MODE == 5
sid_music_enabled: .byte 1
sid_current_volumes: .byte 0x99, 0x99, 0x99
.endif
.endif
pitch_phase: .byte 0
pitch_low: .byte 0
exit_code: .byte 0
game_name: .asciz "STARTC0.COM"
.if SID_MODE
.if SID_MODE == 5
test_message: .ascii "CODEX SID CMS: M toggles CMS music...\r\n$"
.elseif SID_MODE == 4
test_message: .ascii "CODEX SID CMS: full envelope score...\r\n$"
.elseif SID_MODE == 3
test_message: .ascii "CODEX SID CMS: envelope test...\r\n$"
.elseif SID_MODE == 2
test_message: .ascii "CODEX SID CMS: clocked noise test...\r\n$"
.else
test_message: .ascii "CODEX SID CMS: C64 arrangement...\r\n$"
.endif
.else
test_message: .ascii "CODEX CMS: test tone, then Commando...\r\n$"
.endif
game_error_text: .ascii "Unable to start STARTC0.COM.$"
memory_error_text: .ascii "Unable to release DOS memory.$"
.if SID_MODE >= 4
score_name: .asciz "SIDENV.BIN"
score_error_text: .ascii "Unable to load SIDENV.BIN (memory, missing file, or wrong size).$"
.endif

# DOS EXEC parameter block. Use this process's PSP command tail and FCBs.
exec_block:
    .word 0
    .word 0x80, 0
    .word 0x5c, 0
    .word 0x6c, 0

.if SID_MODE && SID_MODE < 4
sid_score:
.if SID_MODE == 3
    .incbin "tools/SidDump/sidmusic-envelope-4m.bin"
.else
    .incbin "tools/SidDump/sidmusic.bin"
.endif
.endif

    .balign 16
stack_space:
    .space 1024
stack_top:
