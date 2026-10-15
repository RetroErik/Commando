"""Shared decoding helpers for the original Commando 1.01 (CGA mode 4) graphics.

All coordinates/offsets are into the EXE *load image* (EXE file minus the 0x200 byte MZ header).
The data segment starts at image offset 0x8350; the code segment (CS) starts at 0.
"""
import os, struct

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # .../VGA
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')   # .../Commando/Original game files
EXE = open(os.path.join(ROOT, 'COMMANDO.EXE'), 'rb').read()
IMG = EXE[0x200:]
DS_BASE = 0x8350

# Palette actually shown by the game: BIOS mode 4 default palette (cyan / magenta / white).
CGA_PAL = [(0, 0, 0), (85, 255, 255), (255, 85, 255), (255, 255, 255)]


def decode_pairs(a, h, w):
    """Decode h*w mask/value pairs at image offset a -> rows of pixel colors (None = transparent)."""
    rows = []
    odd_mask = 0
    for y in range(h):
        row = []
        for x in range(w):
            m = IMG[a + 2 * (y * w + x)]
            v = IMG[a + 2 * (y * w + x) + 1]
            for p in range(4):
                s = 6 - 2 * p
                mm = (m >> s) & 3
                vv = (v >> s) & 3
                if mm == 3:
                    row.append(None)
                else:
                    if mm != 0:
                        odd_mask += 1
                    row.append(vv)
        rows.append(row)
    return rows, odd_mask


def sprite_at(a):
    """Decode the sprite record at image offset a. Returns dict with even/odd pixel rows."""
    odd_off = struct.unpack_from('<H', IMG, a)[0]
    h, w = IMG[a + 2], IMG[a + 3]
    even, bad = decode_pairs(a + 4, h, w)
    if odd_off:
        od = a + 2 + odd_off
        oh, ow = IMG[od], IMG[od + 1]
        odd, bad2 = decode_pairs(od + 2, oh, ow)
        bad += bad2
    else:
        oh, ow, odd = h, w, None
    return dict(a=a, d=a - DS_BASE, h=h, w=w, oh=oh, ow=ow, even=even, odd=odd, bad=bad, odd_off=odd_off)


def menu_sprite_at(a):
    """Menu sprite (code-segment): byte h, byte w, then pairs."""
    h, w = IMG[a], IMG[a + 1]
    rows, bad = decode_pairs(a + 2, h, w)
    return dict(a=a, h=h, w=w, even=rows, bad=bad)
