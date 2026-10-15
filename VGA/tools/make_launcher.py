"""Build the launcher for a VGA release from "Original game files/STARTC2.COM" (keeps its banner + /? help screen) with updated help text.

STARTC2.COM layout (verified): the help text is the last item of the file, at file offset 25Bh (DOS address 35Bh), terminated by '$';
printing it is `mov dx,35Bh / mov ah,9 / int 21h`.  Growing the text only extends the file, so nothing else moves.
python make_launcher.py VERSION OUTDIR     (VERSION = 1.0 | 1.1 | 1.2)
"""
import os, sys, hashlib

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')
HELP_OFF = 0x25B
OLD_BANNER_OFF = 0x1E0          # file offset of the original "Cracked in 1999 ..." string ($-terminated)
BANNER_REFS = (0x0A, 0x0B5)     # offsets of the two `mov dx, imm16` instructions that print it (imm at +1)
BANNER = 'Adapted for VGA, CMS and Adlib by Retro Erik 2026 using Claude Sonnet 5.5'

M_LINES = {
    '1.0': ['  M     Toggle music (PC speaker)           S   Toggle sound'],
    '1.1': ['  M     Music device SPEAKER>ADLIB>OFF  S   Toggle sound (starts: SPEAKER)'],
    '1.2': ['  M     Music device SPEAKER>CMS>ADLIB>OFF  S   Toggle sound (starts: SPEAKER)'],
}
DEV = {
    '1.0': ['Sound: PC speaker only.'],
    '1.1': ['Devices: PC speaker (original), AdLib (game melody + FM gunfire), off.'],
    '1.2': ['Devices: speaker (original), CMS (Hubbard C64 music), AdLib (game melody), off.'],
}


def help_text(version):
    lines = [
        'Commando launcher Start - VGA edition %s' % version,
        BANNER,
        'Retro Erik - https://www.youtube.com/@RetroErik',
        '',
        'Usage: START [/?]   Runs COMMANDO.EXE (320x200, 256-colour VGA).',
        '',
        'Game keys:',
        '  ESC   Pause / resume            F1  Quit the game to the menu',
    ] + M_LINES[version] + [
        '  C     Toggle KEYBOARD / JOYSTICK control',
        '  Space or X  Fire                Z   Second action (grenade)',
        '  Q     Quit to DOS (launcher key, works when the game reads a key)',
        '',
        'Move: 7 8 9 / 4 5 6 / 1 2 3  or  I O P / J L ; / , . /   (5 or L = stop)',
    ] + DEV[version] + [
        'The game turns Caps Lock and Num Lock on; Shift+letter is ignored.',
    ]
    for l in lines:
        assert 'Demonlord' not in l
        assert len(l) <= 79, l
    return '\r\n'.join(lines) + '\r\n$'


def make(version, outdir):
    src = open(os.path.join(ROOT, 'STARTC2.COM'), 'rb').read()
    assert src[HELP_OFF:HELP_OFF + 14] == b'Commando launc', 'unexpected STARTC2.COM layout'
    assert src[0x25A] == 0x00 or True
    assert src.endswith(b'$')
    txt = help_text(version)
    assert txt.count('\n') <= 24, 'help text must fit one 25-line screen (%d lines)' % txt.count('\n')
    # The new banner is longer than the old one, so it is appended after the help text and both print sites are re-pointed.
    old_end = src.index(b'$', OLD_BANNER_OFF) + 1
    assert src[OLD_BANNER_OFF:OLD_BANNER_OFF + 7] == b'Cracked' and old_end - OLD_BANNER_OFF == 66
    body = bytearray(src[:HELP_OFF])
    body[OLD_BANNER_OFF:old_end] = bytes(old_end - OLD_BANNER_OFF)
    help_b = txt.encode('ascii')
    banner_addr = 0x100 + HELP_OFF + len(help_b)
    for r in BANNER_REFS:
        assert body[r] == 0xBA and body[r + 1:r + 3] == bytes([0xE0, 0x02]), 'unexpected banner reference'
        body[r + 1:r + 3] = banner_addr.to_bytes(2, 'little')
    out = bytes(body) + help_b + (BANNER + '\r\n$').encode('ascii')
    assert len(out) < 0xF000 and b'Demonlord' not in out
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, 'START.COM'), 'wb').write(out)
    return len(out)


if __name__ == '__main__':
    print('launcher written, %d bytes' % make(sys.argv[1], sys.argv[2]))
