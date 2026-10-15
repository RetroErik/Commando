# Commando CMS sound project

CMS/Game Blaster sound experiments for the 1987 DOS release of *Commando*. **DOS mode** keeps the game's original PC speaker arrangement and effects. **SID mode** plays a three-voice CMS adaptation of Rob Hubbard's C64 arrangement while retaining the DOS game's effects. **SID noise test** uses the second Game Blaster chip to give each SID voice an independently clocked noise source. **SID envelope test** adds approximate SID attack, decay, sustain, and release volume changes; listening found it closer to the C64 recording. **SID full** loads the eight-minute envelope score from a separate file. **SID M toggle** also lets the game's `M` key mute and restore CMS music while effects continue. DOSBox listening confirmed that control. Real-hardware testing remains.

**By Dag Erik Hagesæter / Retro Erik using Codex in VS Code** - [YouTube: Retro Erik](https://www.youtube.com/@RetroErik)

![Platform](https://img.shields.io/badge/Platform-MS--DOS-blue)
![CPU](https://img.shields.io/badge/CPU-8086%2F8088-green)
![Language](https://img.shields.io/badge/Language-assembly%20%2B%20C%23%20%2B%20PowerShell-orange)
![License](https://img.shields.io/badge/License-undecided-lightgrey)

## Overview

The project patches **copies** of Quicksilver Software's `COMMANDO.EXE` version 1.01 (1987-02-25) and `COMMANDO.DAT`. DAT embeds the complete EXE at offset `2000h`, so both copies need the same sound patches. A temporary DOS `.COM` loader installs the CMS interrupt handlers, runs the original startup program as `STARTC0.COM`, and restores the vectors on normal exit. The familiar `STARTC.COM` command starts the selected build from its own directory. **Use SID M toggle for the current best C64 arrangement.**

| Component | Details |
|-----------|---------|
| Target | DOS, 8086/8088 instruction set |
| Sound card | CMS/Game Blaster compatible, two SAA1099 chips, I/O base `220h` |
| DOS mode | Original mono PC speaker arrangement and effects on CMS channel 0 |
| SID mode | C64 subtune 1 on CMS channels 1–3; original DOS effects on channel 0 |
| SID noise test | SID voices on chip 0 channel 3 and chip 1 channels 0/3; effects on chip 0 channel 0 |
| SID envelope test | Same chip mapping as the noise test, with 3-bit precomputed volume envelopes; four-minute loop |
| SID full | Eight-minute envelope score in external `SIDENV.BIN`; two extra conventional-memory blocks |
| SID M toggle | SID full sound with `M` controlling CMS music; game effects remain independent |
| SID source | The supplied `../Original game files/Commando.sid` file, credited to Rob Hubbard |
| Score | 24,050 PAL frames, about 8 minutes before looping; 48,789 bytes |
| Game revision | EXE SHA-256 `4F53975ABF756A27BA94713C32134F501F5349A80798151E78666FA6A6D52D4E`; DAT SHA-256 `E92EC0D64715DEADA88495E5415634FDE05B155C3EDEDAE2B0E00844A26AAAE9` |
| Hardware performance | 10 MHz XT is the initial target; actual speed remains to be measured on hardware |

## Features

- Separate run directories and launchers prevent accidental mode mixing.
- DOS mode redirects the game's speaker pitch and gate writes to CMS without changing its sequencing.
- SID mode converts the C64 file offline into compact CMS note events, then advances them from the game's existing timer. It preserves the game's effects.
- The SID noise test clocks each CMS noise source from its voice's tone frequency, rather than using a single fixed noise rate. This is an experimental instrument improvement.
- The SID envelope test also retains note release tails. Its shorter four-minute score fits a DOS `.COM` file for listening tests.
- SID full keeps the improved envelopes across the eight-minute score. The loader reads the score before the game starts; no DOS file calls occur in the timer interrupt.
- SID M toggle starts with CMS music on. Pressing `M` mutes or restores that music immediately; the game's separate sound-effects switch still works.
- DOS mode plays a short CMS test tone before the game starts; SID mode starts without it.
- Original game and SID files stay untouched. The patcher checks exact hashes and byte locations before writing copies.
- The loader silences CMS and restores its software interrupt vectors after a normal game exit.

## Quick Start

### Requirements

- Original `../Original game files/COMMANDO.EXE`, `COMMANDO.DAT`, and `STARTC.COM`. SID mode also uses `../Original game files/Commando.sid` when regenerating the score.
- A real DOS machine with a CMS/Game Blaster compatible card at `220h`, or DOSBox 0.74-3 with Game Blaster enabled.
- To rebuild: Windows PowerShell, GNU `as.exe`, `ld.exe`, and `objcopy.exe` from Free Pascal 3.2.2 at `C:\FPC\3.2.2\bin\i386-Win32`. Score regeneration uses PowerShell's C# `Add-Type`.

### Build

From PowerShell in this directory:

```text
.\build.ps1
.\patch.ps1
```

`build.ps1` regenerates the scores from `Commando.sid` if their binary files are absent. To regenerate them explicitly, run `tools\SidDump\generate-sid-score.ps1` and `tools\SidDump\generate-sid-envelope-score.ps1` before building. Each run directory contains a CMS loader named `STARTC.COM`, the unchanged original starter as `STARTC0.COM`, and version-checked copies of EXE and DAT.

### Run in DOSBox

Double-click the launcher for the desired mode:

```text
RUN_DOSBOX.BAT
RUN_SID_DOSBOX.BAT
RUN_SID_NOISE_DOSBOX.BAT
RUN_SID_ENVELOPE_DOSBOX.BAT
RUN_SID_FULL_DOSBOX.BAT
RUN_SID_TOGGLE_DOSBOX.BAT
```

`RUN_SID_TOGGLE_DOSBOX.BAT` is the recommended SID test. The other SID launchers preserve the earlier builds for sound comparisons.

The included DOSBox configs set `sbtype=gb`, `sbbase=220`, and `pcspeaker=false`. The launchers mount separate run directories. The test windows have distinct titles, including **CODEX SID M TOGGLE - COMMANDO**. A launcher closes the previous Codex DOSBox session before starting another, without affecting another AI's session.

### Run on real hardware

Copy every file from the desired run directory into a separate DOS directory, then run:

```text
STARTC.COM
```

Use a CMS/Game Blaster compatible card at I/O base `220h`. The original `STARTC0.COM` must be present alongside the loader. SID full and SID M toggle additionally require `SIDENV.BIN` in the same directory and about 114 KB of free conventional memory for the score. Start with a 10 MHz XT; test a 286 if playback or gameplay is too slow.

## Controls and sound modes

Gameplay controls are unchanged apart from SID M toggle reusing the `M` key for CMS music. DOS mode follows the original speaker's one-voice music and effect priority. The SID builds loop the C64 main arrangement while the game's effects play on CMS chip 0 channel 0. The game's original speaker music remains muted in every SID build. In SID M toggle, `M` starts in the on state and mutes or restores the CMS arrangement without stopping effects. The score continues advancing while muted, so it resumes at the current position. The builds share one source file.

## Technical notes

The copied EXE and the embedded duplicate in DAT replace eleven `OUT 61h` speaker gate writes with `INT 60h` and six `OUT 42h` PIT pitch writes with `INT 61h`. The bridge reconstructs PIT divisors and maps them to SAA1099 tone and octave values. SID mode forces the game's own music switch off while preserving its separate effects switch. It also redirects the game's timer sound call through `INT 62h`; the handler runs the original sound tick, then reads precompiled SID events at roughly 50 Hz. SID M toggle additionally redirects the original music setter through `INT 63h`, which changes CMS music volume and returns zero to keep the DOS tune off. The source contains 8086 instructions only.

The C# converter and 8086 CMS score player were written for this project; they do not reuse a SID emulator or player library. The converter runs the SID file's 6502 init and play routines offline. It translates pitch, gate, and noise flags. The original SID build gives all noise voices a fixed CMS noise rate. The noise and envelope builds give each voice a noise source clocked from its own tone frequency. Both envelope builds model SID ADSR rates offline and store a three-bit volume level per note event. This is an approximation, especially for rapid gate changes; none of the builds emulates SID pulse width or filters. The original SID and noise builds loop after about eight minutes; the four-minute envelope test loops sooner to fit the DOS `.COM` limit. SID full reads its 113,907-byte score into two DOS-owned conventional-memory blocks before starting the game, then loops after eight minutes. Playback starts when the game timer starts; there is currently no title/gameplay-specific tune switching.

Vectors `60h` and `61h` are used in DOS mode; SID mode also uses `62h`, and SID M toggle uses `63h`. Avoid other resident software that owns those vectors. A forced reset cannot run the loader's cleanup. CMS has no general readback detection, so a missing card produces no CMS audio.

## Project layout

| Path | Purpose |
|------|---------|
| `cmsrun.s` | Shared 8086 loader, speaker bridge, and SID score player |
| `tools/SidDump/Program.cs` | Offline 6502 SID extractor and CMS note converter |
| `tools/SidDump/generate-sid-score.ps1`, `generate-sid-envelope-score.ps1`, `generate-sid-full-score.ps1` | Regenerate the bundled note scores |
| `build.ps1`, `patch.ps1` | Build loaders and validate/patch game copies |
| `dosbox-*.conf` | Game Blaster test configurations |
| `RUN_DOSBOX.BAT`, `RUN_SID_DOSBOX.BAT`, `RUN_SID_NOISE_DOSBOX.BAT`, `RUN_SID_ENVELOPE_DOSBOX.BAT`, `RUN_SID_FULL_DOSBOX.BAT`, `RUN_SID_TOGGLE_DOSBOX.BAT` | Launch the six builds |
| `run/`, `run-sid/`, `run-sid-noise/`, `run-sid-envelope/`, `run-sid-full/`, `run-sid-toggle/` | Generated playable DOS directories |

## Screenshots

Screenshots can be added after the playback tests.

## Testing

1. Launch DOS mode. Confirm the test tone, then listen for the familiar speaker arrangement through CMS with DOSBox PC speaker disabled.
2. Launch SID mode. Listen for three-voice C64 music and the game's effects, without a startup test tone. Check for crashes and slowdown.
3. Launch the SID noise test and compare its noisy instruments with the original SID build. The first listening report found similar music quality and working effects.
4. Launch the SID envelope test and compare release tails, percussion, effects, and gameplay speed.
5. Launch SID full. Check that it matches the envelope test at the start, plays through the four-minute point, and eventually loops at eight minutes. Check for missing-score errors.
6. Launch SID M toggle. Press `M` twice; confirm that CMS music stops and resumes while explosions and other effects continue. This worked in the DOSBox listening test.
7. Play through title and gameplay transitions and exit normally. Check that CMS becomes silent.
8. Repeat on a real 10 MHz XT with a compatible card. Measure whether speed is acceptable before changing the CPU target.

## Credits, license, and contributing

*Commando* is credited in the executable to Data East/Capcom and Quicksilver Software. The supplied C64 SID identifies Rob Hubbard and Elite. The game and SID are third-party works. Licensing for the new bridge code has not yet been selected; redistribute original game or SID files only with the appropriate rights. Feedback is welcome via [Retro Erik's YouTube channel](https://www.youtube.com/@RetroErik).
