"""Render the pause-menu text drawn by the patched game (hook_modetext) for each sound mode.
Runs gameplay in the emulator, forces game state 6 (pause), prints the sound-device row."""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fxlib import *
exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
g.run(3_300_000)
g.press(0x3920)
g.run(2_000_000)
ds_seg = struct.unpack_from('<H', c.mem, CS + 0xA7)[0]
for m, name in ((0, 'SPEAKER'), (2, 'ADLIB'), (3, 'OFF')):
    c.mem[CS + sym['s_mode']] = m
    n = call_far_near(g, 0x6075 - 0x6075 + 0x6000, []) if False else 0
    # call the text hook directly: it prints through the game's text routine at the fixed pause-menu position
    c.push(0)   # unused
    c.r[4] += 2
print('hook_modetext address %04X, strings: %s' % (sym['hook_modetext'], [bytes(c.mem[CS + sym[k]: CS + sym[k] + 8]).decode() for k in ('str_speaker', 'str_cms', 'str_adlib', 'str_off')]))
tab = [struct.unpack_from('<H', c.mem, CS + sym['s_mode_str'] + 2 * i)[0] for i in range(4)]
print('s_mode_str table:', [hex(t) for t in tab], 'string addresses:', [hex(sym[k]) for k in ('str_speaker', 'str_cms', 'str_adlib', 'str_off')])
orig = bytes(open(os.path.join(HERE, 'analysis', 'image.bin'), 'rb').read()[0x60CE:0x60F0])
print('patched bytes at 60CE:', bytes(c.mem[CS + 0x60CE:CS + 0x60D4]).hex(' '))
