# Commando VGA 1.1 - AdLib

Adds AdLib/OPL2 sound to the VGA version. **By Dag Erik Hagesæter / Retro Erik using GitHub Copilot in VS Code** - https://www.youtube.com/@RetroErik

The **M** key now cycles the sound device: **SPEAKER -> ADLIB -> OFF -> SPEAKER**. The game starts on SPEAKER; the choice is shown on screen
for about a second and on the title screen row `(M) Music Device`. ADLIB plays the game's own melody (not a replacement song) and an FM gunfire
effect; the AdLib card is detected at start-up and skipped if it is missing. `S` still toggles sound effects, `Q` leaves the game silently.
OFF silences every device while the game's sound logic keeps running, so game timing never changes.
