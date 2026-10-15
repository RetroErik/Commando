# CMS / Game Blaster engine (v1.2): Rob Hubbard's C64 arrangement on two SAA1099 chips + the game's own effects.
# Ported from Codex/cmsrun.s (SID_MODE 5) to run inside the game's code segment.  Chip 0 at 220h/221h, chip 1 at 222h/223h.
# Mapping: effects (INT 60h/61h bridge) on chip 0 channel 0; SID voice 1 -> chip 0 channel 3; voices 2/3 -> chip 1 channels 0/3.
# DS = CS in every routine here.

cms_write:
        push    dx
        mov     dx, 0x221
        out     dx, al
        dec     dx
        mov     al, ah
        out     dx, al
        pop     dx
        ret

cms_write2:
        push    dx
        mov     dx, 0x223
        out     dx, al
        dec     dx
        mov     al, ah
        out     dx, al
        pop     dx
        ret

cms_silence:
        cmp     byte ptr [s_cms_used], 0
        je      cs_done
        push    ax
        xor     ah, ah
        mov     al, 0x14
        call    cms_write
        mov     al, 0x15
        call    cms_write
        mov     al, 0x1C
        call    cms_write
        mov     al, 0x14
        call    cms_write2
        mov     al, 0x15
        call    cms_write2
        mov     al, 0x1C
        call    cms_write2
        pop     ax
cs_done:
        ret

# switch the SAA1099 pair on: reset the player state and start the score from the beginning
cms_enter:
        push    ax
        mov     byte ptr [s_cms_used], 1
        mov     al, 0x1C
        mov     ah, 1
        call    cms_write
        mov     al, 0x15
        xor     ah, ah
        call    cms_write
        mov     al, 0x14
        call    cms_write
        mov     al, 0x00
        mov     ah, 0xCC
        call    cms_write
        mov     al, 0x08
        xor     ah, ah
        call    cms_write
        mov     al, 0x10
        call    cms_write
        mov     al, 0x03
        mov     ah, 0x99
        call    cms_write
        mov     al, 0x16
        mov     ah, 0x30
        call    cms_write
        mov     al, 0x1C
        mov     ah, 1
        call    cms_write2
        mov     al, 0x14
        xor     ah, ah
        call    cms_write2
        mov     al, 0x15
        call    cms_write2
        mov     al, 0x00
        mov     ah, 0x99
        call    cms_write2
        mov     al, 0x03
        call    cms_write2
        mov     al, 0x16
        mov     ah, 0x33
        call    cms_write2
        xor     ax, ax
        mov     [sid_cursor], ax
        mov     byte ptr [sid_bank], 0
        mov     byte ptr [sid_phase], 0
        mov     byte ptr [sid_skip], 0
        mov     byte ptr [sid_freq_mask], 0
        mov     byte ptr [sid_noise_mask], 0
        mov     byte ptr [sid_oct01], 0
        mov     byte ptr [sid_oct23], 0
        mov     byte ptr [sid_second_freq_mask], 0
        mov     byte ptr [sid_second_noise_mask], 0
        mov     byte ptr [sid_second_oct01], 0
        mov     byte ptr [sid_second_oct23], 0
        mov     byte ptr [pitch_phase], 0
        mov     byte ptr [sid_enabled], 1
        mov     byte ptr [sid_current_volumes], 0x99
        mov     byte ptr [sid_current_volumes + 1], 0x99
        mov     byte ptr [sid_current_volumes + 2], 0x99
        mov     byte ptr [0x6583], 0               # the game's own tune stays muted; effects still follow its S key
        pop     ax
        ret

# re-apply the three SID voice volumes (all zero while the CMS music is muted)
sid_apply_volume:
        push    ax
        mov     ah, [sid_current_volumes]
        cmp     byte ptr [sid_enabled], 0
        jne     sav1
        xor     ah, ah
sav1:   mov     al, 0x03
        call    cms_write
        mov     ah, [sid_current_volumes + 1]
        cmp     byte ptr [sid_enabled], 0
        jne     sav2
        xor     ah, ah
sav2:   mov     al, 0x00
        call    cms_write2
        mov     ah, [sid_current_volumes + 2]
        cmp     byte ptr [sid_enabled], 0
        jne     sav3
        xor     ah, ah
sav3:   mov     al, 0x03
        call    cms_write2
        pop     ax
        ret

# ---- speaker bridge (the game's effects) ---------------------------------------------------------------
# AL = value the game wrote to port 61h: tone gate for effects on channel 0
cms_gate:
        and     al, 3
        mov     ah, [sid_freq_mask]
        and     ah, 0xFE
        cmp     al, 3
        jne     cg1
        or      ah, 1
cg1:    mov     [sid_freq_mask], ah
        mov     al, 0x14
        call    cms_write
        ret

# AL = byte written to PIT channel 2 (low byte first, then high byte): recover the divisor, convert to SAA1099 pitch
cms_pitch:
        cmp     byte ptr [pitch_phase], 0
        jne     cp_high
        mov     [pitch_low], al
        mov     byte ptr [pitch_phase], 1
        ret
cp_high:
        mov     byte ptr [pitch_phase], 0
        mov     ah, al
        mov     al, [pitch_low]
        mov     bx, ax
        or      bx, bx
        jz      cp_min
        cmp     bx, 19
        jb      cp_max
        mov     dx, 0x12                       # 1,193,182 / divisor = frequency in Hz
        mov     ax, 0x34DE
        div     bx
        cmp     ax, 61
        jb      cp_min
        xor     cx, cx
cp_oct: cmp     ax, 122
        jbe     cp_tone
        shr     ax, 1
        inc     cl
        cmp     cl, 7
        jb      cp_oct
        jmp     cp_tone
cp_min: xor     cx, cx
        xor     bx, bx
        jmp     cp_out
cp_max: mov     cx, 7
        mov     bx, 255
        jmp     cp_out
cp_tone:
        mov     bx, ax                         # SAA1099: f = 31250 * 2^octave / (511 - tone)
        mov     ax, 31250
        xor     dx, dx
        div     bx
        mov     bx, 511
        sub     bx, ax
        jns     cp_out
        xor     bx, bx
cp_out: mov     al, 0x10
        mov     ah, [sid_oct01]
        and     ah, 0xF0
        or      ah, cl
        mov     [sid_oct01], ah
        call    cms_write
        mov     al, 0x08
        mov     ah, bl
        call    cms_write
        ret

# ---- SID score player -------------------------------------------------------------------------------------
# the game timer runs about 109 Hz; the C64 PAL score advances at 50 Hz
sid_tick:
        add     byte ptr [sid_phase], 50
        cmp     byte ptr [sid_phase], 109
        jb      st_done
        sub     byte ptr [sid_phase], 109
        cmp     byte ptr [sid_skip], 0
        je      st_frame
        dec     byte ptr [sid_skip]
        ret
st_frame:
        mov     si, [sid_cursor]
        mov     ax, [sid_seg0]
        cmp     byte ptr [sid_bank], 0
        je      st_seg
        mov     ax, [sid_seg1]
st_seg: mov     es, ax
        call    sid_score_byte
        mov     dl, al
        cmp     dl, 0xFF
        jne     st_cmd
        mov     byte ptr [sid_bank], 0             # end of score: loop
        mov     ax, [sid_seg0]
        mov     es, ax
        xor     si, si
        call    sid_score_byte
        mov     dl, al
st_cmd: test    dl, 0x80
        jz      st_events
        and     dl, 0x7F
        dec     dl
        mov     [sid_skip], dl
        jmp     st_save
st_events:
        test    dl, 1
        jz      st_v2
        call    sid_score_byte
        mov     dh, al
        call    sid_score_byte
        mov     ah, al
        mov     al, dh
        mov     bl, 1
        call    sid_voice
st_v2:  test    dl, 2
        jz      st_v3
        call    sid_score_byte
        mov     dh, al
        call    sid_score_byte
        mov     ah, al
        mov     al, dh
        mov     bl, 2
        call    sid_voice
st_v3:  test    dl, 4
        jz      st_save
        call    sid_score_byte
        mov     dh, al
        call    sid_score_byte
        mov     ah, al
        mov     al, dh
        mov     bl, 3
        call    sid_voice
st_save:
        mov     [sid_cursor], si
st_done:
        ret

# next score byte in AL; the two banks (60000 + 53907 bytes) sit one after the other in the executable
sid_score_byte:
        mov     al, es:[si]
        inc     si
        cmp     si, 60000
        jne     ssb_done
        cmp     byte ptr [sid_bank], 0
        jne     ssb_done
        mov     byte ptr [sid_bank], 1
        push    ax
        mov     ax, [sid_seg1]
        mov     es, ax
        pop     ax
        xor     si, si
ssb_done:
        ret

# AL = tone, AH = active/noise/octave (bit 7 gate, bit 6 noise, bits 3-5 envelope level, bits 0-2 octave), BL = SID voice 1..3
sid_voice:
        push    ax
        push    bx
        push    cx
        push    dx
        mov     [sid_voice_tone], al
        mov     [sid_voice_state], ah
        mov     al, ah
        and     al, 0x38
        shr     al, 1
        shr     al, 1
        shr     al, 1
        push    bx
        xor     bh, bh
        mov     bl, al
        mov     ah, [sid_volume_table + bx]
        pop     bx
        push    bx
        xor     bh, bh
        dec     bl
        mov     [sid_current_volumes + bx], ah
        pop     bx
        cmp     byte ptr [sid_enabled], 0
        jne     sv_vol
        xor     ah, ah
sv_vol: cmp     bl, 1
        jne     sv_vol2
        mov     al, 0x03
        call    cms_write
        jmp     sv_vol_done
sv_vol2:
        mov     al, 0x00
        cmp     bl, 2
        je      sv_vol_w
        mov     al, 0x03
sv_vol_w:
        call    cms_write2
sv_vol_done:
        cmp     bl, 1
        jne     sv_chip2
        mov     al, 0x0B
        mov     ah, [sid_voice_tone]
        call    cms_write
        mov     cl, [sid_voice_state]
        and     cl, 7
        shl     cl, 1
        shl     cl, 1
        shl     cl, 1
        shl     cl, 1
        mov     ah, [sid_oct23]
        and     ah, 0x0F
        or      ah, cl
        mov     [sid_oct23], ah
        mov     al, 0x11
        call    cms_write
        and     byte ptr [sid_freq_mask], 0xF7
        mov     byte ptr [sid_noise_mask], 0
        mov     dl, [sid_voice_state]
        test    dl, 0x80
        jz      sv_m1
        test    dl, 0x40
        jz      sv_tone1
        mov     byte ptr [sid_noise_mask], 8
        jmp     sv_m1
sv_tone1:
        or      byte ptr [sid_freq_mask], 8
sv_m1:  mov     al, 0x14
        mov     ah, [sid_freq_mask]
        call    cms_write
        mov     al, 0x15
        mov     ah, [sid_noise_mask]
        call    cms_write
        jmp     sv_end
sv_chip2:
        cmp     bl, 2
        jne     sv_v3
        mov     bl, 1
        mov     al, 0x08
        mov     ah, [sid_voice_tone]
        call    cms_write2
        mov     cl, [sid_voice_state]
        and     cl, 7
        mov     ah, [sid_second_oct01]
        and     ah, 0xF0
        or      ah, cl
        mov     [sid_second_oct01], ah
        mov     al, 0x10
        call    cms_write2
        jmp     sv_m2
sv_v3:  mov     bl, 8
        mov     al, 0x0B
        mov     ah, [sid_voice_tone]
        call    cms_write2
        mov     cl, [sid_voice_state]
        and     cl, 7
        shl     cl, 1
        shl     cl, 1
        shl     cl, 1
        shl     cl, 1
        mov     ah, [sid_second_oct23]
        and     ah, 0x0F
        or      ah, cl
        mov     [sid_second_oct23], ah
        mov     al, 0x11
        call    cms_write2
sv_m2:  mov     cl, bl
        not     cl
        and     [sid_second_freq_mask], cl
        and     [sid_second_noise_mask], cl
        mov     dl, [sid_voice_state]
        test    dl, 0x80
        jz      sv_w2
        test    dl, 0x40
        jz      sv_tone2
        or      [sid_second_noise_mask], bl
        jmp     sv_w2
sv_tone2:
        or      [sid_second_freq_mask], bl
sv_w2:  mov     al, 0x14
        mov     ah, [sid_second_freq_mask]
        call    cms_write2
        mov     al, 0x15
        mov     ah, [sid_second_noise_mask]
        call    cms_write2
sv_end: pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

s_cms_used:             .byte 0
sid_enabled:            .byte 1
sid_phase:              .byte 0
sid_skip:               .byte 0
sid_bank:               .byte 0
sid_freq_mask:          .byte 0
sid_noise_mask:         .byte 0
sid_oct01:              .byte 0
sid_oct23:              .byte 0
sid_voice_tone:         .byte 0
sid_voice_state:        .byte 0
sid_second_freq_mask:   .byte 0
sid_second_noise_mask:  .byte 0
sid_second_oct01:       .byte 0
sid_second_oct23:       .byte 0
pitch_phase:            .byte 0
pitch_low:              .byte 0
sid_current_volumes:    .byte 0x99, 0x99, 0x99
sid_volume_table:       .byte 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x77, 0x99
sid_cursor:             .word 0
sid_seg0:               .word 0
sid_seg1:               .word 0
