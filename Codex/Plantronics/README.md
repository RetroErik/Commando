# Commando Plantronics ColorPlus Patch

An experimental 320 × 200, 16-color rendering patch for the 1987 DOS release of *Commando*. The original game draws the same sprite shapes and runs its original gameplay code. This project colors the hero, enemies, projectiles, effects, score, and decorative art separately on a Plantronics ColorPlus-compatible card.

**By Dag Erik Hagesæter / Retro Erik using Codex in VS Code** · [YouTube: Retro Erik](https://www.youtube.com/@RetroErik)

![Platform](https://img.shields.io/badge/Platform-MS--DOS-blue)
![CPU](https://img.shields.io/badge/CPU-8086%2F8088-green)
![Language](https://img.shields.io/badge/Language-8086%20assembly%20%2B%20PowerShell-orange)
![License](https://img.shields.io/badge/License-original%20game%20rights%20reserved-lightgrey)

## Overview

Commando sets CGA mode 4. During active play it draws soldiers into a 16 KB RAM screen, then copies that screen to the normal `B800:0000` video bank. Other scenes can draw directly to video memory. The ColorPlus extension adds a second 16 KB pixel bank at `BC00:0000` without changing the 320 × 200 address math.

This patch keeps the game's original drawing pass. It changes the color-value bytes in copied hero and enemy sprites, so the game itself draws the correct lower ColorPlus bits. A precomputed upper-color version of those sprites is held by the loader in RAM. The loader prepares the extra bank in a RAM shadow, then transfers both video banks together for each changed word. The original ground construction and scenery compositing are retained; color-0 background pixels stay black. Both `COMMANDO.EXE` and its byte-identical copy embedded in `COMMANDO.DAT` are patched **only in `run`**. The original files in `Commando` are never written.

| Component | Details |
|---|---|
| Target | MS-DOS, 8086/8088-compatible CPU |
| Display | Real Plantronics ColorPlus or compatible 86Box adapter |
| Resolution | 320 × 200 pixels, unchanged |
| Source revision | Commando 1.01, 1987-02-25; exact SHA-256 checks in `patch.ps1` |
| Background and borders | Original color-0 background stays black throughout the screen; other static colors still use their CGA pixel codes |
| Hero | Red body, white details, and black belt |
| Enemy soldiers | Two blue shades with a white belt |
| Objects | White bullet; dark/light-gray rocks; dark-red/yellow/light-gray hit effects |
| Screen art | Dark-red/brown side art; dark-cyan frames and score text; cyan life marks under investigation; original-color soldier icon |
| Menu | Green text and formerly brown logo pixels in the copied game files |
| Disk changes | `run/COMMANDO.EXE`, `run/COMMANDO.DAT`, `run/STARTC.COM`, `run/STARTC0.COM` |
| Added memory | 55,040-byte temporary `.COM` diagnostic loader including 16 KB shadows for both banks, upper-color sprite data, palette tables, and its stack |

## Features

- The original sprite positions, masks, width, height, and gameplay routines remain in use. Color-value bytes change in 41 soldier frames, one small rock frame, and 11 projectile, effect, or rock frames and their odd-x variants.
- Hero and enemy animation blocks receive different ColorPlus color rules, regardless of object slot.
- Sprite transparency is retained in both video banks, including the odd-x sprite variant. Previous sprite footprints are restored in the extra bank before new ones are painted.
- The original scrolling-ground and scenery drawing instructions are retained, so bullets and trees keep their original masks and draw order.
- The copied RAM screen receives side-art and cyan frame colors before the paired video transfer. Changed score words are recolored before transfer as well, so old score digits clear in both banks.
- The current diagnostic build samples 16 bytes near the five small life marks from each video bank and records them in `PLTRACE.TXT`. The earlier fixed score-panel pass was removed because it slowed play without restoring the marks.
- The copied menu logo sprites retain red pixels and map brown pixels to green; brown menu text also becomes green. The two gameplay exit hooks clear both video banks before the menu draws.
- The graphics-mode and RAM-to-video copy hooks initialize the extra plane during screen changes. The copy hook updates both planes as adjacent word writes, and skips unchanged lower-bank data. The game-state hooks enable soldier colors at the actual gameplay entry and disable them when its state loop leaves play.
- The loader restores interrupt vectors, disables ColorPlus mode, and turns off the PC speaker after a normal exit.
- The patcher checks original hashes and every changed byte before producing copies.
- The copied original launcher reports a hidden DOS load error through its exit code and lets DOS handle its own floppy reads. Its old crack banner is suppressed in the copy.

## Quick Start

### Requirements

- The untouched `../../Original game files/COMMANDO.EXE`, `COMMANDO.DAT`, and `STARTC.COM` files supplied in this workspace.
- A Plantronics ColorPlus card with an RGBI monitor, or a working ColorPlus setup in 86Box.
- To rebuild: Windows PowerShell and GNU `as.exe`, `ld.exe`, and `objcopy.exe` from Free Pascal 3.2.2 at `C:\FPC\3.2.2\bin\i386-Win32`.

### Build

From PowerShell in this folder:

```text
.\build.ps1
.\test.ps1
```

`build.ps1` prepares the lower- and upper-color sprite assets and screen-color tables, assembles `PLANTRON.COM`, and invokes `patch.ps1` to populate `run`. `test.ps1` runs a graphics smoke test in DOSBox 0.74-3; DOSBox verifies the copied sprite bytes, interrupt, and memory logic but does **not** show ColorPlus output.

### Run on ColorPlus hardware or in 86Box

Copy the four files from `run` into one DOS directory, then run:

```text
STARTC.COM
```

Keep all four files together. `STARTC.COM` is this project's temporary loader; `STARTC0.COM` is a diagnostic copy of the original launcher. Use the supplied 86Box ColorPlus adapter setting for visual color tests. The user tested at 10 MHz and then raised EuroPC to 16 MHz because gameplay had become noticeably slow. Measure responsiveness at the intended hardware speed. Test on a real card after emulator testing.

For the local EuroPC setup at `D:\86Box-Windows-64-b9001`, `Start-EuroPC-Test.cmd` starts an isolated copy of that VM. Its copied hard disk runs `A:\STARTC.COM` automatically. `update_floppy.ps1` prepares a byte-verified copy of the 720 KB floppy before it is placed at the configured image path. `make_autoboot.ps1` changes only `AUTOEXEC.BAT` in a copied VHD; the original EuroPC VHD and VM configuration are untouched. This launch still needs a visible 86Box session for a human color check.

The loader writes `PLTRACE.TXT` in the current DOS directory. It records whether DOS reached the original launcher and, if that launcher returns, its exit code, graphics-hook counts, intro clears, and gameplay starts and leaves. `frames` counts recoloring passes reached through direct rendering or screen copies. `DOS EXEC failed: AX=...` means the outer loader could not start `STARTC0.COM`. A child return code from `80h` upward means that DOS could not load `COMMANDO.EXE`; subtract `80h` for the DOS error number. For example, `code=82` means DOS error 02, file not found. The trace cannot be created on a read-only disk; the exit line is also printed at the prompt.

## Controls and color rules

The game controls are unchanged. The extension uses ColorPlus port `3DDh`, bit 4, for 320 × 200 × 16 mode. The original CGA pixels remain in `B800:0000`. The extra plane is at `BC00:0000` while bit 6 remains clear.

| Game pixels | Plantronics result in this build |
|---|---|
| All color-0 background pixels | Black, as in the original game |
| Palm trees and terrain | Original dark-green leaves, dark-red trunks, and brown ground dots |
| Side decoration | Dark red and brown |
| Frames and score text | Dark cyan; the five cyan life marks remain too dark in 86Box; the larger soldier icon retains its source colors |
| Menu logo and brown text | Brown pixels become green; the logo retains its original red pixels |
| Red hero sprite frames | Red body stays red; other details become white; belt row stays black |
| Green enemy sprite frames | Green body becomes blue; other highlights become bright blue; belt becomes white; black outline stays black |
| Small projectile (`804Ah`) | White |
| Rock-like sprites (`739Ah`, `8478h`, `84AEh`) | Dark gray and light gray |
| Hit and explosion frames (`8058h`–`83F4h`) | Dark red, yellow, and light gray |

The [decoded sprite atlas](test/sprite_atlas_current.png) shows representative animation frames and small objects with an approximate RGBI palette. The sprite records identify these groups:

| Object group | Current colors in the black-background build | Status |
|---|---|---|
| Hero animation frames | Red body, white details, black belt and outline | Recolored in copied sprite data and upper-bank assets |
| Enemy soldier frames | Blue body, light-blue details, white belt, black outline | Recolored in copied sprite data and upper-bank assets |
| Small projectile (`804Ah`) | White | Recolored sprite record and upper-bank asset |
| Rock-like objects (`739Ah`, `84AEh`, `8478h`) | Dark gray and light gray | Recolored sprite records; exact game role is not fully confirmed |
| Hit or explosion frames (`8058h`–`83F4h`) | Dark red, yellow, and light gray | Recolored sprite records; precise sequence is not fully confirmed |
| Larger mixed-color item (`7F74h`) and jeep (`84DCh`) | Original dark-red, dark-green, and brown colors | Not selected for recoloring |
| Palm trees, grass, ground dots | Dark green foliage or grass, dark red trunks, brown dots | Scenery drawn separately from soldier sprite blocks |
| Side decoration | Dark red and brown | Screen-buffer palette transform |
| Frames and score text | Dark cyan; the five cyan life marks need further correction; larger soldier icon keeps original colors | Screen-buffer palette transform |
| Menu logo and brown text | Brown pixels become green; original red logo pixels remain red | Changed only in copied game files |

The background color experiment was removed after 86Box showed lost bullets and incorrect scenery under moving soldiers. The game builds its scrolling ground separately and combines palm pixels with it using bitwise OR, so filling or recoloring that buffer changed how those objects appeared. The present build keeps those game instructions unchanged. The user confirmed in 86Box that the dark-red/brown side art and dark-cyan score look good, and that F1 returns to a clean menu. The five small life marks still look too dark in 86Box even though synthetic DOSBox checks pass; the current read-only diagnostic records their actual video-bank bytes for the next correction. The precise colors of every projectile and effect still need a gameplay check.

## Technical notes

`COMMANDO.DAT` embeds the complete EXE at offset `2000h`. The patcher changes the selected call sites and sprite color-value bytes in both copies. A six-byte trampoline in an unused alignment gap calls the original direct-video object renderer, invokes `INT 60h`, and returns. `INT 61h` replaces the game's mode-4 call; `INT 62h` replaces its full-screen RAM-to-video copy and performs active-play upper-bank rendering. `INT 63h` preserves the RAM clear at the pre-play scene setup. `INT 64h` performs other RAM clears and resets the extra video bank. `INT 65h` clears the pre-play scene. `INT 66h`–`67h` preserve the entry and exit of state `02h`; `INT 68h`–`69h` do the same for player-controlled state `04h`. These hooks control when stale object records may recolor soldiers and clear both video banks on the way back to the menu. The temporary loader installs and later restores ten interrupt vectors. Both the temporary loader and copied launcher explicitly pass their DOS EXEC parameter blocks in `ES:BX`. The copied launcher also adds a DOS busy check to its floppy interrupt and reports the game load result. It retains the original cleanup path. See [ANALYSIS.md](ANALYSIS.md) for the verified offsets and sprite layout.

The MZ relocation table shows that the game's data segment begins `8350h` bytes into the loaded image; with the `200h` MZ header, a sprite at data offset `1E12h` is at EXE file offset `A362h`. The asset builder follows each sprite header and its odd-x variant, changes only value bytes for the lower bank, and keeps a separate precomputed upper-color copy. The game therefore draws the recolored lower pixels through its original renderer. The mode hook initializes the 16 KB upper video bank and a RAM shadow for each bank. In active play, the copy hook updates moving-object footprints in the upper shadow and records the changed span on each scanline. It transfers the upper and lower word at each dirty position as a pair, then uses `REPE CMPSW` to skip long unchanged areas of the lower screen and transfers any other changed words as pairs. The first copy after a mode change or scene clear transfers the full visible image once. The screen-art overlay scans static frame and side-art coordinates on that full copy; later it processes changed score words before their transfer. A diagnostic samples 16 fixed score-area bytes after each relevant hook without writing video RAM. The patch does not alter animation timing or collision state.

The ColorPlus control register is write-only, so this build assumes a compatible card. A standard CGA card is not a supported target. The [Paradise PVC4 data sheet](https://bitsavers.trailing-edge.com/components/westernDigital/_dataSheets/PVC4.pdf) documents port `3DDh` and bank selection for ColorPlus-compatible hardware. [Color Graphics Adapter Notes](https://www.seasip.info/VintagePC/cga.html#plantronics) describes the low and high pixel-bit arrangement.

## Project layout

| Path | Purpose |
|---|---|
| `plantronics.s` | 8086 loader, ColorPlus mode setup, and sprite recoloring |
| `sprite_assets.ps1`, `*_low.bin`, `*_high.bin` | Verified generation of disk lower-color sprites and loader upper-color sprites |
| `screen_palette.ps1`, `screen_tables.bin` | Lookup tables for dark-red/brown side art and dark-cyan frames and score text |
| `menu_assets.ps1`, `menu_low.bin` | Verified brown-to-green menu logo and soldier pixel preparation |
| `launcher_probe.s` | Diagnostic code added only to the copied original launcher |
| `build.ps1`, `patch.ps1` | Build and version-checked copy patching |
| `test_assets_stub.s`, `test_leave_stub.s`, `speaker_probe.s`, `test.ps1` | DOSBox asset, memory, interrupt, jump, and speaker-cleanup smoke tests |
| `update_floppy.ps1`, `make_autoboot.ps1`, `Start-EuroPC-Test.cmd` | Verified local floppy staging and isolated EuroPC automatic game launch |
| `ANALYSIS.md` | Disassembly findings and implementation limits |
| `run/` | Files to copy to a ColorPlus DOS machine or 86Box drive |

## Screenshots

The user's 86Box screenshots confirmed ColorPlus mode, a red hero with a black belt, blue enemies, and clean motion with the paired-bank transfer. The user confirmed that the restored black background, palms, bullets, and moving soldiers looked correct. An earlier build left soldier pixels briefly in the menu; the user confirmed that F1 now returns to a clean menu. The brown-ground experiment produced striped ground, missing palms, lost bullets, and artifacts when soldiers overlapped scenery, so it was removed. After correcting the frame rows and side-art bounds, the user confirmed that the dark-cyan frame edges match its bars and that the dark-red/brown side art looks good. DOSBox 0.74-3 does not render the ColorPlus extension and is used only for DOS memory and program-flow tests.

## Testing guidance

1. Run `test.ps1`; it should print `PASS: precolored assets, paired copy, black background, play clears, and round exit.`, `PASS: both state exits clear video and resume at original jump targets.`, and `PASS: speaker off after loader exit.` The test checks hero white details and black belt, the white enemy belt, a moving white bullet, a gray rock, dark-cyan frame and score pixels, dark-red/brown side pixels, synthetic life marks from RAM drawing, the original-color soldier icon, clearing and redrawing score digits in both banks, CGA green menu bytes, black extra-bank background, unchanged scrolling-ground opcodes, recovery when video RAM no longer matches the saved frame, both play-state entries and cleared exits, and speaker cleanup.
2. In 86Box, verify the opening screen, player movement, enemy movement, scrolling, F1 return, game-over return, and transitions between title and gameplay. Check for colored trails or missing pixels.
3. Compare the patched build with the untouched game at the same positions. The shapes and timing should match, aside from any performance cost of the extra video pass.
4. On a real card, check both an original 4.77 MHz or faster XT and a faster PC if available. Note frame rate, palette, and whether `STARTC.COM` returns to a readable DOS prompt. The 86Box visual tests currently use 16 MHz after 10 MHz felt slow.

## Credits, license, and contributing

The original *Commando* game is copyrighted by its rights holders and is not licensed by this patch. This folder is a local preservation experiment; redistribute only files you have rights to share. Patch code and documentation: **By Dag Erik Hagesæter / Retro Erik using Codex in VS Code**. Hardware observations and palette suggestions are welcome via [Retro Erik on YouTube](https://www.youtube.com/@RetroErik).
