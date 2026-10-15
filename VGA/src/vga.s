# VGA replacement graphics layer for Commando 1.01 (8086 real mode, GNU as, Intel syntax)
# Code lives in the CS window of the patched EXE at CS:8350h; assets and the ground ring follow in their own segments.
# By Dag Erik Hagesaeter / Retro Erik using GitHub Copilot in VS Code
        .intel_syntax noprefix
        .code16
        .arch   i8086
        .text

# ---- layout (must match tools/build_vga.py) --------------------------------
        .set CODE_BASE,  0x8360
        .set ASSET_OFF,  0xC360
        .set ASSET_PARA, ASSET_OFF >> 4
        .include "build/consts.s"
        .set RING_PARA,  ASSET_PARA + ((ASSET_BYTES + 15) >> 4)
        .set SCORE_PARA, RING_PARA + RING_PARAS

# ---- addresses of original routines (code segment offsets) ------------------
        .set A_RAND,     vga_base - (CODE_BASE - 0x6B8B)

        .set DS_LEVEL,   0xFB58
        .set DS_SLOW,    0xFE38
        .set DS_RING,    0xDCE2          # original 2bpp ground ring (only used as an address base)

        .global vga_base
vga_base:

# ============================================================================
# hooks called/jumped to from the patched original code
# ============================================================================

# ---- mode 13h + palette (replaces: call 8310 with mode 4) -------------------
        .global hook_setmode
hook_setmode:
        push    ax
        push    bx
        push    cx
        push    dx
        push    es
        mov     ax, 0x0013
        int     0x10
        mov     ax, cs
        mov     es, ax
        mov     dx, offset t_palette
        xor     bx, bx
        mov     cx, 256
        mov     ax, 0x1012
        int     0x10
        pop     es
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# ---- 7590: fill a RAM screen: (seg, byte) -----------------------------------
        .global hook_ramfill
hook_ramfill:
        push    bp
        mov     bp, sp
        push    ax
        push    cx
        push    di
        push    es
        mov     ax, [bp+4]
        mov     es, ax
        mov     ax, [bp+6]
        mov     ah, al
        xor     di, di
        mov     cx, 0x8000
        cld
        rep     stosw
        pop     es
        pop     di
        pop     cx
        pop     ax
        pop     bp
        ret

# ---- 77AA: clear the video screen -------------------------------------------
        .global hook_clearscreen
hook_clearscreen:
        push    ax
        push    cx
        push    di
        push    es
        mov     ax, 0xA000
        mov     es, ax
        xor     ax, ax
        xor     di, di
        mov     cx, 32000
        cld
        rep     stosw
        pop     es
        pop     di
        pop     cx
        pop     ax
        ret

# ---- 8172: wait for vertical retrace, returns poll count; paced to 60 Hz ----
        .global hook_retrace
hook_retrace:
        push    bx
        push    dx
        xor     bx, bx
        mov     dx, 0x3DA
r1:     in      al, dx
        test    al, 8
        jnz     r1
r2:     inc     bx
        in      al, dx
        test    al, 8
        jz      r2
        # VGA mode 13h refreshes at ~70 Hz, CGA at ~60 Hz: insert an extra retrace wait on 17% of the
        # waits so the retrace-locked parts of the game keep their original speed.
        mov     ax, cs:[v_pace]
        add     ax, 17
        cmp     ax, 100
        jb      r5
        sub     ax, 100
        mov     cs:[v_pace], ax
r3:     in      al, dx
        test    al, 8
        jnz     r3
r4:     in      al, dx
        test    al, 8
        jz      r4
        jmp     r6
r5:     mov     cs:[v_pace], ax
r6:     mov     ax, bx
        pop     dx
        pop     bx
        ret

# ---- 8139: present RAM screen (segment in SI) to the VGA screen ---------------
        .global hook_present
hook_present:
        call    hook_retrace
        push    ax
        push    bx
        push    dx
        push    si
        push    di
        push    cx
        push    ds
        push    es
        mov     ds, si
        mov     ax, 0xA000
        mov     es, ax
        xor     si, si
        xor     di, di
        cld
        cmp     byte ptr cs:[s_label_timer], 0
        je      hp_full
        # label visible: leave its box (rows 0-12, above the border) out of the copy so the game picture never flashes there
        call    snd_label_width
        mov     dx, ax
        shr     ax, 1
        mov     bx, 120
        sub     bx, ax
        mov     ah, 13
hp_row: mov     cx, 40
        rep     movsw
        add     si, dx
        add     di, dx
        mov     cx, bx
        rep     movsw
        dec     ah
        jnz     hp_row
        mov     cx, 187 * 160
        jmp     hp_copy
hp_full: mov    cx, 32000
hp_copy: rep    movsw
        push    cs
        pop     ds
        cmp     byte ptr [s_label_timer], 0
        je      hp_nolabel
        dec     byte ptr [s_label_timer]
        xor     di, di
        call    snd_draw_label
hp_nolabel:
        pop     es
        pop     ds
        pop     cx
        pop     di
        pop     si
        pop     dx
        pop     bx
        pop     ax
        ret

# ---- 77C1: pixel address: bx = x in 4-pixel units, cx = y  ->  ax = y*320 + x*4 --
        .global hook_addr
hook_addr:
vga_addr:
        push    dx
        mov     ax, cx
        mov     dx, ax
        shl     ax, 1
        shl     ax, 1
        add     ax, dx              # 5y
        shl     ax, 1
        shl     ax, 1
        shl     ax, 1
        shl     ax, 1
        shl     ax, 1
        shl     ax, 1               # 320y
        mov     dx, bx
        shl     dx, 1
        shl     dx, 1
        add     ax, dx
        pop     dx
        ret

# ---- 7C3F: draw a sprite: es=dest seg, dx=CGA record, bx=x (2px units), cx=y -----
        .global hook_sprite
hook_sprite:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        mov     bp, bx
        shr     bx, 1
        call    vga_addr
        mov     di, ax
        mov     si, dx
        mov     bx, [si]            # odd_off of the CGA record (game data segment)
        # find the VGA asset of this record
        xor     si, si
        mov     cx, N_SPRITES
sf1:    mov     ax, cs:[si + offset t_sprite_keys]
        cmp     ax, dx
        je      sf2
        add     si, 2
        loop    sf1
        jmp     sdone
sf2:    mov     ax, cs:[si + offset t_sprite_paras]
        add     ax, ASSET_PARA
        mov     cx, cs
        add     ax, cx
        mov     ds, ax
        xor     si, si
        lodsw                       # al = wpx, ah = h
        test    bp, 1
        jz      sd1
        or      bx, bx
        jz      sd1
        # odd image: skip the even bitmap (wpx*h bytes) and take its own width
        push    ax
        mul     ah                  # ax = al * ah
        mov     si, ax
        add     si, 2
        pop     ax
        lodsb                       # odd width, h unchanged
sd1:    mov     dl, al              # dl = wpx
        xor     dh, dh
        mov     bh, ah              # bh = rows
        cld
srow:   mov     cx, dx
spx:    lodsb
        or      al, al
        jz      sskip
        mov     es:[di], al
sskip:  inc     di
        loop    spx
        add     di, 320
        sub     di, dx
        dec     bh
        jnz     srow
sdone:  pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# ---- 7899: restore a sprite footprint from the background segment (si) -------------
        .global hook_restore
hook_restore:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        mov     bp, bx
        shr     bx, 1
        call    vga_addr
        mov     di, ax
        mov     bx, dx              # record pointer (game data segment)
        test    bp, 1
        jz      rs1
        mov     ax, [bx]
        or      ax, ax
        jz      rs1
        add     bx, ax              # odd image header at record + 2 + odd_off
rs1:    mov     al, [bx+3]          # width in bytes
        xor     ah, ah
        shl     ax, 1
        shl     ax, 1
        mov     dx, ax              # dx = width in pixels
        mov     bl, [bx+2]          # rows
        mov     ds, si              # background segment
        mov     si, di
        cld
rrow:   mov     cx, dx
        shr     cx, 1
        rep     movsw
        add     si, 320
        sub     si, dx
        add     di, 320
        sub     di, dx
        dec     bl
        jnz     rrow
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# ---- 6D4E: draw a glyph / 8x8 tile: bx = code, ax = colour, cx = dest offset, es = dest seg ----
        .global hook_glyph
hook_glyph:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    si
        push    bp
        push    ds
        mov     di, cx
        and     ax, 0x000F
        mov     bp, ax              # colour (0 = erase)
        cmp     bx, 0x90
        jae     gdone
        mov     dx, 12              # glyph size
        cmp     bx, 0x80
        jb      g0
        mov     dx, 8
g0:     shl     bx, 1
        mov     ax, cs:[bx + offset t_glyph]
        cmp     ax, 0xFFFF
        je      gdone
        add     ax, ASSET_PARA
        mov     cx, cs
        add     ax, cx
        mov     ds, ax
        xor     si, si
        mov     bh, dl              # rows
        cld
grow:   mov     cx, dx
gpx:    lodsb
        or      al, al
        jz      gskip
        or      bp, bp
        jnz     gput
        xor     al, al
gput:   mov     es:[di], al
gskip:  inc     di
        loop    gpx
        add     di, 320
        sub     di, dx
        dec     bh
        jnz     grow
gdone:  pop     ds
        pop     bp
        pop     si
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# ---- 18A3: title bitmap: (seg, x bytes, y bottom, index) -------------------------
        .global hook_title
hook_title:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     ax, [bp+4]
        mov     es, ax
        mov     bx, [bp+10]
        shl     bx, 1
        mov     ax, cs:[bx + offset t_title]
        add     ax, ASSET_PARA
        mov     cx, cs
        add     ax, cx
        mov     ds, ax
        xor     si, si
        lodsw                       # al = wpx, ah = h
        mov     dl, al
        xor     dh, dh              # dx = wpx
        mov     al, ah
        xor     ah, ah
        mov     bx, ax              # bx = h
        mov     ax, [bp+8]          # y of the bottom row
        sub     ax, bx
        sar     ax, 1
        shl     ax, 1               # top row (even, like the CGA bank layout)
        mov     cx, ax
        push    bx
        mov     bx, [bp+6]
        call    vga_addr
        mov     di, ax
        pop     bx
        mov     bh, bl              # rows
        cld
trow:   mov     cx, dx
tpx:    lodsb
        or      al, al
        jz      tskip
        mov     es:[di], al
tskip:  inc     di
        loop    tpx
        add     di, 320
        sub     di, dx
        dec     bh
        jnz     trow
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# ---- 6A2B: dissolve a RAM screen onto the display in the original pseudo-random order ----
        .global hook_dissolve
hook_dissolve:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    si
        call    A_RAND
        mov     di, ax
dis1:   call    A_RAND
        mov     si, ax
        call    dis_copy
        cmp     byte ptr [DS_SLOW], 0
        je      dis2
        mov     cx, 10
dis3:   loop    dis3
dis2:   cmp     si, di
        jne     dis1
        xor     si, si
        call    dis_copy
        mov     ax, [bp+4]
        mov     [0xF8FA], ax
        pop     si
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# copy the 4 pixels that CGA byte offset si covers from segment [bp+4] to the display
dis_copy:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    si
        push    ds
        push    es
        mov     ax, si
        and     ax, 0x1FFF
        mov     bx, si
        and     bx, 0x2000
        mov     cl, 80
        div     cl                  # al = row pair, ah = byte column
        cmp     al, 100
        jae     dc_out
        xor     dx, dx
        mov     dl, ah              # byte column
        xor     ah, ah
        shl     ax, 1               # y = pair*2
        or      bx, bx
        jz      dc1
        inc     ax                  # odd bank
dc1:    mov     cx, ax              # y
        mov     bx, dx              # x in 4-pixel units
        call    vga_addr
        mov     di, ax
        mov     si, ax
        mov     ax, [bp+4]
        mov     ds, ax
        mov     ax, 0xA000
        mov     es, ax
        movsw
        movsw
dc_out: pop     es
        pop     ds
        pop     si
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# ---- 76D1: ground ring -> screen: (seg, x bytes, y, ring start, offset, size, rows, bytes per row) ----
        .global hook_groundblit
hook_groundblit:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     ax, [bp+4]
        mov     es, ax
        mov     bx, [bp+6]
        mov     cx, [bp+8]
        call    vga_addr
        mov     di, ax
        # first ring row = offset / bytes-per-row ; ring rows = size / bytes-per-row
        mov     ax, [bp+12]
        mov     bl, [bp+18]
        div     bl
        mov     dl, al              # dl = current ring row
        mov     ax, [bp+14]
        div     bl
        mov     dh, al              # dh = ring rows
        mov     bl, [bp+18]
        xor     bh, bh
        shl     bx, 1
        shl     bx, 1               # bx = row width in pixels (224)
        # si = ring row * width
        xor     ax, ax
        mov     al, dl
        push    dx
        mul     bx
        pop     dx
        mov     si, ax
        mov     ax, cs
        add     ax, RING_PARA
        mov     ds, ax
        mov     cx, [bp+16]         # rows to draw
        cld
gb1:    push    cx
        mov     cx, bx
        shr     cx, 1
        push    di
        rep     movsw
        pop     di
        add     di, 320
        inc     dl
        cmp     dl, dh
        jb      gb2
        xor     dl, dl
        xor     si, si
gb2:    pop     cx
        loop    gb1
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# ---- scenery lookup: ax = DS pointer into a CGA bitmap -> carry clear: dx = asset segment, bx = byte offset
# (clobbers cx/si; DS must be the game data segment)
scen_find:
        push    cx
        push    si
        push    di
        mov     di, ax
        xor     ax, ax
        mov     al, [DS_LEVEL]
        mov     bx, ax
        xor     si, si
        mov     cx, N_SCEN
sc1:    cmp     cs:[si + offset t_scen], bx
        jne     sc3
        mov     ax, cs:[si + offset t_scen + 2]    # cga base
        cmp     di, ax
        jb      sc3
        mov     dx, di
        sub     dx, ax                              # offset inside the bitmap
        cmp     dx, cs:[si + offset t_scen + 4]    # size
        jae     sc3
        mov     ax, cs:[si + offset t_scen + 6]    # para
        add     ax, ASSET_PARA
        mov     bx, cs
        add     ax, bx
        mov     bx, dx
        shl     bx, 1
        shl     bx, 1
        mov     dx, ax
        clc
        jmp     sc4
sc3:    add     si, 10
        loop    sc1
        stc
sc4:    pop     di
        pop     si
        pop     cx
        ret

# ---- 5F5D / 6498 replacements: (dest ptr in 2bpp ring, src ptr, byte count) ----
        .global hook_orblit
hook_orblit:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     bl, 1
        jmp     blit_common
        .global hook_copyblit
hook_copyblit:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     bl, 1               # copy-blit also colour-keys (index 0 = transparent), like the art expects
blit_common:
        mov     byte ptr cs:[v_orflag], bl
        mov     ax, [bp+4]
        sub     ax, DS_RING
        shl     ax, 1
        shl     ax, 1
        mov     di, ax              # ring pixel offset
        mov     ax, cs
        add     ax, RING_PARA
        mov     es, ax
        mov     ax, [bp+6]
        mov     cx, [bp+8]
        call    scen_find
        jc      bl_fallback
        # dx = asset segment, bx = offset
        mov     si, bx
        mov     ds, dx
        shl     cx, 1
        shl     cx, 1               # pixels
        cld
        cmp     byte ptr cs:[v_orflag], 0
        jne     bl_or
        shr     cx, 1
        rep     movsw
        jmp     bl_out
bl_or:  lodsb
        or      al, al
        jz      bl_o2
        mov     es:[di], al
bl_o2:  inc     di
        loop    bl_or
        jmp     bl_out
# unknown bitmap: expand the CGA bytes through the level colour map
bl_fallback:
        mov     si, [bp+6]
        mov     cx, [bp+8]
bf1:    push    cx
        lodsb
        mov     ah, al
        mov     cx, 4
bf2:    rol     ah, 1
        rol     ah, 1
        mov     al, ah
        and     al, 3
        call    gcol_of
        cmp     byte ptr cs:[v_orflag], 0
        je      bf3
        or      al, al
        jz      bf4
bf3:    mov     es:[di], al
bf4:    inc     di
        loop    bf2
        pop     cx
        loop    bf1
bl_out: pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# ---- colour of a CGA pixel value for the current level: al = value 0..3 -> al = palette index
# for value 0 a pseudo-random shade is chosen (own LFSR, never the game's random numbers)
gcol_of:
        push    bx
        push    cx
        push    ax
        xor     bh, bh
        mov     bl, al              # value 0..3
        xor     ax, ax
        mov     al, [DS_LEVEL]
        dec     ax
        cmp     ax, 3
        jb      gc1
        xor     ax, ax
gc1:    mov     cx, ax
        shl     cx, 1
        shl     cx, 1               # 4L
        mov     ax, cx
        shl     ax, 1
        shl     ax, 1               # 16L
        add     cx, ax              # 20L
        or      bl, bl
        jnz     gc2
        mov     ax, cs:[v_lfsr]
        shr     ax, 1
        jnc     gc3
        xor     ax, 0xB400
gc3:    mov     cs:[v_lfsr], ax
        and     ax, 0x0F
        add     ax, cx
        mov     bx, ax
        mov     al, cs:[bx + offset t_gcol + 4]
        jmp     gc4
gc2:    add     bx, cx
        mov     al, cs:[bx + offset t_gcol]
gc4:    mov     bl, al
        pop     ax
        mov     al, bl
        pop     cx
        pop     bx
        ret

# ---- 64C1 replacement for the ground rows: (dest ptr, pattern byte, count) ----
        .global hook_fillrow
hook_fillrow:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es
        mov     ax, [bp+4]
        sub     ax, DS_RING
        shl     ax, 1
        shl     ax, 1
        mov     di, ax
        mov     ax, cs
        add     ax, RING_PARA
        mov     es, ax
        mov     dl, [bp+6]          # pattern
        mov     cx, [bp+8]          # byte count
        call    fill_pixels
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# es:di <- cx bytes of CGA pattern dl expanded to 4*cx pixels
fill_pixels:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    bp
        xor     ax, ax
        mov     al, [DS_LEVEL]
        dec     ax
        cmp     ax, 3
        jb      fl1
        xor     ax, ax
fl1:    mov     bp, ax
        shl     bp, 1
        shl     bp, 1               # 4L
        mov     bx, bp
        shl     bx, 1
        shl     bx, 1               # 16L
        add     bp, bx              # 20L
        mov     si, cs:[v_lfsr]
fp1:    push    cx
        mov     dh, dl
        mov     cx, 4
fp2:    rol     dh, 1
        rol     dh, 1
        mov     bl, dh
        and     bl, 3
        jnz     fp3
        shr     si, 1               # value 0: pseudo-random shade from the level's noise table
        jnc     fp5
        xor     si, 0xB400
fp5:    mov     bx, si
        and     bx, 0x0F
        add     bx, bp
        mov     al, cs:[bx + offset t_gcol + 4]
        jmp     fp4
fp3:    xor     bh, bh
        add     bx, bp
        mov     al, cs:[bx + offset t_gcol]
fp4:    mov     es:[di], al
        inc     di
        loop    fp2
        pop     cx
        loop    fp1
        mov     cs:[v_lfsr], si
        pop     bp
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

# ---- 64C1 replacement used to clear the whole ground ring (dest, byte, count) ----
        .global hook_clearground
hook_clearground:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es
        mov     ax, cs
        add     ax, RING_PARA
        mov     es, ax
        xor     di, di
        mov     cx, 0x1C00
        mov     dl, [bp+6]
        call    fill_pixels
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# ---- 7743: foreground overlay colour-key copy: (seg, x bytes, y, src ptr, rows, width bytes, stride bytes) ----
        .global hook_colorkey
hook_colorkey:
        push    bp
        mov     bp, sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     ax, [bp+4]
        mov     es, ax
        mov     bx, [bp+6]
        mov     cx, [bp+8]
        call    vga_addr
        mov     di, ax
        mov     ax, [bp+10]
        call    scen_find
        jc      ck_out
        mov     si, bx
        mov     ds, dx
        mov     ax, [bp+14]         # width bytes
        shl     ax, 1
        shl     ax, 1
        mov     dx, ax              # width pixels
        mov     ax, [bp+16]         # stride bytes
        shl     ax, 1
        shl     ax, 1
        mov     bx, ax              # stride pixels
        mov     ax, [bp+12]
        mov     ah, al              # rows
        cld
ck1:    push    si
        push    di
        mov     cx, dx
ck2:    lodsb
        or      al, al
        jz      ck3
        mov     es:[di], al
ck3:    inc     di
        loop    ck2
        pop     di
        pop     si
        add     di, 320
        add     si, bx
        dec     ah
        jnz     ck1
ck_out: pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret

# ============================================================================
# variables
# ============================================================================
v_pace:   .word 0
v_lfsr:   .word 0xACE1
v_orflag: .byte 0
          .byte 0
t_gcol:
        # per level: 4 colour-map entries (CGA value 0..3) + 16 noise shades for value 0
        .include "build/gcol.s"

        .include "src/snd.s"
        .include "build/tables.s"
        .global vga_end
vga_end:
