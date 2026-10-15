test_registers times 256 db 0
test_writes dw 0
test_chains dw 0
test_before dw 0
test_saved_timer dd 0
test_pass_text db 'PASS: detection, notes, rests, percussion, 128 rows, loop, registers, chaining, timer restore.',13,10,'$'
test_sync_text db 'PASS: game recognition, mismatched code rejection, mute, frozen position, resume, preview isolation.',13,10,'$'
test_speaker_text db 'PASS: guarded speaker music suppression, active effects preserved, speaker exit cleanup.',13,10,'$'
test_effect_text db 'PASS: effects pitch conversion, retrigger, sweep, S mute, independent music mute, guarded live hook.',13,10,'$'
test_game_music_text db 'PASS: live music capture, original pitch, repeated notes, rests, note gaps, sequence end, M mute, no replacement song.',13,10,'$'
test_fail_text db 'FAIL: player regression test.',13,10,'$'

test_chain:
    inc word [cs:test_chains]
    iret

test_music_continue:
    ret

test_entry:
    cld
    push cs
    pop es
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    sti
    mov bx, (program_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc test_fail
    mov byte [preview_mode], 1
    call detect_adlib
    jc test_fail
    call init_music
    mov word [old_timer], test_chain
    mov [old_timer+2], cs
    mov ax, 1234h
    mov bx, 5678h
    mov cx, 9abch
    mov dx, 0def0h
    mov si, 1357h
    mov di, 2468h
    mov bp, 3579h
    push cs
    pop es
    std
    pushf
    push cs
    call timer_handler
    pushf
    cmp ax, 1234h
    jne test_fail
    cmp bx, 5678h
    jne test_fail
    cmp cx, 9abch
    jne test_fail
    cmp dx, 0def0h
    jne test_fail
    cmp si, 1357h
    jne test_fail
    cmp di, 2468h
    jne test_fail
    cmp bp, 3579h
    jne test_fail
    mov ax, es
    mov bx, cs
    cmp ax, bx
    jne test_fail
    pop ax
    test ax, 400h
    jz test_fail
    cld
    cmp word [test_chains], 1
    jne test_fail
    cmp word [song_position], song+3
    jne test_fail
    cmp byte [test_registers+0a0h], 57h
    jne test_fail
    cmp byte [test_registers+0b0h], 31h
    jne test_fail
    cmp byte [test_registers+0b1h], 29h
    jne test_fail
    cmp byte [test_registers+0b2h], 29h
    jne test_fail
    call music_tick
    cmp byte [test_registers+0b2h], 0
    jne test_fail
    call music_tick
    call music_tick
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    cmp byte [test_registers+0b1h], 0
    jne test_fail
    cmp word [song_position], song+6
    jne test_fail
    mov cx, 378
.loop:
    push cx
    call music_tick
    pop cx
    loop .loop
    cmp word [song_position], song
    jne test_fail
    mov ax, [test_writes]
    mov [test_before], ax
    call music_tick
    call music_tick
    cmp word [song_position], song
    jne test_fail
    call music_tick
    cmp word [song_position], song+3
    jne test_fail
    mov ax, [test_writes]
    cmp ax, [test_before]
    jbe test_fail
    mov ax, 351ch
    int 21h
    mov [test_saved_timer], bx
    mov [test_saved_timer+2], es
    call install_timer
    call remove_timer
    mov ax, 351ch
    int 21h
    cmp bx, [test_saved_timer]
    jne test_fail
    mov ax, es
    cmp ax, [test_saved_timer+2]
    jne test_fail
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    cmp byte [test_registers+43h], 3fh
    jne test_fail
    call init_music
    push cs
    pop es
    mov bx, 8283h
    call probe_game_timer
    jnc test_fail
    mov bx, 8284h
    mov word [es:66c5h], 6582h
    call probe_game_timer
    jnc test_fail
    mov word [es:66c5h], 6583h
    mov byte [es:6879h], 75h
    call probe_game_timer
    jnc test_fail
    mov byte [es:6879h], 74h
    mov byte [es:6583h], 1
    call probe_game_timer
    jc test_fail
    cmp al, 1
    jne test_fail
    mov word [es:658ch], 1
    in al, 61h
    or al, 3
    out 61h, al
    call suppress_speaker_music
    cmp byte [es:6879h], 0ebh
    jne test_fail
    in al, 61h
    and al, 3
    cmp al, 3
    jne test_fail
    mov word [es:658ch], 0
    mov byte [es:6879h], 74h
    call suppress_speaker_music
    in al, 61h
    and al, 3
    jne test_fail
    call probe_game_timer
    jc test_fail
    cmp al, 1
    jne test_fail
    call apply_game_music_state
    call music_tick
    mov byte [es:6583h], 0
    mov bx, 8284h
    call probe_game_timer
    jc test_fail
    call apply_game_music_state
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    cmp byte [test_registers+0b1h], 0
    jne test_fail
    cmp byte [test_registers+0b2h], 0
    jne test_fail
    mov ax, [test_writes]
    mov [test_before], ax
    call music_tick
    call music_tick
    xor ax, ax
    call apply_game_music_state
    cmp word [song_position], song+3
    jne test_fail
    mov ax, [test_writes]
    cmp ax, [test_before]
    jne test_fail
    mov byte [es:6583h], 1
    mov bx, 8284h
    call probe_game_timer
    call apply_game_music_state
    call music_tick
    cmp word [song_position], song+6
    jne test_fail
    cmp byte [game_muted], 0
    jne test_fail
    mov byte [preview_mode], 1
    mov byte [game_recognized], 0
    call sync_game_music
    cmp byte [game_recognized], 0
    jne test_fail
    mov byte [preview_mode], 0
    push cs
    pop es
    mov bx, 8284h
    mov word [es:698ch], 030dh
    call probe_game_timer
    jnc test_fail
    mov word [es:698ch], 030ch
    call probe_game_timer
    jc test_fail
    call install_effect_bridge
    cmp word [es:698ch], 0fc24h
    jne test_fail
    cmp byte [es:69a5h], 0eah
    jne test_fail
    call probe_game_timer
    jc test_fail
    mov byte [es:6590h], 1
    mov word [es:658ch], 1000h
    mov word [es:6593h], 1004h
    mov word [es:658eh], 1193
    mov byte [game_muted], 1
    call update_effect
    cmp byte [test_registers+0a3h], 93h
    jne test_fail
    cmp byte [test_registers+0b3h], 26h
    jne test_fail
    mov ax, [test_writes]
    mov [test_before], ax
    call update_effect
    mov ax, [test_writes]
    cmp ax, [test_before]
    jne test_fail
    mov word [es:658eh], 2386
    call update_effect
    cmp byte [test_registers+0b3h], 22h
    jne test_fail
    mov word [es:6593h], 1003h
    mov ax, [test_writes]
    mov [test_before], ax
    call update_effect
    mov ax, [test_writes]
    sub ax, [test_before]
    cmp ax, 5
    jne test_fail
    mov byte [es:6590h], 0
    call update_effect
    cmp byte [test_registers+0b3h], 0
    jne test_fail
    cmp byte [test_registers+0bdh], 20h
    jne test_fail
    mov byte [es:6590h], 1
    mov word [es:658eh], 0
    call update_effect
    cmp byte [effect_active], 0
    jne test_fail
    mov word [es:658eh], 1193
    mov ax, 1234h
    mov bx, 5678h
    mov cx, 9abch
    mov dx, 0def0h
    mov si, 1357h
    mov di, 2468h
    call test_hook_entry
    cmp ax, 1234h
    jne test_fail
    cmp bx, 5678h
    jne test_fail
    cmp cx, 9abch
    jne test_fail
    cmp dx, 0def0h
    jne test_fail
    cmp si, 1357h
    jne test_fail
    cmp di, 2468h
    jne test_fail
    mov ax, 1
    call divisor_to_opl
    cmp ax, 1023
    jne test_fail
    cmp cl, 28
    jne test_fail
    mov ax, 65535
    call divisor_to_opl
    cmp ax, 384
    jne test_fail
    cmp cl, 0
    jne test_fail
    call init_music
    cmp byte [test_registers+28h], 20h
    jne test_fail
    cmp byte [test_registers+48h], 00h
    jne test_fail
    cmp byte [test_registers+0c3h], 0fh
    jne test_fail
    cmp byte [test_registers+68h], 0fah
    jne test_fail
    cmp byte [test_registers+88h], 0fh
    jne test_fail
    cmp byte [test_registers+54h], 04h
    jne test_fail
    cmp byte [test_registers+74h], 0fah
    jne test_fail
    cmp byte [test_registers+2bh], 20h
    jne test_fail
    cmp byte [test_registers+4bh], 08h
    jne test_fail
    cmp byte [test_registers+6bh], 0f8h
    jne test_fail
    mov byte [effect_preview_tick], 0
    call preview_effect_tick
    cmp byte [test_registers+0b3h], 2bh
    jne test_fail
    cmp byte [test_registers+0bdh], 28h
    jne test_fail
    call preview_effect_tick
    call preview_effect_tick
    cmp byte [test_registers+0b3h], 0
    jne test_fail
    cmp byte [test_registers+0bdh], 20h
    jne test_fail
    mov byte [effect_preview_tick], 8
    call preview_effect_tick
    cmp byte [effect_preview_tick], 0
    jne test_fail
    call start_gun_noise
    mov cx, 6
.noise_duration:
    call tick_gun_noise
    loop .noise_duration
    cmp byte [gun_noise_ticks], 1
    jne test_fail
    cmp byte [test_registers+0bdh], 28h
    jne test_fail
    call tick_gun_noise
    cmp byte [gun_noise_ticks], 0
    jne test_fail
    cmp byte [test_registers+0bdh], 20h
    jne test_fail
    mov ax, 4095
    call render_gun_pitch
    cmp byte [test_registers+0a3h], 80h
    jne test_fail
    cmp byte [test_registers+0b3h], 21h
    jne test_fail
    mov ax, 4096
    call render_gun_pitch
    cmp byte [test_registers+0a3h], 80h
    jne test_fail
    cmp byte [test_registers+0b3h], 21h
    jne test_fail
    mov ax, 65535
    call render_gun_pitch
    cmp byte [test_registers+0a3h], 80h
    jne test_fail
    cmp byte [test_registers+0b3h], 21h
    jne test_fail
    mov byte [preview_mode], 0
    mov ax, [test_writes]
    mov [test_before], ax
    call music_tick
    mov ax, [test_writes]
    cmp ax, [test_before]
    jne test_fail
    mov byte [es:685eh], 64h
    call install_game_music
    cmp byte [game_music_mode], 0
    jne test_fail
    mov byte [es:685eh], 65h
    call install_game_music
    cmp byte [game_music_mode], 1
    jne test_fail
    cmp byte [es:685ah], 0eah
    jne test_fail
    mov byte [es:6583h], 1
    mov word [es:6581h], 1000h
    mov byte [es:6585h], 2
    mov word [es:65dah], 1193
    mov word [music_resume], test_music_continue
    mov [music_resume+2], cs
    mov ax, 1234h
    mov bx, 5678h
    mov cx, 9abch
    mov dx, 0def0h
    xor si, si
    mov di, 2468h
    call game_music_bridge
    cmp ax, 1193
    jne test_fail
    cmp bx, 5678h
    jne test_fail
    cmp cx, 9abch
    jne test_fail
    cmp dx, 0def0h
    jne test_fail
    cmp si, 0
    jne test_fail
    cmp di, 2468h
    jne test_fail
    cmp byte [test_registers+0a0h], 93h
    jne test_fail
    cmp byte [test_registers+0b0h], 36h
    jne test_fail
    cmp byte [game_music_on], 1
    jne test_fail
    mov ax, [test_writes]
    mov [test_before], ax
    mov ax, 1193
    call capture_game_music_note
    mov ax, [test_writes]
    sub ax, [test_before]
    cmp ax, 3
    jne test_fail
    mov byte [es:6585h], 1
    call update_game_music
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    mov byte [es:6585h], 2
    call update_game_music
    cmp byte [test_registers+0b0h], 36h
    jne test_fail
    xor ax, ax
    call capture_game_music_note
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    mov byte [es:6583h], 0
    mov ax, 1193
    call capture_game_music_note
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    mov byte [es:6583h], 1
    call update_game_music
    cmp byte [test_registers+0b0h], 36h
    jne test_fail
    mov word [es:6581h], 0
    call update_game_music
    cmp byte [test_registers+0b0h], 0
    jne test_fail
    call silence
    in al, 61h
    or al, 3
    out 61h, al
    call cleanup
    in al, 61h
    and al, 3
    jne test_fail
    mov dx, test_pass_text
    mov ah, 9
    int 21h
    mov dx, test_sync_text
    mov ah, 9
    int 21h
    mov dx, test_speaker_text
    mov ah, 9
    int 21h
    mov dx, test_effect_text
    mov ah, 9
    int 21h
    mov dx, test_game_music_text
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

test_fail:
    cld
    call silence
    mov dx, test_fail_text
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

; Synthetic profile in this test process, not copied game code or song data.
    times 6581h-100h-($-$$) db 0
    dw 0
    db 1
    db 0, 2
    times 658ch-100h-($-$$) db 0
    dw 0
    dw 0
    db 1
    times 6593h-100h-($-$$) db 0
    dw 0
    times 66c1h-100h-($-$$) db 0
    dw 0c033h, 0a02eh, 6583h, 0c00bh
    times 685ah-100h-($-$$) db 0
    db 2eh,8bh,84h,0dah,65h,0bh,0c0h,75h,11h
    times 6874h-100h-($-$$) db 0
    db 2eh,38h,0eh,83h,65h,74h,1dh
    times 698ah-100h-($-$$) db 0
    db 0e4h,61h,0ch,03h
    times 69a5h-100h-($-$$) db 0
test_hook_entry:
    db 50h,2eh,0a0h,80h,65h,0feh,0c0h,24h,01h,58h,0c3h
    times 824ch-100h-($-$$) db 0
    dw 0650h, 0c033h, 0c08eh, 20bbh
    times 8284h-100h-($-$$) db 0
    dw 1e50h, 0b806h
