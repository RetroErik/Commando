# Commando AdLib Audio Launcher 0.7

An experimental DOS add-on that renders **Commando's own music** through AdLib
and gives the gun a short noise-based FM sound. It runs the existing
`STARTC.COM` launcher and keeps the PC speaker silent.

**By Dag Erik Hagesæter / Retro Erik** - [YouTube: Retro Erik](https://www.youtube.com/@RetroErik)

![Platform](https://img.shields.io/badge/Platform-MS--DOS-blue)
![CPU](https://img.shields.io/badge/CPU-8086%2F8088-green)
![Language](https://img.shields.io/badge/Language-NASM%20assembly-orange)
![License](https://img.shields.io/badge/License-not%20specified-lightgrey)

## Overview

All add-on files belong in this `Copilot` directory. The original executable,
data and launcher remain unchanged in the `Original game files` directory next to it. The add-on makes
guarded changes only to the running game's RAM image; it is not a permanent TSR
and never patches the game on disk.

| Component | Details |
|-----------|---------|
| Target | Commando 1.01, dated February 25, 1987 |
| Entry point | Original `STARTC.COM` |
| CPU | 8086/8088 real-mode instructions |
| Hardware | AdLib/OPL2 at `388h` and `389h` |
| Gameplay music | Live rendering of the game's resolved pitches, rests and note timing |
| Gunfire | Maximum-feedback FM burst, low body and snare transient |
| Timing | Game audio update at approximately 109 Hz; BIOS hook for discovery and previews |
| PC speaker | Disabled in DOSBox and gated off in the recognized game |
| Memory | Small parent process retained while the game runs |
| Preservation | Original executable, data, launcher and song resources unchanged on disk |

## Features

- Uses the original game's melody, not a replacement track during gameplay.
- Lets the original sequencer select its songs and transitions.
- Converts resolved PIT pitches to OPL notes without exporting or embedding the
  game's song sequences in the add-on.
- Follows rests, repeated notes, note gaps, sequence end and the music-enable flag.
- Keeps music and gunfire on independent AdLib voices.
- Preserves independent **M** and **S** controls.
- Provides standalone music and gunfire previews.
- Detects missing AdLib hardware and reports DOS launch errors.
- Clears AdLib keys, rhythm noise and the speaker gate on return.

### Limits

CMS is not implemented, and real 8088 hardware performance is not verified.
Version-specific instruction signatures must match before a RAM hook is installed.
An unrecognized profile produces a warning on return; no substitute gameplay song
is played.

Gunfire is synthesized, not a sampled firearm recording. The original game has
one prioritized effect stream, which the add-on follows. New grenade audio is
**deferred**: the original grenade is silent, and the unsuccessful experimental
explosion hook has been removed. No delayed artificial explosion is scheduled.

## Quick Start

### Requirements

- Keep `STARTC.COM`, `COMMANDO.EXE` and `COMMANDO.DAT` in the `Original game files` directory next to `Copilot`.
- Use DOSBox 0.74-3 or compatible DOS with AdLib hardware.
- Use NASM to rebuild. The build script checks PATH and
  `%LOCALAPPDATA%\bin\NASM`.

### Build on Windows

Run [BUILD.BAT](BUILD.BAT), or:

```text
nasm -f bin -Wall -Werror -w-reloc-abs-word cmusic.asm -o CMUSIC.COM
```

The suppressed warning concerns intentional absolute 16-bit addresses in a
single-segment DOS `.COM` file. Other enabled warnings are errors.

### Run on Windows

Run [RUN_MUSIC.BAT](RUN_MUSIC.BAT). It mounts the **`Original game files` directory** as `C:`, mounts the
`Copilot` directory as `D:` and runs `D:\CMUSIC`, which invokes the original `STARTC.COM`.

The script uses the local DOSBox 0.74-3 installation path; edit that path for a
different installation.

## Usage

Run DOS commands from the `Original game files` directory (mounted as `C:`, with `Copilot` mounted as `D:`):

```text
D:\CMUSIC        Start through STARTC with original music and AdLib gunfire
D:\CMUSIC /N     Start without the add-on's audio hooks
D:\CMUSIC /P     Preview the original add-on composition Night Patrol
D:\CMUSIC /E     Preview synthesized AdLib gunfire
D:\CMUSIC /?     Show help
STARTC           Start the unmodified game without the add-on
```

**Night Patrol is preview-only.** Its original three-voice, 128-row loop remains
available with `/P`; it is not played over Commando's music.

The supplied DOSBox configuration disables the PC speaker even with `/N` or
`STARTC`. For an original-audio comparison, also load
[test/speaker-original.conf](test/speaker-original.conf) after the main
configuration and run `STARTC` without `CMUSIC`.

## Controls and Diagnostics

- **M:** Mute/resume the game's music on AdLib; gunfire is independent.
- **S:** Mute/resume gunfire; music is independent.
- **Esc:** Use the game's pause/resume behavior; its music flag is followed.
- **Q:** Return through the original launcher's BIOS-keyboard exit handler.
  The response depends on the game reaching a keyboard read.
- **Ctrl+F9:** Close DOSBox if the original launcher cannot return.

Previews stop on any key. No new keyboard handler is installed.

After a game run, the launcher prints synchronization status and small
diagnostic counters:

```text
Effects: ticks=... enabled=... active=... updates=... music-notes=...
Game returned; launcher cleanup completed.
```

Counters are 16-bit and may wrap on long sessions. A warning identifies an
unrecognized audio profile or music hook instead of claiming successful
conversion.

## Technical Notes

### Live Music

The game uses a word-based music sequencer and a separate byte-command effect
sequencer. Music keeps advancing while effects own the original speaker, so
sampling speaker output alone would confuse shots with melody notes.

The add-on samples the IRQ0 vector from `INT 1Ch` and recognizes this executable
using its handler offset and instruction signatures. It then installs RAM-only
hooks with interrupts disabled:

| Loaded code offset | Purpose |
|--------------------|---------|
| `CS:685Ah` | Capture the music sequencer's resolved PIT divisor |
| `CS:6879h` | Skip the original music-to-speaker output branch |
| `CS:698Ch` | Disable the effect's speaker gate instead of enabling it |
| `CS:69A5h` | Render audio state on each game timer update |

These are **loaded code-segment offsets**, not file offsets. The executable has
a `200h`-byte MZ header. The music and effect enable flags are `CS:6583h` and
`CS:6590h`.

The music hook replaces the five-byte pitch-table load with a far jump, renders
the resolved note, preserves the instruction's AX result and other registers,
and continues at `CS:685Fh`. Original song data, timing tables, loops and event
selection are neither copied nor replaced. The shared audio callback reproduces
its displaced instructions and continues at `CS:69AAh`.

Music uses OPL channel 0. The callback watches the original note phase and
sequence state to key off gaps and ended songs. It does not write game audio
flags or call DOS from an interrupt.

### Gunfire

Gunfire uses OPL channel 3 for a low FM body, with the game's effect pitch sweep
transposed down four octaves, with overflow clamped to the lowest supported
pitch. Version 0.7 removes the bright hi-hat. Channel 3 uses additive mode:
one half-frequency operator provides a fast-decaying maximum-feedback burst,
and the other provides the low body. The snare layer adds a short crack.
A restarted effect triggers a tightly gated snare noise burst in OPL rhythm mode;
the noise gate lasts at most seven
game ticks (approximately 64 ms), or ends sooner when the effect stops.

The body's fast-decaying envelope and noise layer avoid the old sustained,
speaker-like beep. The `S` flag, zero divisors and ended effects key off the body
and noise. Unexpected changes to the game's IRQ0 handler also silence active
voices rather than following an unrecognized child-memory pointer.

### Timing and Cleanup

The game programs PIT divisor `2AAAh` and chains the previous BIOS IRQ0 handler
every sixth interrupt. The add-on leaves the PIT and game IRQ0 handler unchanged.
The BIOS hook discovers the game; installed audio callbacks follow the game's
faster sequencer directly.

OPL writes use status-port read delays. Use AdLib exclusively while this launcher
runs; another resident OPL player could interfere.

Normal returns and DOS launch errors remove the BIOS hook, clear all OPL keys
and rhythm bits, attenuate carriers and disable the speaker gate. RAM changes
last only for that game process. A crash or forced termination can bypass
cleanup; reset or close DOSBox in that case.

No automatic backup is needed because the original files are never edited.

## Project Layout

```text
Commando\
  Original game files\
    STARTC.COM           Original launcher, unchanged
    COMMANDO.EXE         Original game, unchanged
    COMMANDO.DAT         Original data, unchanged
  Copilot\
    cmusic.asm           Launcher, live bridges, FM instruments and previews
    CMUSIC.COM           Built DOS launcher
    BUILD.BAT            Windows build
    RUN_MUSIC.BAT        Windows DOSBox launcher
    dosbox-music.conf    CGA, 5000 cycles, OPL2, PC speaker disabled
    TEST.ps1             Windows regression runner
    test\
      player-test.inc    Driver and synthetic-profile regressions
      game-stub.asm      Synthetic game timer/EXEC test
      checks.bat         DOS integration checks
      no-opl.conf        Missing-AdLib test configuration
      speaker-original.conf  Original-speaker comparison override
```

## Testing

From PowerShell:

```text
.\TEST.ps1
```

The suite builds 8086-only binaries and tests detection, preview notes and loop
boundaries, register/flag preservation, interrupt chaining, timer restoration,
child execution, exit-code propagation, file errors and missing hardware.

Synthetic-profile tests cover signature mismatch rejection, safe RAM hooks,
original-instruction continuation, pitch conversion, repeated notes, rests,
note gaps, sequence end, music mute/resume, effect restart, sweeps, noise gating
and independent music/effect controls. No commercial game or song files are
copied into the tests.

### Listening and Gameplay Results

- The first version 0.7 tuning was confirmed lower but too dull; a stronger
  snare alone was also too dull. The current tuning adds a maximum-feedback
  additive FM burst. The user confirmed this version sounds better and chose
  to keep it.
- The user confirmed the original melody is playing in version 0.6.
- The user confirmed the revised sound is much more like gunfire.
- The user confirmed **S** mutes/restores gunfire without affecting music.
- The user confirmed **M** controls only music while gunfire still works.
- The user confirmed **Q** returns to DOS with no tone or hiss left playing
  in version 0.6.
- Prior versions passed user checks for gameplay, pause/resume and silence after
  exit. Repeat pause/resume checks after substantial audio changes.
- The original game was checked separately: grenade explosions have no speaker
  sound. New grenade audio was deferred at the user's request.

Automated register checks do not replace listening or real gameplay tests.

## Credits, License and Contributing

Commando and its original game files belong to their respective rights holders.
Embedded credits identify Data East, CapCom and Quicksilver Software.
The add-on requires the user's existing game; no original music assets or
transcribed soundtrack are distributed with it.

Night Patrol is a new composition used only by the add-on preview. No license
has been assigned to this source, and the game is not relicensed by this project.
Contributions should preserve the original files and 8086 compatibility.

[YouTube: Retro Erik](https://www.youtube.com/@RetroErik)
