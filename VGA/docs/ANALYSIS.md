# Commando 1.01 – graphics system analysis (for the VGA conversion)

**By Dag Erik Hagesæter / Retro Erik using GitHub Copilot in VS Code** · [YouTube: Retro Erik](https://www.youtube.com/@RetroErik)

This document records what was reverse-engineered from the **untouched** `COMMANDO.EXE` / `COMMANDO.DAT` / `START.COM`
in the `Original game files` folder. Nothing in that folder was modified. Every statement below is backed by either disassembly,
a DOSBox screenshot, or a trace/test run in the offline 8086 emulator (`tools/emu86.py`, `tools/emu_game.py`); the
scripts that reproduce the evidence are listed in the [tools table](#tools).

## 1. Conventions

| Term | Meaning |
|---|---|
| **image offset** | offset in the EXE *load image* = EXE file offset − `0200h` (the MZ header is 512 bytes). Code addresses below are image offsets = runtime `CS:IP` offsets. |
| **DS offset** | offset in the data segment. `DS = CS + 0835h` paragraphs, so **image offset = DS offset + 8350h** (EXE file offset = DS offset + 8550h). |
| **CGA pixel values** | 0 black, 1 cyan, 2 magenta, 3 white. The game only calls BIOS mode 4 (never sets the palette register), so the BIOS default palette 1 is what every PC/VGA shows. |

## 2. Program and files

* `COMMANDO.EXE` – "Game Executive run-time Version 2.01 (Quicksilver Software)", *Commando 1.01 (1987-02-25)*, a compiled-C
  game with hand-written assembler graphics primitives. The MZ header declares a 71,071-byte image (`CS:IP 0000:0010`,
  `SS:SP 181A:03E8`, `minalloc 06FFh`); the file is padded to 153,600 bytes with data that is **not** loaded by DOS.
  Only two relocations exist (both the `DS` value).
* `COMMANDO.DAT` – a 160 KB (40 track × 8 sector) floppy image. `START.COM` (identical size/purpose to `STARTC.COM`) hooks **INT 13h**
  and serves drive-0 sector reads from the DAT (`offset = track·4096 + (sector−1)·512`), and hooks **INT 16h** (the keys `Q`/`q` leave the game).
  It then `EXEC`s `COMMANDO.EXE`.
* **The DAT also carries the level graphics.** Level *n* is loaded by `393F` through INT 13h from tracks `24+4n … 27+4n`
  (3.5 tracks = 14,336 bytes to `DS:9454`). Only n = 1, 2, 3 exist (tracks 28–39). The DAT embeds a complete copy of `COMMANDO.EXE` at offset `2000h`, so these
  tracks coincide with the *tail of the EXE file* (the part DOS does not load, EXE file offset `1A000h…`); the remaining tail is filler.
* The game reads input through BIOS `INT 16h` (`7551` = key ready, `7568` = get key) and a joystick port routine (`81B0`).

## 3. Display model

| Item | Finding |
|---|---|
| Mode | `INT 10h` AH=0 AL=4 (320×200, 2 bits/pixel) from `69E3` (called at start-up); restored to mode 3 by `6AB0`. |
| Video memory | `B800:0000` (even rows) / `B800:2000` (odd rows), 80 bytes per row, 4 pixels per byte, high bits = left pixel. |
| Back buffer | **One** 16 KB "RAM screen" in CGA layout, allocated with `INT 21h AH=48h` (segment kept in `DS:FA1E`), plus the static **background** copy kept in the same layout. |
| Presenting | `8139` copies the RAM screen to `B800` (100 × 2 rows × 40 words), called through `75D2`. A full-screen present happens every game frame. `8172` waits for vertical retrace (port `3DAh`). |
| X coordinate | Object X is stored in **2-pixel units** (`bl>>1` = byte column; bit 0 selects the odd-x image, i.e. +2 pixels). Y is in pixels (`77C1` looks up `(y/2)·80` from a table at `77D1`). |

Typical screen layout (320×200): 40-pixel decorative **side art** at x = 0 and x = 280 (five stacked pods per side),
the **playfield frame** (x ≈ 44…275, y ≈ 9…160) built from 8×8 frame tiles, and the **score panel** (y ≈ 168…198).

## 4. Sprites (data segment, mask/value pairs)

All characters, vehicles, effects, bullets, side art and panel icons are sprite records in the data segment (`DS:1B52…9100`):

```text
+0  word  odd_off     ; odd-x image header lies at (record + 2 + odd_off); 0 = odd uses the even image
+2  byte  height
+3  byte  width_bytes ; 4 CGA pixels per byte
+4  height * width_bytes * (mask byte, value byte)         ; even-x image
        [byte height, byte width_bytes, pairs]              ; odd-x image (2 pixels shifted right)
draw:  screen_byte = (screen_byte AND mask) OR value        ; mask bit-pair 11 = transparent
```

* **90 sprite records** were located (`tools/scan_sprites.py` + `tools/catalog_sprites.py`, catalog in `extracted/sprites_catalog.json`,
  raw record bytes in `extracted/sprites/`). They are grouped in [Section 12](#12-asset-inventory).
* The odd-x image is the even image shifted by 2 pixels with the right-hand pixels clipped to the byte width (22 sprites match
  exactly, 28 differ by < 6 % of pixels at the clipped edge). One VGA bitmap per sprite is therefore enough: draw it at pixel
  `x_units · 2` regardless of parity.
* Draw primitives: `7C3F` draws a record (jump-table unrolled by row count at `7BF7`); `7899` **restores** an object's old footprint from the background
  RAM segment (same unrolling); `75EA` renders all objects straight to `B800`; `765C` does the same into the RAM screen.
  Each of the 25 slots in the object array (8-byte records: `+0` new sprite pointer, `+2/+3` x/y, `+4/+5` last x/y, `+6` last sprite; `FFFFh` = inactive)
  is erased and redrawn every frame.

## 5. Fonts, tiles and menu bitmaps

| Asset | Where | Format |
|---|---|---|
| Large font | `DS:00B6 + 36·code`, codes `01…5F` used | 12×12 pixels, 3 bytes × 12 rows, pixel value 3 = ink; the colour comes from a nibble table at `DS:9230` (`6D4E`/`6DBF`: `screen = (screen AND NOT ink) OR (ink AND colour)`). Codes: `01` block, `02` target cursor, `2E` `.`, `30–39`, `41–5A`, `5C` heart, `5D` left arrow, `5E` "END", `5F`. |
| Small tiles | `DS:0016 + 16·(code−80h)`, codes `80…89` | 8×8 pixels. Used by `6C7C` as 8×8 "text" to draw the **playfield and score-panel frames** (codes `82–89` in `5239`). |
| Title bitmaps | **code segment** pointer table at `CS:193C` (5 words) → `[h][w]` + mask/value pairs, drawn by `18A3` | `COMMANDO` logo in four pieces (64×44, 48×36, 60×36, 68×44) and the 60×58 hero on a crate. Y is the *bottom* pixel row, X a byte column. |
| Text callers | `6C7C`, `6CA2` (string) etc. | position in pixels, glyph code, colour 0–15 |

## 6. Scenery and ground (level data from the DAT)

* The playfield is a **scrolling ground buffer**: `DS:DCE2`, 56 bytes (224 px) × 128 rows, 2 bits/pixel. Every frame `76D1` copies it (with wrap-around) into the RAM screen.
* A second buffer, `DS:CD60`, is 28 bytes × 128 rows and is **never displayed** (see §7).
* Scenery objects are described by 14-byte records in the level data. The strip builder `50E4` composes one new ground row per scroll step: for each active record it copies one
  source row of `width` bytes into the 56-byte buffer (`6498` = copy, or `5F5D` = OR-copy when the record's OR flag is set; trees are OR-blitted so black is transparent) **and** one row of
  `ceil(width/2)` bytes from a *second* bitmap into the 28-byte buffer.

```text
rec+2  byte  column in the 56-byte row          rec+8  word  DS pointer of the 56-wide bitmap (display)
rec+3  word  DS pointer of the half-width bitmap (attributes)   rec+B  byte  1 = OR-blit, 0 = copy
rec+5  byte  bitmap height in rows               rec+C  byte  width in bytes of the 56-wide bitmap
rec+6  word  first map row of the object
```

Level 1 (jungle, 4 records): two palm trees (44×56, OR-blit), a rock/slab (40×28) and a pebble (12×5).
Level 2: no scenery records; the playfield is a cyan/black 1-pixel checker dither. Level 3: five scenery bitmaps (gate 56×52, wall bands, …) over the same dither.
Extracted bitmaps: `extracted/scenery_*.bin`, atlas `atlas/scenery_cga.png`.

## 7. What gameplay logic reads (collision audit)

Method: the emulator records every **read** of selected memory areas together with the reading instruction (`tools/audit_reads.py`,
`tools/audit_sprite_reads.py`), plus a negative test (`tools/test_sprite_independence.py`).

| Data | Readers during gameplay | Conclusion |
|---|---|---|
| Sprite records (`DS:1B52…9100`) | draw loops (`7C3F`, `7899`) **and** logic that reads only record bytes **0, 1, 2, 3 and the odd-image width byte** (offset `odd_off+3`) – i.e. only the header (odd offset, height, width) | Object-vs-object collision (`1610…17xx`, `16A5`), edge tests and animation use **rectangles from the headers**. Pixel/mask bytes are never read by logic. |
| RAM screen / video RAM | only the draw routines (`7899/7C3F` merge into it) and the present copy `8139` | No pixel-based collision on the screen. |
| Ground buffer `DS:DCE2` | only `76D1` (display blit) | purely visual |
| **Attribute buffer `DS:CD60`** (28 bytes/row) | `4F58…50DE` – the **scenery collision test**: for an object it indexes `row = y + sprite height + scroll`, `byte = x>>2`, and tests the 2-bit cell selected by `x&3` (mask table `DS:1B30`) | **Gameplay depends on this layer.** It is built from the *second* bitmap of every scenery record, straight from the level data. It must be kept exactly as loaded; the new VGA art only replaces the *display* bitmap. |

**Negative test:** scrambling the mask *and* value bytes of **all 90 sprite records** (headers intact) and running the game for 6 M (level 1) /
4 M (level 3) instructions of gameplay produced **0 differing bytes** in `DS:9250…FFFF` (every variable, object table, score, random seed, scroll position and scenery buffer)
and an identical instruction count, while the frame itself differed (`analysis/collision_independence_L1.txt`, `…_L3.txt`). Therefore:

* the original CGA sprite **headers must stay in the data segment** (the VGA renderer looks the new artwork up by the original record address); the pixel/mask bytes are free;
* the scenery **attribute layer** must be kept unchanged;
* the VGA bitmaps must keep the original width/height so that the draw/erase rectangles agree with the logic's collision rectangles.

## 8. CGA-specific code that a VGA renderer must replace

| Routine (image offset) | Role | Callers / notes |
|---|---|---|
| `69E3` / `6AB0` | set mode 4 / restore text mode | start-up / exit |
| `7590` | fill the 16 KB RAM screen with one byte | scene set-up |
| `75D2` → `8139` | copy RAM screen → `B800` | every frame |
| `77AA` | clear `B800` | |
| `76D1` | ground buffer → RAM screen with wrap (CGA row interleave `+2000h`) | every frame |
| `7743` | colour-key copy (0 = transparent) | called from `1829` |
| `7899`, `7C3F` and the unrolled bodies `7A…`, `7C85…` | restore footprint from background / mask-value sprite blit | `75EA`, `765C` |
| `18A3` | menu bitmap blit (code-segment source) | title screen |
| `6D4E`, `6DBF` | glyph draw to CGA / 48-byte-stride buffer | text wrappers `6C46`, `6C7C`, `6CA2`, `6CD8`, `6D0B` |
| `50E4`, `5F5D`, `6498`, `64C1` | ground strip composer and copy helpers (2 bpp rows) | scene scrolling |
| `5239` | gameplay scene builder (frame tiles, side art, score panel) | start of each game |

Everything else (object logic, AI, random numbers, timing, sound, keyboard) is independent of the pixel format.

## 9. Proposed VGA architecture

```text
Original   game logic -> CGA primitives (2 bpp, B800 layout)                 -> BIOS mode 4
VGA        same game logic -> VGA primitives (8 bpp, linear 320x200)         -> mode 13h + 256-colour DAC
                          \-> pre-converted artwork (same sizes, same ids)
```

1. **Frame buffers:** one 64,000-byte linear 8 bpp RAM screen and one background copy (4,000 paragraphs each, allocated with the same `INT 21h/48h` call) replace the 16 KB ones. Present = `rep movsw` of 32,000 words to `A000:0000`.
   Because mode 13h has exactly the same 320×200 geometry, every game coordinate maps 1:1 (`pixel x = 2·x_units`, no row interleave: `offset = y·320 + x`).
2. **Sprites:** keep the CGA records for headers/logic. A new asset table maps *original record address → VGA bitmap* (`[w][h]` + 8-bit pixels, index 0 = transparent colour-key; index 0 is reserved and never used by artwork). `7C3F` becomes a colour-keyed byte copy; `7899` becomes a row copy from the background.
3. **Ground and scenery:** the strip composer keeps the original 2 bpp data for the **attribute** buffer (collision) and gets an 8 bpp twin for display (224×128 = 28 KB). Scenery art is replaced by 8 bpp bitmaps with the same sizes, OR-blit bitmaps use colour key 0; the ground fill colour per level comes from the level's palette.
4. **Text/tiles:** glyphs and 8×8 frame tiles are replaced by 8 bpp versions; the colour argument selects a palette ramp.
5. **Palette:** the 256-entry palette (`preview/palette_vga.png`) is set once with `INT 10h AX=1012h`; ramps are contiguous so later effects (hit flash, fade) can be done through the DAC.
6. **Code placement:** the new routines are placed in an extra code segment appended inside the EXE's existing padding (header page count and a relocation table are updated in the *copy*); the original primitives get 5-byte far-call/jump trampolines. The original `COMMANDO.DAT` level data is reused untouched (VGA bitmaps for scenery live in a new data file/segment keyed by the same data-segment pointers).
7. **Speed:** 8 bpp moves four times as many bytes as the CGA path on a 4.77 MHz 8088. The design keeps the original dirty-rectangle behaviour (only footprints are restored/redrawn) and presents the buffer once per frame; the full-screen present is the main cost and will be measured in DOSBox cycle counts before any further optimisation.

## 10. Test strategy

* **Offline emulator regression** (`tools/emu_game.py`): runs the real game headless, deterministic, with INT 13h/16h/21h/10h emulation. A patched VGA build must keep the *DS variable region identical* to the original after N frames (same method as the sprite-scramble test) – this proves "same game logic".
* **Render equivalence:** because the CGA path is deterministic, the VGA path can be validated by rendering the original CGA frame, mapping each CGA pixel back through the sprite/bitmap ids, and comparing the VGA frame at the *pixel-ownership* level (same pixels covered).
* **DOSBox** (`tools/dosbox_shot.ps1`): starts the game with `START.COM`, sends keys and takes PNG screenshots (`Ctrl+F5`). Used for the original reference screens and later for the VGA build smoke tests (mode 13h, palette, startup, no crash).

## 11. Open points

* The exact in-game *meaning* of a few sprites (supply crate `7F74`, skull `81E2`, gun `88BA`, grenade stock piles) is inferred from appearance/position; the labels in the catalog carry a confidence field.
* Level 2/3 ground fills are 2-colour dithers built from the level data's row patterns; the VGA art for them is proposed as 2-tone dithers and will be generated at the same stage as the scenery.
* The meaning of record byte `+0Ah` and the exact role of the `DS:1B30` mask table are documented only as far as needed for collision preservation.

## 12. Asset inventory

| Group | Count | Size(s) | Where | Notes |
|---|---|---|---|---|
| Hero (magenta) | 17 walk/aim + 4 firing + 4 arms-up + 1 down | 16×20…24×22 | `DS:3DAC…5DD0`, `36CC`, `37D8`, `52D0` | firing frames add cyan weapon pixels |
| Enemy soldiers (cyan) | 17 + 2 arms-up + 4 crouched/lying + 4 dying | 16×16…24×22 | `DS:1B52…3D28` | |
| Vehicles | jeep 48×20, truck 48×16, motorbike 2× 36×20, gun 20×19 | | `84DC`, `8F5A`, `7B32/7C9E`, `88BA` | |
| Pickups/panel | supply crate 20×21, grenade 8×7, stock piles 10 | | `7F74`, `739A`, `64B6…7144` | `64B6` = blank (clear) piece |
| Effects | 3 bursts, 4 blasts, 1 skull, 6 bullets, 2 point pop-ups | 4×2…32×9 | `804A…8AD4` | |
| UI | cursor 36×32, side art 2× 40×35, title hero 60×58, title logo 4 pieces | | `8AD4`, `5F36/61F6`, `73D8`, `CS:193C` | |
| Fonts | 76 large glyphs 12×12, 10 tiles 8×8 | | `DS:00B6`, `DS:0016` | |
| Scenery | 9 bitmaps (+ 9 attribute bitmaps) | up to 56×52 | DAT tracks 28–39 | |

Atlases of the original graphics are in `atlas/`; extracted binaries in `extracted/`.

## Tools

| Tool | Purpose |
|---|---|
| `tools/emu86.py`, `emu_game.py`, `emu_script.py` | 8086 emulator + game harness (INT 10h/13h/16h/21h, timer, key injection, CGA frame renderer) |
| `tools/trace_writes.py`, `trace_ground.py`, `trace_strips.py`, `trace_records.py` | which instruction draws what (video RAM, RAM screen, ground buffer, scenery records) |
| `tools/audit_reads.py`, `audit_sprite_reads.py`, `test_sprite_independence.py` | collision-dependency evidence (Section 7) |
| `tools/scan_sprites.py`, `catalog_sprites.py`, `defs.py` | locate / classify sprite records |
| `tools/extract_scenery.py`, `extract_misc.py`, `atlas_orig.py`, `atlas_fonts_menu.py` | extraction + original atlases |
| `tools/vga_palette.py`, `vga_art.py`, `make_previews.py` | **proposed** VGA art + preview sheets (not used by the game) |
| `tools/dosbox_shot.ps1`, `montage.py`, `mzinfo.py`, `dis.py`, `disasm.py`, `index_funcs.py` | DOSBox automation, helpers, disassembly |
