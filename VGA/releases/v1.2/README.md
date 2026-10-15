# Commando VGA 1.2 - AdLib + CMS

Adds CMS/Game Blaster music. **By Dag Erik Hagesæter / Retro Erik using GitHub Copilot in VS Code** - https://www.youtube.com/@RetroErik

The **M** key cycles **SPEAKER -> CMS -> ADLIB -> OFF -> SPEAKER** (starts on SPEAKER). CMS plays Rob Hubbard's C64 arrangement (about 8 minutes, then loops)
on two SAA1099 chips at I/O 220h/222h while the game's own effects use CMS channel 0. The score is embedded in `COMMANDO.EXE` (no extra file needed).
The game's ESC pause menu mutes/restores the CMS music. CMS cannot be detected by software, so it is always offered; select another device if the card is absent.
Credits: Rob Hubbard / Elite (the SID tune), Retro Erik (CMS arrangement and player, from the Codex CMS project).
