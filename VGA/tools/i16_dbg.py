import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.join(HERE, 'build', 'COMMANDO.EXE')
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
orig = g.int_16
log = []
def i16():
    ah = (c.r[0] >> 8) & 0xFF
    orig()
    log.append((c.icount, ah, c.r[0], c.zf))
g.int_16 = i16
g.run(3_500_000)
g.press(0x324D)
g.run(4_000_000)
print(len(log), log[-6:])
print('queue', g.key_queue, 'ivt16', hex(c.rw(0x5A)), hex(c.rw(0x58)), 'CS:IP %04X:%04X' % (c.s[1], c.ip))
