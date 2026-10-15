# Commando VGA - sound layer (v1.1 AdLib, v1.2 CMS).  8086 real mode, GNU as, Intel syntax.
# By Dag Erik Hagesaeter / Retro Erik using GitHub Copilot in VS Code
#
# Included at the end of src/vga.s, so it lives in the game's code segment (CS).  Every routine below that touches
# the game's own sound variables (CS:6580h...) runs with DS = CS.
#
# Sound modes (M key cycles them; the game starts in SPEAKER):
#   0 SPEAKER  original PC speaker sound, written through the INT 60h/61h bridge to the real ports
#   1 CMS      SAA1099 (Game Blaster): Rob Hubbard SID arrangement + the game's effects on channel 0   (v1.2)
#   2 ADLIB    OPL2: the game's own melody (resolved pitches) + synthesized gunfire
#   3 OFF      silent; the game's sound sequencers keep running so game timing never changes
#
# Game sound variables (code segment): 6580 tick toggle, 6581 music start pointer, 6583 music enable (M),
# 6585 music phase (2 = note playing), 658C effect start pointer, 658E effect divisor, 6590 effect enable (S),
# 6593 effect cursor.   OUT 61h -> INT 60h, OUT 42h -> INT 61h in the original code.

        .set MODE_SPEAKER, 0
        .set MODE_CMS,     1
        .set MODE_ADLIB,   2
        .set MODE_OFF,     3

        .set A_TICK,       vga_base - (CODE_BASE - 0x69A5)
        .set A_PRINT,      vga_base - (CODE_BASE - 0x8320)
        .set A_ORIG_ENTRY, vga_base - (CODE_BASE - 0x008F)
        .set A_SETMUSIC_BODY, vga_base - (CODE_BASE - 0x6787)

# ============================================================================
# program entry / exit
# ============================================================================
        .global hook_entry
hook_entry:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     ds
        xor     ax, ax
        mov     es, ax
        cli
        mov     ax, es:[0x180]
        mov     [s_old60], ax
        mov     ax, es:[0x182]
        mov     [s_old60 + 2], ax
        mov     ax, es:[0x184]
        mov     [s_old61], ax
        mov     ax, es:[0x186]
        mov     [s_old61 + 2], ax
        mov     word ptr es:[0x180], offset snd_gate
        mov     es:[0x182], cs
        mov     word ptr es:[0x184], offset snd_pitch
        mov     es:[0x186], cs
        mov     ax, es:[0x58]                       # INT 16h: the launcher's Q handler leaves the game without passing
        mov     [s_old16], ax                       # through hook_exit, so watch for the Q key and silence the devices first
        mov     ax, es:[0x5A]
        mov     [s_old16 + 2], ax
        mov     word ptr es:[0x58], offset snd_int16
        mov     es:[0x5A], cs
        sti
.if SND_CMS
        mov     ax, cs
        add     ax, SCORE_PARA
        mov     [sid_seg0], ax
        add     ax, 3750
        mov     [sid_seg1], ax
.endif
        call    snd_detect
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        jmp     A_ORIG_ENTRY

# replaces: mov ax,4C00h / int 21h at the end of the game
        .global hook_exit
hook_exit:
        push    cs
        pop     ds
        cli
        call    snd_silence_all
        xor     ax, ax
        mov     es, ax
        mov     ax, [s_old60]
        mov     es:[0x180], ax
        mov     ax, [s_old60 + 2]
        mov     es:[0x182], ax
        mov     ax, [s_old61]
        mov     es:[0x184], ax
        mov     ax, [s_old61 + 2]
        mov     es:[0x186], ax
        mov     ax, [s_old16]
        mov     es:[0x58], ax
        mov     ax, [s_old16 + 2]
        mov     es:[0x5A], ax
        sti
        mov     ax, 0x4C00
        int     0x21

# INT 16h wrapper: a pending 'Q' means the launcher is about to abandon the game -> silence every sound device now
snd_int16:
        cmp     ah, 1
        je      si16_peek
        jmp     far ptr cs:[s_old16]
si16_peek:
        pushf
        call    far ptr cs:[s_old16]
        pushf
        jz      si16_done
        cmp     al, 'q'
        je      si16_quit
        cmp     al, 'Q'
        jne     si16_done
si16_quit:
        push    ds
        push    cs
        pop     ds
        push    ax
        cli
        call    snd_silence_all
        mov     byte ptr [s_mode], MODE_OFF
        pop     ax
        pop     ds
si16_done:
        popf
        retf    2

# ============================================================================
# INT 60h = OUT 61h,AL (speaker gate)      INT 61h = OUT 42h,AL (PIT channel 2 divisor, low then high byte)
# ============================================================================
snd_gate:
        cmp     byte ptr cs:[s_mode], MODE_SPEAKER
        jne     sg_other
        out     0x61, al
        iret
sg_other:
.if SND_CMS
        cmp     byte ptr cs:[s_mode], MODE_CMS
        jne     sg_done
        push    ax
        push    ds
        push    cs
        pop     ds
        call    cms_gate
        pop     ds
        pop     ax
.endif
sg_done:
        iret

snd_pitch:
        cmp     byte ptr cs:[s_mode], MODE_SPEAKER
        jne     sp_other
        out     0x42, al
        iret
sp_other:
.if SND_CMS
        cmp     byte ptr cs:[s_mode], MODE_CMS
        jne     sp_done
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    cs
        pop     ds
        call    cms_pitch
        pop     ds
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.endif
sp_done:
        iret

# ============================================================================
# mode handling
# ============================================================================
# AdLib is the only device that can be detected; a missing card is dropped from the cycle.
snd_detect:
        push    ax
        push    bx
        push    cx
        push    dx
        mov     ax, 0x6004
        call    opl_write
        mov     ax, 0x8004
        call    opl_write
        mov     dx, 0x388
        in      al, dx
        and     al, 0xE0
        mov     bl, al
        mov     ax, 0xFF02
        call    opl_write
        mov     ax, 0x2104
        call    opl_write
        mov     cx, 200
sdt1:   in      al, dx
        loop    sdt1
        and     al, 0xE0
        mov     bh, al
        mov     ax, 0x6004
        call    opl_write
        mov     ax, 0x8004
        call    opl_write
        cmp     bl, 0
        jne     sdt_missing
        cmp     bh, 0xC0
        jne     sdt_missing
        jmp     sdt_done
sdt_missing:
        and     byte ptr [s_allowed], 0xFB
sdt_done:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# stop every sound device (DS = CS)
snd_silence_all:
        push    ax
        in      al, 0x61
        and     al, 0xFC
        out     0x61, al
        call    a_silence
.if SND_CMS
        call    cms_silence
.endif
        pop     ax
        ret

# AL = new mode.  DS = CS, interrupts disabled by the caller.
snd_set_mode:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ax
        call    snd_silence_all
        pop     ax
        mov     [s_mode], al
        mov     byte ptr [s_phase], 0
        mov     byte ptr [a_music_on], 0
        mov     byte ptr [a_eff_active], 0
        mov     byte ptr [a_noise_ticks], 0
.if SND_CMS
        cmp     al, MODE_CMS
        jne     ssm_notcms
        call    cms_enter
        jmp     ssm_label
ssm_notcms:
        cmp     byte ptr [0x6583], 0
        jne     ssm_adlib
        mov     byte ptr [0x6583], 0xFF       # leaving CMS: hand the game its own tune flag back
ssm_adlib:
.endif
        cmp     al, MODE_ADLIB
        jne     ssm_label
        call    a_init
ssm_label:
        mov     byte ptr [s_label_timer], 90
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# replaces the M key's "toggle music" call at CS:363D
        .global hook_mkey
hook_mkey:
        push    ax
        push    bx
        push    cx
        push    ds
        push    cs
        pop     ds
        cli
        mov     al, [s_mode]
mk1:    inc     al
        and     al, 3
        mov     cl, al
        mov     ah, [s_allowed]
        shr     ah, cl
        test    ah, 1
        jz      mk1
        call    snd_set_mode
        sti
        pop     ds
        pop     cx
        pop     bx
        pop     ax
        ret

# ============================================================================
# timer tick: replaces the near CALL to the game's sound tick (CS:69A5) in its IRQ0 handler
# ============================================================================
        .global hook_tick
hook_tick:
        call    A_TICK
        cmp     byte ptr cs:[s_mode], MODE_ADLIB
        je      ht_run
.if SND_CMS
        cmp     byte ptr cs:[s_mode], MODE_CMS
        je      ht_run
.endif
        ret
ht_run:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        push    cs
        pop     es
        cmp     byte ptr [s_mode], MODE_ADLIB
        jne     ht_cms
        call    a_tick
        jmp     ht_out
ht_cms:
.if SND_CMS
        call    sid_tick
.endif
ht_out: pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# replaces MOV AX,CS:[SI+65DAh] in the music sequencer: AX = the note's PIT divisor
        .global hook_notefetch
hook_notefetch:
        mov     ax, cs:[si + 0x65DA]
        cmp     byte ptr cs:[s_mode], MODE_ADLIB
        jne     nf_ret
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    ax
        push    cs
        pop     ds
        call    a_capture
        pop     ax
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
nf_ret: ret

.if SND_CMS
# replaces the first bytes of the game's "set music enable" (CS:6784, argument at [bp+4])
        .global hook_setmusic
hook_setmusic:
        push    bp
        mov     bp, sp
        cmp     byte ptr cs:[s_mode], MODE_CMS
        je      hsm_cms
        jmp     A_SETMUSIC_BODY
hsm_cms:
        push    ax
        push    ds
        push    cs
        pop     ds
        mov     ax, [bp + 4]
        mov     byte ptr [sid_enabled], 1
        or      ax, ax
        jnz     hsm_set
        mov     byte ptr [sid_enabled], 0
hsm_set:
        mov     byte ptr [0x6583], 0
        call    sid_apply_volume
        pop     ds
        pop     ax
        pop     bp
        ret

# replaces the game's "is music on" query (CS:66C1): AX = 0/1
        .global hook_getmusic
hook_getmusic:
        xor     ax, ax
        cmp     byte ptr cs:[s_mode], MODE_CMS
        jne     hgm1
        mov     al, cs:[sid_enabled]
        jmp     hgm2
hgm1:   mov     al, cs:[0x6583]
hgm2:   or      ax, ax
        je      hgm3
        mov     ax, 1
hgm3:   ret
.endif

# replaces the pause-menu "MUSIC ON/OFF" text: prints the current sound device at the same place
        .global hook_modetext
hook_modetext:
        push    ax
        push    bx
        push    si
        mov     al, cs:[s_mode]
        xor     ah, ah
        mov     bx, ax
        shl     bx, 1
        mov     si, cs:[s_mode_str + bx]
        mov     bx, 0xFF00                  # DS:FF00 = unused game data; the game's print routine reads DS-relative text
hmt1:   mov     al, cs:[si]
        mov     [bx], al
        inc     si
        inc     bx
        or      al, al
        jnz     hmt1
        mov     ax, 3
        push    ax
        mov     ax, 0xFF00
        push    ax
        xor     ax, ax
        push    ax
        call    A_PRINT
        add     sp, 6
        pop     si
        pop     bx
        pop     ax
        ret

# on-screen label after a mode change; ES:DI = A000h screen, DS = CS, preserves everything
snd_draw_label:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        call    snd_label_width
        mov     bx, ax
        mov     di, 80
        mov     dx, 13
        mov     si, 320
        sub     si, bx
        shr     bx, 1
dlb1:   mov     cx, bx
        xor     ax, ax
        cld
        rep     stosw
        add     di, si
        dec     dx
        jnz     dlb1
        mov     al, [s_mode]
        xor     ah, ah
        mov     bx, ax
        shl     bx, 1
        mov     si, [s_label_tab + bx]
        mov     cx, 82 + 1 * 320
dlb2:   lodsb
        or      al, al
        jz      dlb3
        xor     ah, ah
        mov     bx, ax
        mov     ax, 3
        call    hook_glyph
        add     cx, 12
        jmp     dlb2
dlb3:   pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# AX = width in pixels of the label box (12 per glyph + 2 margin each side); only uses CS-relative reads
snd_label_width:
        push    bx
        push    si
        mov     al, cs:[s_mode]
        xor     ah, ah
        mov     bx, ax
        shl     bx, 1
        mov     si, cs:[s_label_tab + bx]
        xor     ax, ax
slw1:   cmp     byte ptr cs:[si], 0
        je      slw2
        inc     ax
        inc     si
        jmp     slw1
slw2:   mov     bx, ax
        shl     ax, 1
        shl     ax, 1
        shl     bx, 1
        shl     bx, 1
        shl     bx, 1
        add     ax, bx
        add     ax, 4
        pop     si
        pop     bx
        ret

# ============================================================================
# AdLib / OPL2 engine
# ============================================================================
# AL = register, AH = value (status-port reads give the 3.3 / 23 microsecond delays on any CPU)
opl_write:
        push    ax
        push    cx
        push    dx
        mov     dx, 0x388
        out     dx, al
        mov     cx, 6
ow1:    in      al, dx
        loop    ow1
        inc     dx
        mov     al, ah
        out     dx, al
        dec     dx
        mov     cx, 35
ow2:    in      al, dx
        loop    ow2
        pop     dx
        pop     cx
        pop     ax
        ret

# all voices off, carriers attenuated (also used when the OPL does not exist - harmless)
a_silence:
        push    ax
        push    si
        mov     ax, 0x00BD
        call    opl_write
        mov     al, 0xB0
as1:    call    opl_write
        inc     al
        cmp     al, 0xB9
        jb      as1
        mov     si, offset a_carriers
as2:    mov     al, [si]
        add     al, 0x40
        mov     ah, 0x3F
        call    opl_write
        inc     si
        cmp     si, offset a_carriers_end
        jb      as2
        pop     si
        pop     ax
        ret

a_init:
        push    ax
        push    si
        call    a_silence
        mov     si, offset a_instruments
ai1:    mov     ax, [si]
        call    opl_write
        add     si, 2
        cmp     si, offset a_instruments_end
        jb      ai1
        mov     ax, 0x00B0
        call    opl_write
        inc     al
        call    opl_write
        inc     al
        call    opl_write
        pop     si
        pop     ax
        ret

# AX = nonzero PIT divisor -> AX = OPL f-number, CL = block bits (the PIT/OPL clock ratio is 24 within 0.01 %)
a_divisor_to_opl:
        mov     bx, ax
        mov     cx, 7
        mov     si, 0
        mov     di, 3
        cmp     bx, 193
        jae     adv1
        mov     ax, 1023
        jmp     adv3
adv1:   mov     ax, si
        mov     dx, di
        div     bx
        cmp     ax, 512
        jae     adv3
        jcxz    adv3
        shl     si, 1
        rcl     di, 1
        dec     cx
        jmp     adv1
adv3:   shl     cl, 1
        shl     cl, 1
        ret

# AX = divisor, BL = OPL channel
a_render_pitch:
        push    bx
        call    a_divisor_to_opl
        pop     bx
        mov     dh, ah
        mov     ah, al
        mov     al, bl
        add     al, 0xA0
        call    opl_write
        mov     ah, dh
        or      ah, cl
        or      ah, 0x20
        mov     al, bl
        add     al, 0xB0
        call    opl_write
        ret

# a new note of the game's music sequencer (AX = its divisor)
a_capture:
        mov     [a_divisor], ax
        call    a_stop_music
        cmp     byte ptr [0x6583], 0
        je      acp1
        call    a_render_music
acp1:   ret

a_render_music:
        mov     ax, [a_divisor]
        or      ax, ax
        jz      arm1
        xor     bx, bx
        call    a_render_pitch
        mov     byte ptr [a_music_on], 1
arm1:   ret

a_stop_music:
        cmp     byte ptr [a_music_on], 0
        je      asm1
        mov     ax, 0x00B0
        call    opl_write
        mov     byte ptr [a_music_on], 0
asm1:   ret

a_tick:
        cmp     byte ptr [0x6583], 0
        je      at_off
        cmp     word ptr [0x6581], 0
        je      at_off
        cmp     byte ptr [0x6585], 2
        jne     at_off
        cmp     byte ptr [a_music_on], 0
        jne     at_eff
        call    a_render_music
        jmp     at_eff
at_off: call    a_stop_music
at_eff: call    a_update_effect
        ret

a_update_effect:
        call    a_noise_tick
        cmp     byte ptr [0x6590], 0
        je      aue_stop
        mov     si, [0x658C]
        or      si, si
        jz      aue_stop
        mov     di, [0x6593]
        cmp     di, si
        je      aue_stop
        mov     ax, [0x658E]
        or      ax, ax
        jz      aue_stop
        mov     dx, ax
        cmp     byte ptr [a_eff_active], 0
        je      aue_trigger
        cmp     si, [a_eff_source]
        jne     aue_trigger
        cmp     di, [a_eff_cursor]
        jb      aue_trigger
        cmp     dx, [a_eff_div]
        jne     aue_pitch
        mov     [a_eff_cursor], di
        ret
aue_trigger:
        mov     ax, 0x00B3
        call    opl_write
        call    a_noise_start
aue_pitch:
        mov     [a_eff_source], si
        mov     [a_eff_cursor], di
        mov     [a_eff_div], dx
        mov     ax, dx
        call    a_gun_pitch
        mov     byte ptr [a_eff_active], 1
        ret
aue_stop:
        call    a_noise_stop
        cmp     byte ptr [a_eff_active], 0
        je      aue_done
        mov     ax, 0x00B3
        call    opl_write
        mov     byte ptr [a_eff_active], 0
aue_done:
        ret

# the effect's pitch sweep, four octaves lower, on the FM "body" channel 3
a_gun_pitch:
        cmp     ax, 4095
        ja      agp1
        shl     ax, 1
        shl     ax, 1
        shl     ax, 1
        shl     ax, 1
        jmp     agp2
agp1:   mov     ax, 65535
agp2:   mov     bl, 3
        jmp     a_render_pitch

a_noise_start:
        mov     ax, 0x20BD
        call    opl_write
        mov     ax, 0x28BD
        call    opl_write
        mov     byte ptr [a_noise_ticks], 7
        ret

a_noise_tick:
        cmp     byte ptr [a_noise_ticks], 0
        je      ant1
        dec     byte ptr [a_noise_ticks]
        jnz     ant1
        mov     ax, 0x20BD
        call    opl_write
ant1:   ret

a_noise_stop:
        cmp     byte ptr [a_noise_ticks], 0
        je      ans1
        mov     byte ptr [a_noise_ticks], 0
        mov     ax, 0x20BD
        call    opl_write
ans1:   ret

# ---- CMS / SAA1099 engine (v1.2) -------------------------------------------------------------------
.if SND_CMS
        .include "src/cms.s"
.endif

# ============================================================================
# data
# ============================================================================
s_mode:         .byte 0
s_allowed:      .byte 0x0D + (SND_CMS * 2)       # bit n = mode n may be selected by M: SPEAKER, ADLIB, OFF (+ CMS from v1.2)
s_phase:        .byte 0
s_label_timer:  .byte 0
s_old60:        .word 0, 0
s_old61:        .word 0, 0
s_old16:        .word 0, 0
a_music_on:     .byte 0
a_noise_ticks:  .byte 0
a_eff_active:   .byte 0
                .byte 0
a_divisor:      .word 0
a_eff_source:   .word 0
a_eff_cursor:   .word 0
a_eff_div:      .word 0

s_mode_str:     .word str_speaker, str_cms, str_adlib, str_off
str_speaker:    .asciz "SPEAKER "
str_cms:        .asciz "CMS     "
str_adlib:      .asciz "ADLIB   "
str_off:        .asciz "OFF     "
s_label_tab:    .word lbl_speaker, lbl_cms, lbl_adlib, lbl_off
lbl_speaker:    .asciz "SOUND:SPEAKER"
lbl_cms:        .asciz "SOUND:CMS"
lbl_adlib:      .asciz "SOUND:ADLIB"
lbl_off:        .asciz "SOUND:OFF"

a_carriers:     .byte 3, 4, 5, 11, 12, 13, 19, 20, 21
a_carriers_end:

# (register, value) pairs.  Channels 0-2: melodic voices (channel 0 plays the game's melody),
# channel 3: additive-mode FM gunfire body, channel 6/7: rhythm noise setup.
a_instruments:
        .byte   0x01, 0x20, 0x08, 0x00
        .byte   0x20, 0x21, 0x23, 0x21, 0x40, 0x1C, 0x43, 0x14
        .byte   0x60, 0xF2, 0x63, 0xF2, 0x80, 0x74, 0x83, 0x75
        .byte   0xE0, 0x00, 0xE3, 0x00, 0xC0, 0x04
        .byte   0x21, 0x21, 0x24, 0x21, 0x41, 0x18, 0x44, 0x1A
        .byte   0x61, 0xF3, 0x64, 0xF3, 0x81, 0x85, 0x84, 0x85
        .byte   0xE1, 0x00, 0xE4, 0x00, 0xC1, 0x02
        .byte   0x22, 0x0F, 0x25, 0x01, 0x42, 0x00, 0x45, 0x20
        .byte   0x62, 0xF8, 0x65, 0xF8, 0x82, 0xFF, 0x85, 0xFF
        .byte   0xE2, 0x00, 0xE5, 0x00, 0xC2, 0x0E
        .byte   0x28, 0x20, 0x2B, 0x20, 0x48, 0x00, 0x4B, 0x08
        .byte   0x68, 0xFA, 0x6B, 0xF8, 0x88, 0x0F, 0x8B, 0x6F
        .byte   0xE8, 0x00, 0xEB, 0x00, 0xC3, 0x0F
        .byte   0x31, 0x21, 0x51, 0x00, 0x71, 0xF8, 0x91, 0x0F, 0xF1, 0x00
        .byte   0x34, 0x21, 0x54, 0x04, 0x74, 0xFA, 0x94, 0x0F, 0xF4, 0x00
        .byte   0xA7, 0x00, 0xB7, 0x11, 0xBD, 0x20
a_instruments_end:
