"""Assemble releases/vX.Y: patched EXE, unchanged DAT, version launcher, README.
python make_release.py VERSION            VERSION = 1.0 | 1.1 | 1.2
v1.0 and v1.1 EXEs are the frozen files already in releases/; only the launcher + README are (re)written for them.
v1.2 copies build/COMMANDO.EXE (must have been built with `build_vga.py 1`)."""
import os, sys, shutil, hashlib, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_launcher

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')

README = {
'1.0': """# Commando VGA 1.0

320x200 256-colour VGA version of Commando 1.01 (graphics only; sound is the original PC speaker).
**By Dag Erik Hagesæter / Retro Erik using GitHub Copilot in VS Code** - https://www.youtube.com/@RetroErik

Run `START.COM` in this folder on a VGA PC (or DOSBox with `machine=vgaonly`).
Files: `COMMANDO.EXE` (patched), `COMMANDO.DAT` and the launcher. Original game files are not modified.
""",
'1.1': """# Commando VGA 1.1 - AdLib

Adds AdLib/OPL2 sound to the VGA version. **By Dag Erik Hagesæter / Retro Erik using GitHub Copilot in VS Code** - https://www.youtube.com/@RetroErik

The **M** key now cycles the sound device: **SPEAKER -> ADLIB -> OFF -> SPEAKER**. The game starts on SPEAKER; the choice is shown on screen
for about a second and on the title screen row `(M) Music Device`. ADLIB plays the game's own melody (not a replacement song) and an FM gunfire
effect; the AdLib card is detected at start-up and skipped if it is missing. `S` still toggles sound effects, `Q` leaves the game silently.
OFF silences every device while the game's sound logic keeps running, so game timing never changes.
""",
'1.2': """# Commando VGA 1.2 - AdLib + CMS

Adds CMS/Game Blaster music. **By Dag Erik Hagesæter / Retro Erik using GitHub Copilot in VS Code** - https://www.youtube.com/@RetroErik

The **M** key cycles **SPEAKER -> CMS -> ADLIB -> OFF -> SPEAKER** (starts on SPEAKER). CMS plays Rob Hubbard's C64 arrangement (about 8 minutes, then loops)
on two SAA1099 chips at I/O 220h/222h while the game's own effects use CMS channel 0. The score is embedded in `COMMANDO.EXE` (no extra file needed).
The game's ESC pause menu mutes/restores the CMS music. CMS cannot be detected by software, so it is always offered; select another device if the card is absent.
Credits: Rob Hubbard / Elite (the SID tune), Retro Erik (CMS arrangement and player, from the Codex CMS project).
""",
}


def make(version):
    out = os.path.join(HERE, 'releases', 'v' + version)
    os.makedirs(out, exist_ok=True)
    if version == '1.2':
        shutil.copyfile(os.path.join(HERE, 'build', 'COMMANDO.EXE'), os.path.join(out, 'COMMANDO.EXE'))
    shutil.copyfile(os.path.join(ROOT, 'COMMANDO.DAT'), os.path.join(out, 'COMMANDO.DAT'))
    make_launcher.make(version, out)
    open(os.path.join(out, 'README.md'), 'w', encoding='utf-8').write(README[version])
    for n in ('COMMANDO.EXE', 'COMMANDO.DAT', 'START.COM', 'README.md'):
        p = os.path.join(out, n)
        print('%-14s %8d  %s' % (n, os.path.getsize(p), hashlib.sha256(open(p, 'rb').read()).hexdigest()[:16]))
    if version == '1.2':
        # the downloadable archive linked from the main README lives next to it, in the Commando folder
        zpath = os.path.join(os.path.dirname(HERE), 'Commando.zip')
        with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
            for n in ('COMMANDO.DAT', 'COMMANDO.EXE', 'START.COM'):
                z.write(os.path.join(out, n), n)
        print('Commando.zip   %8d' % os.path.getsize(zpath))


if __name__ == '__main__':
    make(sys.argv[1])
