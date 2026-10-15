"""Render the README screenshots (title + gameplay) for the original CGA, Plantronics ColorPlus and VGA builds.

All three are produced by running the real game code headlessly in the 8086 emulator (the Plantronics build together with its
loader), so the frames are directly comparable.  Output: docs/images/*.png at 2x (nearest neighbour) plus a comparison sheet.
python make_readme_screens.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emu_plantronics            # sets the PSP/load segments used by the Plantronics run
from emu_plantronics import PlanGame, PLAN
import emu_game
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')
OUT = os.path.join(HERE, 'docs', 'images')
os.makedirs(OUT, exist_ok=True)
STEPS = [(2_000_000, 'snap', 'title'), (4_000_000, 'key', None), (7_000_000, 'snap', 'gameplay')]
VGA_STEPS = [(2_450_000, 'snap', 'title'), (4_000_000, 'key', None), (10_000_000, 'snap', 'gameplay')]   # the VGA build draws the logo later and starts play later


def run(name, g, grab, steps=STEPS):
    c = g.cpu
    for n, kind, arg in steps:
        g.run(n - c.icount)
        if kind == 'key':
            g.press(0x3920)
        else:
            im = grab(g).convert('RGB')
            im.resize((640, 400), Image.NEAREST).save(os.path.join(OUT, '%s_%s.png' % (arg, name)))
            print(name, arg, 'ok')


def standard(path):
    # original / VGA builds: working directory does not matter, the emulator reads COMMANDO.DAT from the Commando folder
    emu_game.PSP_SEG, emu_game.LOAD_SEG = 0x1000, 0x1010
    g = emu_game.Game(path)
    return g


if __name__ == '__main__':
    # Plantronics first (it needs its own segment layout)
    pg = PlanGame()
    os.chdir(PLAN)
    run('plantronics', pg, lambda g: g.frame_plantronics())
    g = standard(os.path.join(ROOT, 'COMMANDO.EXE'))
    run('cga', g, lambda g: g.frame())
    g = standard(os.path.join(HERE, 'releases', 'v1.2', 'COMMANDO.EXE'))
    run('vga', g, lambda g: g.frame(), VGA_STEPS)

    rows = ['cga', 'plantronics', 'vga']
    sheet = Image.new('RGB', (1280, 3 * 400))
    for r, name in enumerate(rows):
        for col, scene in enumerate(('title', 'gameplay')):
            sheet.paste(Image.open(os.path.join(OUT, '%s_%s.png' % (scene, name))), (col * 640, r * 400))
    sheet.save(os.path.join(HERE, 'test', 'readme_sheet.png'))
