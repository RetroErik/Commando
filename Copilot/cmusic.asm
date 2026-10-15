; Commando AdLib launcher, 8086-compatible.
; By Dag Erik Hagesæter / Retro Erik.
bits 16
cpu 8086
org 100h

%ifdef MUSIC_TEST
    jmp test_entry
%else
    jmp start
%endif

old_timer       dd 0
saved_ss        dw 0
saved_sp        dw 0
exit_code       db 0
launch_error    dw 0
music_enabled  db 1
preview_mode   db 0
game_muted     db 0
game_recognized db 0
effect_hook_segment dw 0
audio_resume    dw 69aah, 0
effect_active  db 0
effect_source  dw 0
effect_cursor  dw 0
effect_divisor dw 0
effect_ticks   dw 0
effect_seen    dw 0
effect_updates dw 0
effect_enabled_ticks dw 0
effect_preview_tick db 0
gun_noise_ticks db 0
game_music_mode db 0
game_music_on db 0
game_music_divisor dw 0
music_resume dw 685fh, 0
game_music_events dw 0
ticks_left     db 1
song_position  dw song
child_name     db 'STARTC.COM', 0
command_tail   db 0, 13
exec_block:
    dw 0
    dw command_tail, 0
    dw 5ch, 0
    dw 6ch, 0

timer_handler:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    push cs
    pop ds
    call sync_game_music
    cmp byte [preview_mode], 2
    je .effects_preview
    call music_tick
    jmp .restore
.effects_preview:
    call preview_effect_tick
.restore:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    jmp far [cs:old_timer]

music_tick:
    cmp byte [preview_mode], 1
    jne .done
    cmp byte [game_muted], 0
    jne .done
    dec byte [ticks_left]
    jz .row
    cmp byte [ticks_left], 2
    jne .done
    mov ax, 00b2h
    call opl_write
.done:
    ret
.row:
    mov byte [ticks_left], 3
    mov si, [song_position]
    xor bx, bx
    mov al, [si]
    call play_note
    inc bx
    mov al, [si+1]
    call play_note
    inc bx
    mov al, [si+2]
    call play_note
    add si, 3
    cmp si, song_end
    jb .save
    mov si, song
.save:
    mov [song_position], si
    ret

sync_game_music:
    cmp byte [preview_mode], 0
    jne .done
    xor ax, ax
    mov es, ax
    les bx, [es:20h]
    call probe_game_timer
    jc .unknown
    mov byte [game_recognized], 1
    push ax
    call suppress_speaker_music
    call install_effect_bridge
    call install_game_music
    pop ax
    call apply_game_music_state
.done:
    ret
.unknown:
    call stop_game_music
    call stop_gun_noise
    cmp byte [effect_active], 0
    je .done
    mov ax, 00b3h
    call opl_write
    mov byte [effect_active], 0
    ret

; ES:BX is the current IRQ0 entry. Never cache a pointer into the child.
probe_game_timer:
    cmp bx, 8284h
    jne .unknown
    cmp word [es:8284h], 1e50h
    jne .unknown
    cmp word [es:8286h], 0b806h
    jne .unknown
    cmp word [es:824ch], 0650h
    jne .unknown
    cmp word [es:824eh], 0c033h
    jne .unknown
    cmp word [es:8250h], 0c08eh
    jne .unknown
    cmp word [es:8252h], 20bbh
    jne .unknown
    cmp word [es:66c1h], 0c033h
    jne .unknown
    cmp word [es:66c3h], 0a02eh
    jne .unknown
    cmp word [es:66c5h], 6583h
    jne .unknown
    cmp word [es:66c7h], 0c00bh
    jne .unknown
    cmp word [es:6874h], 382eh
    jne .unknown
    cmp word [es:6876h], 830eh
    jne .unknown
    cmp byte [es:6878h], 65h
    jne .unknown
    cmp word [es:6879h], 1d74h
    je .recognized
    cmp word [es:6879h], 1debh
    jne .unknown
.recognized:
    cmp word [es:698ah], 61e4h
    jne .unknown
    cmp word [es:698ch], 030ch
    je .effect_gate_ok
    cmp word [es:698ch], 0fc24h
    jne .unknown
.effect_gate_ok:
    cmp word [es:69aah], 0c0feh
    jne .unknown
    cmp word [es:69ach], 0124h
    jne .unknown
    cmp byte [es:69a5h], 50h
    jne .installed
    cmp word [es:69a6h], 0a02eh
    jne .unknown
    cmp word [es:69a8h], 6580h
    jne .unknown
    jmp .profile_ok
.installed:
    cmp byte [es:69a5h], 0eah
    jne .unknown
    cmp word [es:69a6h], effect_bridge
    jne .unknown
    mov ax, cs
    cmp [es:69a8h], ax
    jne .unknown
.profile_ok:
    mov al, [es:6583h]
    clc
    ret
.unknown:
    stc
    ret

; The original update is called at every game IRQ, not just the BIOS tick.
install_effect_bridge:
    pushf
    cli
    mov word [es:698ch], 0fc24h
    cmp byte [es:69a5h], 0eah
    je .done
    mov ax, es
    mov [effect_hook_segment], ax
    mov [audio_resume+2], ax
    mov word [es:69a6h], effect_bridge
    mov ax, cs
    mov [es:69a8h], ax
    mov byte [es:69a5h], 0eah
    call stop_speaker
.done:
    popf
    ret

effect_bridge:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    push cs
    pop ds
    mov es, [effect_hook_segment]
    call update_game_music
    call update_effect
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ; Reproduce the displaced PUSH AX / MOV AL,CS:[6580h], then continue.
    push ax
    push ds
    push ax
    mov ax, [cs:effect_hook_segment]
    mov ds, ax
    pop ax
    mov al, [6580h]
    pop ds
    jmp far [cs:audio_resume]

install_game_music:
    cmp byte [es:685ah], 0eah
    jne .original
    cmp word [es:685bh], game_music_bridge
    jne .done
    mov ax, cs
    cmp word [es:685dh], ax
    jne .done
    ret
.original:
    cmp word [es:685ah], 8b2eh
    jne .done
    cmp word [es:685ch], 0da84h
    jne .done
    cmp byte [es:685eh], 65h
    jne .done
    cmp word [es:685fh], 0c00bh
    jne .done
    cmp word [es:6861h], 1175h
    jne .done
    pushf
    cli
    mov ax, es
    mov [music_resume+2], ax
    mov word [es:685bh], game_music_bridge
    mov ax, cs
    mov [es:685dh], ax
    mov byte [es:685ah], 0eah
    mov byte [game_music_mode], 1
    mov ax, 00b0h
    call opl_write
    inc al
    call opl_write
    inc al
    call opl_write
    popf
.done:
    ret

; Capture the game's resolved pitch, not a transcription of its song resources.
game_music_bridge:
    pushf
    cli
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    push cs
    pop ds
    mov es, [effect_hook_segment]
    mov ax, [es:si+65dah]
    push ax
    call capture_game_music_note
    pop ax
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    popf
    jmp far [cs:music_resume]

capture_game_music_note:
    mov [game_music_divisor], ax
    inc word [game_music_events]
    call stop_game_music
    cmp byte [es:6583h], 0
    je .done
    call render_game_music
.done:
    ret

update_game_music:
    cmp byte [game_music_mode], 0
    je .done
    cmp byte [es:6583h], 0
    je .off
    cmp word [es:6581h], 0
    je .off
    cmp byte [es:6585h], 2
    jne .off
    cmp byte [game_music_on], 0
    jne .done
    call render_game_music
.done:
    ret
.off:
    jmp stop_game_music

render_game_music:
    mov ax, [game_music_divisor]
    or ax, ax
    jz .done
    xor bx, bx
    call render_opl_pitch
    mov byte [game_music_on], 1
.done:
    ret

stop_game_music:
    cmp byte [game_music_on], 0
    je .done
    mov ax, 00b0h
    call opl_write
    mov byte [game_music_on], 0
.done:
    ret

update_effect:
    inc word [effect_ticks]
    call tick_gun_noise
    cmp byte [es:6590h], 0
    je .stop
    inc word [effect_enabled_ticks]
    mov si, [es:658ch]
    or si, si
    jz .stop
    inc word [effect_seen]
    mov di, [es:6593h]
    cmp di, si
    je .stop
    mov ax, [es:658eh]
    or ax, ax
    jz .stop
    mov dx, ax
    cmp byte [effect_active], 0
    je .trigger
    cmp si, [effect_source]
    jne .trigger
    cmp di, [effect_cursor]
    jb .trigger
    cmp dx, [effect_divisor]
    jne .pitch
    mov [effect_cursor], di
    ret
.trigger:
    mov ax, 00b3h
    call opl_write
    call start_gun_noise
.pitch:
    inc word [effect_updates]
    mov [effect_source], si
    mov [effect_cursor], di
    mov [effect_divisor], dx
    mov ax, dx
    call render_gun_pitch
    mov byte [effect_active], 1
    ret
.stop:
    call stop_gun_noise
    cmp byte [effect_active], 0
    je .done
    mov ax, 00b3h
    call opl_write
    mov byte [effect_active], 0
.done:
    ret

start_gun_noise:
    mov ax, 20bdh
    call opl_write
    mov ax, 28bdh
    call opl_write
    mov byte [gun_noise_ticks], 7
    ret

tick_gun_noise:
    cmp byte [gun_noise_ticks], 0
    je .done
    dec byte [gun_noise_ticks]
    jnz .done
    mov ax, 20bdh
    call opl_write
.done:
    ret

stop_gun_noise:
    cmp byte [gun_noise_ticks], 0
    je .done
    mov byte [gun_noise_ticks], 0
    mov ax, 20bdh
    call opl_write
.done:
    ret

render_gun_pitch:
    cmp ax, 4095
    ja .clamp
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    jmp render_effect_pitch
.clamp:
    mov ax, 65535
render_effect_pitch:
    mov bl, 3
render_opl_pitch:
    push bx
    call divisor_to_opl
    pop bx
    mov dh, ah
    mov ah, al
    mov al, bl
    add al, 0a0h
    call opl_write
    mov ah, dh
    or ah, cl
    or ah, 20h
    mov al, bl
    add al, 0b0h
    call opl_write
    ret

preview_effect_tick:
    mov al, [effect_preview_tick]
    cmp al, 0
    je .shot
    cmp al, 2
    je .off
    jmp .advance
.off:
    call stop_gun_noise
    mov ax, 00b3h
    call opl_write
    jmp .advance
.shot:
    call start_gun_noise
    mov ax, 00b3h
    call opl_write
    mov ax, 397
    call render_gun_pitch
    jmp .advance
.advance:
    mov cx, 6
.noise_tick:
    push cx
    call tick_gun_noise
    pop cx
    loop .noise_tick
    inc byte [effect_preview_tick]
    cmp byte [effect_preview_tick], 9
    jb .done
    mov byte [effect_preview_tick], 0
.done:
    ret

; AX = nonzero PIT divisor; AX = OPL f-number, CL = block bits.
; PIT/OPL frequency ratio is approximately 24, within 0.01 percent.
divisor_to_opl:
    mov bx, ax
    mov cx, 7
    mov si, 0
    mov di, 3
    cmp bx, 193
    jae .convert
    mov ax, 1023
    jmp .block
.convert:
    mov ax, si
    mov dx, di
    div bx
    cmp ax, 512
    jae .block
    jcxz .block
    shl si, 1
    rcl di, 1
    dec cx
    jmp .convert
.block:
    shl cl, 1
    shl cl, 1
    ret

; Skip only the music-to-speaker output branch; its sequencer and M flag remain.
suppress_speaker_music:
    cmp byte [es:6879h], 0ebh
    je .done
    mov byte [es:6879h], 0ebh
    cmp word [es:658ch], 0
    jne .done
    call stop_speaker
.done:
    ret

stop_speaker:
    push ax
    in al, 61h
    and al, 0fch
    out 61h, al
    pop ax
    ret

apply_game_music_state:
    or al, al
    jnz .enabled
    cmp byte [game_muted], 0
    jne .done
    mov byte [game_muted], 1
    mov ax, 00b0h
    call opl_write
    inc al
    call opl_write
    inc al
    call opl_write
    ret
.enabled:
    cmp byte [game_muted], 0
    je .done
    mov byte [game_muted], 0
    mov byte [ticks_left], 1
.done:
    ret

; AL = note (1 = C2, 0 = rest), BL = melodic channel.
play_note:
    push ax
    push bx
    push cx
    push dx
    push si
    mov cl, al
    mov al, bl
    add al, 0b0h
    xor ah, ah
    call opl_write
    mov al, cl
    or al, al
    jz .done
    dec al
    xor ah, ah
    mov cl, 12
    div cl
    mov ch, al
    mov al, ah
    xor ah, ah
    mov si, ax
    shl si, 1
    mov dx, [f_numbers+si]
    mov ah, dl
    mov al, bl
    add al, 0a0h
    call opl_write
    mov ah, dh
    mov al, ch
    add al, 2
    shl al, 1
    shl al, 1
    or ah, al
    or ah, 20h
    mov al, bl
    add al, 0b0h
    call opl_write
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; AL = register, AH = value. Read delays also work on fast CPUs.
opl_write:
    push ax
    push cx
    push dx
    mov dx, 388h
    out dx, al
    mov cx, 6
.address_delay:
    in al, dx
    loop .address_delay
    inc dx
    mov al, ah
    out dx, al
    dec dx
    mov cx, 35
.data_delay:
    in al, dx
    loop .data_delay
    pop dx
    pop cx
    pop ax
%ifdef MUSIC_TEST
    push bx
    xor bx, bx
    mov bl, al
    mov [test_registers+bx], ah
    inc word [test_writes]
    pop bx
%endif
    ret

detect_adlib:
    push bx
    push cx
    push dx
    mov ax, 6004h
    call opl_write
    mov ax, 8004h
    call opl_write
    mov dx, 388h
    in al, dx
    and al, 0e0h
    mov bl, al
    mov ax, 0ff02h
    call opl_write
    mov ax, 2104h
    call opl_write
    mov cx, 200
.wait:
    in al, dx
    loop .wait
    and al, 0e0h
    mov bh, al
    mov ax, 6004h
    call opl_write
    mov ax, 8004h
    call opl_write
    cmp bl, 0
    jne .missing
    cmp bh, 0c0h
    jne .missing
    clc
    jmp .done
.missing:
    stc
.done:
    pop dx
    pop cx
    pop bx
    ret

init_music:
    call silence
    mov si, instruments
.next:
    mov ax, [si]
    call opl_write
    add si, 2
    cmp si, instruments_end
    jb .next
    mov byte [ticks_left], 1
    mov word [song_position], song
    ret

silence:
    mov ax, 00bdh
    call opl_write
    mov al, 0b0h
.channel:
    call opl_write
    inc al
    cmp al, 0b9h
    jb .channel
    mov si, carrier_offsets
.carrier:
    mov al, [si]
    add al, 40h
    mov ah, 3fh
    call opl_write
    inc si
    cmp si, carrier_offsets_end
    jb .carrier
    ret

install_timer:
    mov ax, 351ch
    int 21h
    mov [old_timer], bx
    mov [old_timer+2], es
    mov dx, timer_handler
    mov ax, 251ch
    int 21h
    ret

remove_timer:
    push ds
    lds dx, [old_timer]
    mov ax, 251ch
    int 21h
    pop ds
    call silence
    ret

start:
    cld
    mov si, 81h
    xor cx, cx
    mov cl, [80h]
.skip_space:
    jcxz .arguments_done
    lodsb
    dec cx
    cmp al, ' '
    je .skip_space
    cmp al, '/'
    jne usage_error
    or cx, cx
    jz usage_error
    lodsb
    dec cx
    cmp al, '?'
    je .help
    and al, 0dfh
    cmp al, 'N'
    je .no_music
    cmp al, 'P'
    je .preview
    cmp al, 'E'
    je .effects_preview
    cmp al, 'H'
    je .help
    jmp usage_error
.no_music:
    mov byte [music_enabled], 0
    jmp .trailing
.preview:
    mov byte [preview_mode], 1
    jmp .trailing
.effects_preview:
    mov byte [preview_mode], 2
.trailing:
    jcxz .arguments_done
    lodsb
    dec cx
    cmp al, ' '
    jne usage_error
    jmp .trailing
.help:
    mov dx, help_text
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
.arguments_done:
    mov dx, banner
    mov ah, 9
    int 21h
    cmp byte [preview_mode], 0
    jne .hardware
    mov dx, child_name
    call check_file
    jc file_error
    mov dx, game_name
    call check_file
    jc file_error
    mov dx, data_name
    call check_file
    jc file_error
.hardware:
    cmp byte [music_enabled], 0
    je .execute
    call detect_adlib
    jc hardware_error
    call init_music
    call install_timer
    cmp byte [preview_mode], 0
    jne preview
.execute:
    mov ax, cs
    mov es, ax
    mov [exec_block+4], ax
    mov [exec_block+8], ax
    mov [exec_block+12], ax
    cli
    mov ss, ax
    mov sp, stack_top
    sti
    mov bx, (program_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc memory_error
    mov [saved_ss], ss
    mov [saved_sp], sp
    mov dx, child_name
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    ; Old DOS versions need the parent's stack restored after EXEC.
    cli
    mov ss, [cs:saved_ss]
    mov sp, [cs:saved_sp]
    sti
    push cs
    pop ds
    push cs
    pop es
    jc .exec_failed
    mov ah, 4dh
    int 21h
    mov [exit_code], al
    call cleanup
    cmp byte [music_enabled], 0
    je .returned
    cmp byte [game_recognized], 0
    je .unrecognized
    mov dx, synchronized_text
    jmp .status
.unrecognized:
    mov dx, unrecognized_text
.status:
    mov ah, 9
    int 21h
.returned:
    cmp byte [music_enabled], 0
    je .return_message
    mov dx, effect_diagnostic_text
    mov ah, 9
    int 21h
    mov ax, [effect_ticks]
    call print_number
    mov dx, diagnostic_enabled_text
    mov ah, 9
    int 21h
    mov ax, [effect_enabled_ticks]
    call print_number
    mov dx, diagnostic_seen_text
    mov ah, 9
    int 21h
    mov ax, [effect_seen]
    call print_number
    mov dx, diagnostic_updates_text
    mov ah, 9
    int 21h
    mov ax, [effect_updates]
    call print_number
    mov dx, diagnostic_music_text
    mov ah, 9
    int 21h
    mov ax, [game_music_events]
    call print_number
    mov dx, newline
    mov ah, 9
    int 21h
.return_message:
    cmp byte [game_recognized], 0
    je .return_status
    cmp byte [game_music_mode], 0
    jne .return_status
    mov dx, music_warning_text
    mov ah, 9
    int 21h
.return_status:
    mov dx, returned_text
    mov ah, 9
    int 21h
    mov al, [exit_code]
    mov ah, 4ch
    int 21h
.exec_failed:
    mov [launch_error], ax
    call cleanup
    mov dx, exec_error_text
    mov ah, 9
    int 21h
    mov ax, [launch_error]
    call print_number
    mov dx, newline
    jmp fail

check_file:
    mov ax, 3d00h
    int 21h
    jc .done
    mov bx, ax
    mov ah, 3eh
    int 21h
.done:
    ret

preview:
    mov dx, preview_text
    cmp byte [preview_mode], 2
    jne .message
    mov dx, effect_preview_text
.message:
    mov ah, 9
    int 21h
    xor ax, ax
    int 16h
    call remove_timer
    mov dx, preview_done_text
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

cleanup:
    call stop_speaker
    cmp byte [music_enabled], 0
    je .done
    call remove_timer
.done:
    ret

memory_error:
    call cleanup
    mov dx, memory_error_text
    jmp fail
file_error:
    mov dx, file_error_text
    jmp fail
hardware_error:
    mov dx, hardware_error_text
    jmp fail
usage_error:
    mov dx, help_text
fail:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

print_number:
    xor cx, cx
    mov bx, 10
.digit:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .digit
.print:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop .print
    ret

f_numbers dw 343, 363, 385, 408, 432, 458, 485, 514, 544, 577, 611, 647
carrier_offsets db 3, 4, 5, 11, 12, 13, 19, 20, 21
carrier_offsets_end:

instruments:
    db 01h,20h, 08h,00h
    ; Lead: restrained FM brass, bass: plucked pulse, percussion: short FM hit.
    db 20h,21h, 23h,21h, 40h,1ch, 43h,14h
    db 60h,0f2h, 63h,0f2h, 80h,74h, 83h,75h
    db 0e0h,00h, 0e3h,00h, 0c0h,04h
    db 21h,21h, 24h,21h, 41h,18h, 44h,1ah
    db 61h,0f3h, 64h,0f3h, 81h,85h, 84h,85h
    db 0e1h,00h, 0e4h,00h, 0c1h,02h
    db 22h,0fh, 25h,01h, 42h,00h, 45h,20h
    db 62h,0f8h, 65h,0f8h, 82h,0ffh, 85h,0ffh
    db 0e2h,00h, 0e5h,00h, 0c2h,0eh
    ; Additive mode exposes the maximum-feedback burst beside the low body.
    db 28h,20h, 2bh,20h, 48h,00h, 4bh,08h
    db 68h,0fah, 6bh,0f8h, 88h,0fh, 8bh,6fh
    db 0e8h,00h, 0ebh,00h, 0c3h,0fh
    db 31h,21h, 51h,00h, 71h,0f8h, 91h,0fh, 0f1h,00h
    db 34h,21h, 54h,04h, 74h,0fah, 94h,0fh, 0f4h,00h
    db 0a7h,00h, 0b7h,11h, 0bdh,20h
instruments_end:

; Original composition "Night Patrol": eight 16-step phrases, not arcade music.
%macro phrase 17
    %assign root %1
    %rotate 1
    %assign step 0
    %rep 16
        db %1
        %if (step % 4) = 0
            db root, 1
        %elif (step % 4) = 2
            db root+7, 8
        %else
            db 0, 0
        %endif
        %rotate 1
        %assign step step+1
    %endrep
%endmacro

song:
    phrase 1,  25,0,28,32, 30,28,25,0, 32,0,35,32, 30,28,27,0
    phrase 9,  28,0,32,35, 33,32,28,0, 32,33,35,0, 33,32,30,0
    phrase 11, 30,0,33,37, 35,33,30,0, 33,35,37,35, 33,30,27,0
    phrase 8,  27,0,30,32, 35,32,30,0, 27,30,32,30, 27,24,25,0
    phrase 1,  37,0,35,32, 30,32,28,0, 25,28,32,35, 37,35,32,0
    phrase 9,  33,0,32,28, 32,35,40,0, 40,37,35,32, 33,32,28,0
    phrase 11, 37,0,35,33, 30,33,35,0, 37,35,33,30, 33,30,27,0
    phrase 8,  32,0,30,27, 24,27,30,0, 32,30,27,24, 25,0,25,0
song_end:

banner db 'Commando AdLib audio launcher 0.7',13,10
       db 'By Dag Erik Hages',91h,'ter / Retro Erik',13,10,'$'
help_text db 'CMUSIC       Original game music and gunfire through AdLib.',13,10
          db 'CMUSIC /N    Start without AdLib hooks (comparison).',13,10
          db 'CMUSIC /P    Preview Night Patrol; any key stops.',13,10
          db 'CMUSIC /E    Preview AdLib gunfire; any key stops.',13,10
          db 'CMUSIC /?    Show help.',13,10
          db 'Run from the Commando directory. Press Q to leave the game.',13,10,'$'
file_error_text db 'ERROR: Cannot read STARTC.COM, COMMANDO.EXE or COMMANDO.DAT.',13,10,'$'
hardware_error_text db 'ERROR: AdLib/OPL hardware not detected at 388h. Use /N for no music.',13,10,'$'
memory_error_text db 'ERROR: Cannot release memory for the game.',13,10,'$'
exec_error_text db 'ERROR: Cannot launch STARTC.COM. DOS error: $'
preview_text db 'Playing Night Patrol. Press any key to stop.',13,10,'$'
effect_preview_text db 'AdLib gunfire preview. Any key stops.',13,10,'$'
preview_done_text db 'Preview ended; audio stopped and timer restored.',13,10,'$'
returned_text db 'Game returned; launcher cleanup completed.',13,10,'$'
unrecognized_text db 'WARNING: Game audio profile not recognized; original music conversion unavailable.',13,10,'$'
synchronized_text db 'Game music controls and AdLib effects synchronized.',13,10,'$'
effect_diagnostic_text db 'Effects: ticks=$'
diagnostic_enabled_text db ' enabled=$'
diagnostic_seen_text db ' active=$'
diagnostic_updates_text db ' updates=$'
diagnostic_music_text db ' music-notes=$'
music_warning_text db 'WARNING: Original music hook not recognized; no replacement song is played.',13,10,'$'
game_name db 'COMMANDO.EXE',0
data_name db 'COMMANDO.DAT',0
newline db 13,10,'$'

%ifdef MUSIC_TEST
    %include "test\player-test.inc"
%endif

align 16
stack_bottom:
    times 512 db 0
stack_top:
program_end:
