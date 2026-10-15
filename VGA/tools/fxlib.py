"""Helpers to drive the game's own sound effect starter (CS:672E) from the emulator test harness."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *


def call_far_near(g, ip_target, args, max_steps=20000):
    """Execute a near CALL to CS:ip_target with C-style stack arguments (args[0] pushed last = first argument)."""
    c = g.cpu
    saved = (list(c.r), list(c.s), c.ip, c.get_flags())
    ret_ip = c.ip
    ss = c.s[2] << 4
    for a in reversed(args):
        c.push(a)
    c.push(ret_ip)
    sp_after = c.r[4] + 2 + 2 * len(args)
    target_sp = c.r[4] + 2
    c.ip = ip_target
    steps = 0
    while steps < max_steps:
        c.step()
        steps += 1
        if c.s[1] == saved[1][1] and c.ip == ret_ip and c.r[4] == target_sp:
            break
    c.r, c.s, c.ip = saved[0], saved[1], saved[2]
    c.set_flags(saved[3])
    return steps


def start_effect(g, ptr=0x1B34, prio=1):
    return call_far_near(g, 0x672E, [ptr, prio])
