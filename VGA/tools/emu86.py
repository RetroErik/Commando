"""Minimal 8086 real-mode emulator used only for offline analysis of COMMANDO.EXE.

It runs the original EXE with just enough DOS/BIOS/hardware emulation to reach gameplay, so that every
write to a CGA video/RAM screen can be traced back to the drawing routine that made it.
Not a general-purpose emulator.
"""
import struct, sys, os

PAR = [1 if bin(i).count('1') % 2 == 0 else 0 for i in range(256)]
M16 = 0xFFFF


class Halt(Exception):
    pass


class CPU:
    def __init__(self):
        self.mem = bytearray(1 << 20)
        self.r = [0] * 8            # ax cx dx bx sp bp si di
        self.s = [0] * 4            # es cs ss ds
        self.ip = 0
        self.cf = self.pf = self.af = self.zf = self.sf = self.of = self.df = 0
        self.if_ = 1
        self.icount = 0
        self.ports_out = []
        self.halted = False
        self.on_int = None          # python handler (n) -> True if handled
        self.on_in = lambda p, size: 0
        self.on_out = lambda p, v, size: None
        self.write_hook = None      # optional callable(addr, size) before each write when watch set
        self.watch = None           # (lo, hi) physical addresses
        self.pending_irq = []
        self.trace_calls = False

    # ---- memory
    rwatch = None
    read_hook = None

    def rb(self, a):
        a &= 0xFFFFF
        if self.rwatch is not None and self.rwatch[0] <= a < self.rwatch[1]:
            self.read_hook(a, 1)
        return self.mem[a]

    def rw(self, a):
        a &= 0xFFFFF
        if self.rwatch is not None and self.rwatch[0] <= a < self.rwatch[1]:
            self.read_hook(a, 2)
        return self.mem[a] | (self.mem[(a + 1) & 0xFFFFF] << 8)

    def wb(self, a, v):
        a &= 0xFFFFF
        if self.watch is not None and self.watch[0] <= a < self.watch[1]:
            self.write_hook(a, 1, v & 0xFF)
        self.mem[a] = v & 0xFF

    def ww(self, a, v):
        a &= 0xFFFFF
        if self.watch is not None and self.watch[0] <= a < self.watch[1]:
            self.write_hook(a, 2, v & 0xFFFF)
        self.mem[a] = v & 0xFF
        self.mem[(a + 1) & 0xFFFFF] = (v >> 8) & 0xFF

    # ---- registers
    def get_r8(self, i):
        return (self.r[i] & 0xFF) if i < 4 else ((self.r[i - 4] >> 8) & 0xFF)

    def set_r8(self, i, v):
        v &= 0xFF
        if i < 4:
            self.r[i] = (self.r[i] & 0xFF00) | v
        else:
            self.r[i - 4] = (self.r[i - 4] & 0x00FF) | (v << 8)

    # ---- stack
    def push(self, v):
        self.r[4] = (self.r[4] - 2) & M16
        self.ww((self.s[2] << 4) + self.r[4], v)

    def pop(self):
        v = self.rw((self.s[2] << 4) + self.r[4])
        self.r[4] = (self.r[4] + 2) & M16
        return v

    # ---- flags
    def get_flags(self):
        return (self.cf | 2 | (self.pf << 2) | (self.af << 4) | (self.zf << 6) | (self.sf << 7) |
                (self.if_ << 9) | (self.df << 10) | (self.of << 11) | 0xF000)

    def set_flags(self, f):
        self.cf = f & 1
        self.pf = (f >> 2) & 1
        self.af = (f >> 4) & 1
        self.zf = (f >> 6) & 1
        self.sf = (f >> 7) & 1
        self.if_ = (f >> 9) & 1
        self.df = (f >> 10) & 1
        self.of = (f >> 11) & 1

    def szp(self, v, size):
        if size == 1:
            self.zf = 1 if (v & 0xFF) == 0 else 0
            self.sf = (v >> 7) & 1
        else:
            self.zf = 1 if (v & M16) == 0 else 0
            self.sf = (v >> 15) & 1
        self.pf = PAR[v & 0xFF]

    def alu(self, op, a, b, size):
        mask = 0xFF if size == 1 else M16
        top = 0x80 if size == 1 else 0x8000
        if op in (0, 2):   # add/adc
            c = self.cf if op == 2 else 0
            res = a + b + c
            self.cf = 1 if res > mask else 0
            self.af = 1 if ((a & 15) + (b & 15) + c) > 15 else 0
            r = res & mask
            self.of = 1 if (~(a ^ b) & (a ^ r) & top) else 0
            self.szp(r, size)
            return r
        if op in (5, 3, 7):   # sub/sbb/cmp
            c = self.cf if op == 3 else 0
            res = a - b - c
            self.cf = 1 if res < 0 else 0
            self.af = 1 if ((a & 15) - (b & 15) - c) < 0 else 0
            r = res & mask
            self.of = 1 if ((a ^ b) & (a ^ r) & top) else 0
            self.szp(r, size)
            return r
        if op == 1:
            r = (a | b) & mask
        elif op == 4:
            r = (a & b) & mask
        else:   # 6 xor
            r = (a ^ b) & mask
        self.cf = self.of = self.af = 0
        self.szp(r, size)
        return r

    # ---- fetch
    def f8(self):
        v = self.mem[((self.s[1] << 4) + self.ip) & 0xFFFFF]
        self.ip = (self.ip + 1) & M16
        return v

    def f16(self):
        a = ((self.s[1] << 4) + self.ip) & 0xFFFFF
        v = self.mem[a] | (self.mem[(a + 1) & 0xFFFFF] << 8)
        self.ip = (self.ip + 2) & M16
        return v

    # ---- modrm
    def modrm(self, seg_ovr):
        m = self.f8()
        mod, reg, rm = m >> 6, (m >> 3) & 7, m & 7
        if mod == 3:
            return mod, reg, rm, None, None
        r = self.r
        if rm == 0:
            off = r[3] + r[6]; dseg = 3
        elif rm == 1:
            off = r[3] + r[7]; dseg = 3
        elif rm == 2:
            off = r[5] + r[6]; dseg = 2
        elif rm == 3:
            off = r[5] + r[7]; dseg = 2
        elif rm == 4:
            off = r[6]; dseg = 3
        elif rm == 5:
            off = r[7]; dseg = 3
        elif rm == 6:
            if mod == 0:
                off = self.f16(); dseg = 3
            else:
                off = r[5]; dseg = 2
        else:
            off = r[3]; dseg = 3
        if mod == 1:
            d = self.f8()
            off += d - 256 if d & 0x80 else d
        elif mod == 2:
            off += self.f16()
        off &= M16
        seg = self.s[seg_ovr if seg_ovr is not None else dseg]
        return mod, reg, rm, seg, off

    def ea_read(self, mod, rm, seg, off, size):
        if mod == 3:
            return self.get_r8(rm) if size == 1 else self.r[rm]
        a = (seg << 4) + off
        return self.rb(a) if size == 1 else self.rw(a)

    def ea_write(self, mod, rm, seg, off, size, v):
        if mod == 3:
            if size == 1:
                self.set_r8(rm, v)
            else:
                self.r[rm] = v & M16
        else:
            a = (seg << 4) + off
            if size == 1:
                self.wb(a, v)
            else:
                self.ww(a, v)

    # ---- interrupts
    def do_int(self, n):
        if self.on_int and self.on_int(n):
            return
        self.push(self.get_flags())
        self.push(self.s[1])
        self.push(self.ip)
        self.if_ = 0
        self.ip = self.rw(n * 4)
        self.s[1] = self.rw(n * 4 + 2)

    def shift(self, op, v, cnt, size):
        mask = 0xFF if size == 1 else M16
        bits = 8 if size == 1 else 16
        top = 1 << (bits - 1)
        cnt &= 0x1F
        if cnt == 0:
            return v
        for _ in range(cnt):
            if op == 0:     # rol
                c = (v >> (bits - 1)) & 1
                v = ((v << 1) | c) & mask
                self.cf = c
                self.of = ((v >> (bits - 1)) & 1) ^ c
            elif op == 1:   # ror
                c = v & 1
                v = (v >> 1) | (c << (bits - 1))
                self.cf = c
                self.of = ((v >> (bits - 1)) ^ (v >> (bits - 2))) & 1
            elif op == 2:   # rcl
                c = (v >> (bits - 1)) & 1
                v = ((v << 1) | self.cf) & mask
                self.cf = c
                self.of = ((v >> (bits - 1)) & 1) ^ c
            elif op == 3:   # rcr
                c = v & 1
                self.of = (((v >> (bits - 1)) & 1) ^ self.cf)
                v = (v >> 1) | (self.cf << (bits - 1))
                self.cf = c
            elif op in (4, 6):   # shl
                c = (v >> (bits - 1)) & 1
                v = (v << 1) & mask
                self.cf = c
                self.of = ((v >> (bits - 1)) & 1) ^ c
                self.szp(v, size)
            elif op == 5:   # shr
                self.of = (v >> (bits - 1)) & 1
                self.cf = v & 1
                v >>= 1
                self.szp(v, size)
            else:           # sar
                self.cf = v & 1
                v = (v >> 1) | (v & top)
                self.of = 0
                self.szp(v, size)
        return v

    def cond(self, c):
        t = c >> 1
        if t == 0:
            r = self.of
        elif t == 1:
            r = self.cf
        elif t == 2:
            r = self.zf
        elif t == 3:
            r = self.cf or self.zf
        elif t == 4:
            r = self.sf
        elif t == 5:
            r = self.pf
        elif t == 6:
            r = self.sf != self.of
        else:
            r = self.zf or (self.sf != self.of)
        return (not r) if (c & 1) else bool(r)

    # ---- main step
    def step(self):
        if self.s[1] == 0xF000:
            # control reached a default BIOS/DOS vector (e.g. a chained "pushf; call far oldvec"):
            # run the Python service and return like IRET
            n = self.ip & 0xFF
            if getattr(self, 'on_service', None):
                self.on_service(n)
            elif self.on_int:
                self.on_int(n)
            cf, zf = self.cf, self.zf            # BIOS/DOS return their result in the flags of the IRET image
            self.ip = self.pop()
            self.s[1] = self.pop()
            self.set_flags(self.pop())
            self.cf, self.zf = cf, zf
            return
        if self.pending_irq and self.if_:
            n = self.pending_irq.pop(0)
            self.do_int(n)
        self.cur_ip = self.ip
        seg_ovr = None
        rep = None
        start_ip = self.ip
        while True:
            op = self.f8()
            if op == 0x26:
                seg_ovr = 0
            elif op == 0x2E:
                seg_ovr = 1
            elif op == 0x36:
                seg_ovr = 2
            elif op == 0x3E:
                seg_ovr = 3
            elif op == 0xF2:
                rep = 2
            elif op == 0xF3:
                rep = 3
            elif op == 0xF0:
                pass
            else:
                break
        self.icount += 1
        r = self.r
        s = self.s
        if op < 0x40 and (op & 7) < 6:
            aop = op >> 3
            k = op & 7
            if k < 4:
                size = 1 if (k & 1) == 0 else 2
                mod, reg, rm, seg, off = self.modrm(seg_ovr)
                if k < 2:   # r/m, reg
                    a = self.ea_read(mod, rm, seg, off, size)
                    b = self.get_r8(reg) if size == 1 else r[reg]
                    res = self.alu(aop, a, b, size)
                    if aop != 7:
                        self.ea_write(mod, rm, seg, off, size, res)
                else:       # reg, r/m
                    a = self.get_r8(reg) if size == 1 else r[reg]
                    b = self.ea_read(mod, rm, seg, off, size)
                    res = self.alu(aop, a, b, size)
                    if aop != 7:
                        if size == 1:
                            self.set_r8(reg, res)
                        else:
                            r[reg] = res
            elif k == 4:
                res = self.alu(aop, r[0] & 0xFF, self.f8(), 1)
                if aop != 7:
                    self.set_r8(0, res)
            else:
                res = self.alu(aop, r[0], self.f16(), 2)
                if aop != 7:
                    r[0] = res
            return
        if op < 0x40:
            if op in (0x06, 0x0E, 0x16, 0x1E):
                self.push(s[(op >> 3) & 3])
            elif op in (0x07, 0x17, 0x1F):
                s[(op >> 3) & 3] = self.pop()
            else:
                raise Halt('unsupported opcode %02X at %04X:%04X' % (op, s[1], start_ip))
            return
        if op < 0x48:
            reg = op & 7
            cf = self.cf
            r[reg] = self.alu(0, r[reg], 1, 2)
            self.cf = cf
            return
        if op < 0x50:
            reg = op & 7
            cf = self.cf
            r[reg] = self.alu(5, r[reg], 1, 2)
            self.cf = cf
            return
        if op < 0x58:
            v = r[op & 7]
            if (op & 7) == 4:
                v = (v - 2) & M16
            self.push(v)
            return
        if op < 0x60:
            r[op & 7] = self.pop()
            return
        if 0x70 <= op < 0x80:
            d = self.f8()
            if self.cond(op & 15):
                self.ip = (self.ip + (d - 256 if d & 0x80 else d)) & M16
            return
        if 0x80 <= op <= 0x83:
            size = 1 if (op & 1) == 0 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            a = self.ea_read(mod, rm, seg, off, size)
            if op == 0x81:
                b = self.f16()
            elif op == 0x83:
                b = self.f8()
                if b & 0x80:
                    b |= 0xFF00
            else:
                b = self.f8()
            res = self.alu(reg, a, b, size)
            if reg != 7:
                self.ea_write(mod, rm, seg, off, size, res)
            return
        if op in (0x84, 0x85):
            size = 1 if op == 0x84 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            a = self.ea_read(mod, rm, seg, off, size)
            b = self.get_r8(reg) if size == 1 else r[reg]
            self.alu(4, a, b, size)
            return
        if op in (0x86, 0x87):
            size = 1 if op == 0x86 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            a = self.ea_read(mod, rm, seg, off, size)
            b = self.get_r8(reg) if size == 1 else r[reg]
            self.ea_write(mod, rm, seg, off, size, b)
            if size == 1:
                self.set_r8(reg, a)
            else:
                r[reg] = a
            return
        if 0x88 <= op <= 0x8B:
            size = 1 if (op & 1) == 0 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            if op < 0x8A:
                v = self.get_r8(reg) if size == 1 else r[reg]
                self.ea_write(mod, rm, seg, off, size, v)
            else:
                v = self.ea_read(mod, rm, seg, off, size)
                if size == 1:
                    self.set_r8(reg, v)
                else:
                    r[reg] = v
            return
        if op == 0x8C:
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            self.ea_write(mod, rm, seg, off, 2, s[reg & 3])
            return
        if op == 0x8D:
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            r[reg] = off
            return
        if op == 0x8E:
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            s[reg & 3] = self.ea_read(mod, rm, seg, off, 2)
            return
        if op == 0x8F:
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            v = self.pop()
            self.ea_write(mod, rm, seg, off, 2, v)
            return
        if op == 0x90:
            return
        if 0x91 <= op <= 0x97:
            reg = op & 7
            r[0], r[reg] = r[reg], r[0]
            return
        if op == 0x98:
            r[0] = (r[0] & 0xFF) | (0xFF00 if r[0] & 0x80 else 0)
            return
        if op == 0x99:
            r[2] = 0xFFFF if r[0] & 0x8000 else 0
            return
        if op == 0x9A:
            o = self.f16()
            sg = self.f16()
            self.push(s[1])
            self.push(self.ip)
            self.ip = o
            s[1] = sg
            return
        if op == 0x9C:
            self.push(self.get_flags())
            return
        if op == 0x9D:
            self.set_flags(self.pop())
            return
        if op == 0x9E:
            f = (r[0] >> 8) & 0xFF
            self.cf = f & 1
            self.pf = (f >> 2) & 1
            self.af = (f >> 4) & 1
            self.zf = (f >> 6) & 1
            self.sf = (f >> 7) & 1
            return
        if op == 0x9F:
            r[0] = (r[0] & 0xFF) | ((self.get_flags() & 0xFF) << 8)
            return
        if 0xA0 <= op <= 0xA3:
            off = self.f16()
            seg = s[seg_ovr if seg_ovr is not None else 3]
            a = (seg << 4) + off
            if op == 0xA0:
                self.set_r8(0, self.rb(a))
            elif op == 0xA1:
                r[0] = self.rw(a)
            elif op == 0xA2:
                self.wb(a, r[0])
            else:
                self.ww(a, r[0])
            return
        if op in (0xA4, 0xA5, 0xA6, 0xA7, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF):
            self.string_op(op, rep, seg_ovr)
            return
        if op == 0xA8:
            self.alu(4, r[0] & 0xFF, self.f8(), 1)
            return
        if op == 0xA9:
            self.alu(4, r[0], self.f16(), 2)
            return
        if 0xB0 <= op <= 0xB7:
            self.set_r8(op & 7, self.f8())
            return
        if 0xB8 <= op <= 0xBF:
            r[op & 7] = self.f16()
            return
        if op == 0xC2:
            n = self.f16()
            self.ip = self.pop()
            r[4] = (r[4] + n) & M16
            return
        if op == 0xC3:
            self.ip = self.pop()
            return
        if op in (0xC4, 0xC5):
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            a = (seg << 4) + off
            r[reg] = self.rw(a)
            s[0 if op == 0xC4 else 3] = self.rw(a + 2)
            return
        if op in (0xC6, 0xC7):
            size = 1 if op == 0xC6 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            v = self.f8() if size == 1 else self.f16()
            self.ea_write(mod, rm, seg, off, size, v)
            return
        if op == 0xCA:
            n = self.f16()
            self.ip = self.pop()
            s[1] = self.pop()
            r[4] = (r[4] + n) & M16
            return
        if op == 0xCB:
            self.ip = self.pop()
            s[1] = self.pop()
            return
        if op == 0xCC:
            self.do_int(3)
            return
        if op == 0xCD:
            self.do_int(self.f8())
            return
        if op == 0xCF:
            self.ip = self.pop()
            s[1] = self.pop()
            self.set_flags(self.pop())
            return
        if 0xD0 <= op <= 0xD3:
            size = 1 if (op & 1) == 0 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            v = self.ea_read(mod, rm, seg, off, size)
            cnt = 1 if op < 0xD2 else (r[1] & 0xFF)
            v = self.shift(reg, v, cnt, size)
            self.ea_write(mod, rm, seg, off, size, v)
            return
        if op == 0xD7:
            a = (s[seg_ovr if seg_ovr is not None else 3] << 4) + ((r[3] + (r[0] & 0xFF)) & M16)
            self.set_r8(0, self.rb(a))
            return
        if 0xD8 <= op <= 0xDF:
            self.modrm(seg_ovr)
            return
        if 0xE0 <= op <= 0xE3:
            d = self.f8()
            if op == 0xE3:
                take = r[1] == 0
            else:
                r[1] = (r[1] - 1) & M16
                take = r[1] != 0
                if op == 0xE0:
                    take = take and not self.zf
                elif op == 0xE1:
                    take = take and bool(self.zf)
            if take:
                self.ip = (self.ip + (d - 256 if d & 0x80 else d)) & M16
            return
        if op == 0xE4:
            self.set_r8(0, self.on_in(self.f8(), 1))
            return
        if op == 0xE5:
            r[0] = self.on_in(self.f8(), 2) & M16
            return
        if op == 0xE6:
            self.on_out(self.f8(), r[0] & 0xFF, 1)
            return
        if op == 0xE7:
            self.on_out(self.f8(), r[0], 2)
            return
        if op == 0xE8:
            d = self.f16()
            self.push(self.ip)
            self.ip = (self.ip + d) & M16
            return
        if op == 0xE9:
            d = self.f16()
            self.ip = (self.ip + d) & M16
            return
        if op == 0xEA:
            o = self.f16()
            sg = self.f16()
            self.ip = o
            s[1] = sg
            return
        if op == 0xEB:
            d = self.f8()
            self.ip = (self.ip + (d - 256 if d & 0x80 else d)) & M16
            return
        if op == 0xEC:
            self.set_r8(0, self.on_in(r[2], 1))
            return
        if op == 0xED:
            r[0] = self.on_in(r[2], 2) & M16
            return
        if op == 0xEE:
            self.on_out(r[2], r[0] & 0xFF, 1)
            return
        if op == 0xEF:
            self.on_out(r[2], r[0], 2)
            return
        if op == 0xF4:
            raise Halt('hlt')
        if op == 0xF5:
            self.cf ^= 1
            return
        if op in (0xF6, 0xF7):
            size = 1 if op == 0xF6 else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            v = self.ea_read(mod, rm, seg, off, size)
            if reg in (0, 1):
                self.alu(4, v, self.f8() if size == 1 else self.f16(), size)
            elif reg == 2:
                self.ea_write(mod, rm, seg, off, size, ~v)
            elif reg == 3:
                res = self.alu(5, 0, v, size)
                self.cf = 1 if v != 0 else 0
                self.ea_write(mod, rm, seg, off, size, res)
            elif reg == 4:   # mul
                if size == 1:
                    res = (r[0] & 0xFF) * v
                    r[0] = res & M16
                    self.cf = self.of = 1 if res > 0xFF else 0
                else:
                    res = r[0] * v
                    r[0] = res & M16
                    r[2] = (res >> 16) & M16
                    self.cf = self.of = 1 if res > M16 else 0
            elif reg == 5:   # imul
                if size == 1:
                    a = (r[0] & 0xFF)
                    a = a - 256 if a & 0x80 else a
                    b = v - 256 if v & 0x80 else v
                    res = a * b
                    r[0] = res & M16
                    self.cf = self.of = 0 if -128 <= res <= 127 else 1
                else:
                    a = r[0] - 65536 if r[0] & 0x8000 else r[0]
                    b = v - 65536 if v & 0x8000 else v
                    res = a * b
                    r[0] = res & M16
                    r[2] = (res >> 16) & M16
                    self.cf = self.of = 0 if -32768 <= res <= 32767 else 1
            elif reg == 6:   # div
                if size == 1:
                    n = r[0]
                    if v == 0 or n // v > 0xFF:
                        self.do_int(0)
                        return
                    q, rem = divmod(n, v)
                    r[0] = (q & 0xFF) | ((rem & 0xFF) << 8)
                else:
                    n = (r[2] << 16) | r[0]
                    if v == 0 or n // v > M16:
                        self.do_int(0)
                        return
                    q, rem = divmod(n, v)
                    r[0] = q & M16
                    r[2] = rem & M16
            else:            # idiv
                if size == 1:
                    n = r[0] - 65536 if r[0] & 0x8000 else r[0]
                    d = v - 256 if v & 0x80 else v
                    if d == 0:
                        self.do_int(0)
                        return
                    q = int(n / d)
                    rem = n - q * d
                    r[0] = (q & 0xFF) | ((rem & 0xFF) << 8)
                else:
                    n = (r[2] << 16) | r[0]
                    n = n - (1 << 32) if n & 0x80000000 else n
                    d = v - 65536 if v & 0x8000 else v
                    if d == 0:
                        self.do_int(0)
                        return
                    q = int(n / d)
                    rem = n - q * d
                    r[0] = q & M16
                    r[2] = rem & M16
            return
        if op == 0xF8:
            self.cf = 0
            return
        if op == 0xF9:
            self.cf = 1
            return
        if op == 0xFA:
            self.if_ = 0
            return
        if op == 0xFB:
            self.if_ = 1
            return
        if op == 0xFC:
            self.df = 0
            return
        if op == 0xFD:
            self.df = 1
            return
        if op in (0xFE, 0xFF):
            size = 1 if op == 0xFE else 2
            mod, reg, rm, seg, off = self.modrm(seg_ovr)
            if reg < 2:
                v = self.ea_read(mod, rm, seg, off, size)
                cf = self.cf
                v = self.alu(0 if reg == 0 else 5, v, 1, size)
                self.cf = cf
                self.ea_write(mod, rm, seg, off, size, v)
            elif reg == 2:
                v = self.ea_read(mod, rm, seg, off, 2)
                self.push(self.ip)
                self.ip = v
            elif reg == 3:
                a = (seg << 4) + off
                self.push(s[1])
                self.push(self.ip)
                self.ip = self.rw(a)
                s[1] = self.rw(a + 2)
            elif reg == 4:
                self.ip = self.ea_read(mod, rm, seg, off, 2)
            elif reg == 5:
                a = (seg << 4) + off
                self.ip = self.rw(a)
                s[1] = self.rw(a + 2)
            else:
                v = self.ea_read(mod, rm, seg, off, 2)
                self.push(v)
            return
        raise Halt('unsupported opcode %02X at %04X:%04X' % (op, s[1], start_ip))

    def string_op(self, op, rep, seg_ovr):
        r, s = self.r, self.s
        size = 1 if (op & 1) == 0 else 2
        step = (-size if self.df else size)
        src_seg = s[seg_ovr if seg_ovr is not None else 3]
        base = op & 0xFE
        while True:
            if rep and r[1] == 0:
                return
            if base == 0xA4:       # movs
                a = (src_seg << 4) + r[6]
                v = self.rb(a) if size == 1 else self.rw(a)
                d = (s[0] << 4) + r[7]
                if size == 1:
                    self.wb(d, v)
                else:
                    self.ww(d, v)
                r[6] = (r[6] + step) & M16
                r[7] = (r[7] + step) & M16
            elif base == 0xA6:     # cmps
                a = (src_seg << 4) + r[6]
                x = self.rb(a) if size == 1 else self.rw(a)
                d = (s[0] << 4) + r[7]
                y = self.rb(d) if size == 1 else self.rw(d)
                self.alu(7, x, y, size)
                r[6] = (r[6] + step) & M16
                r[7] = (r[7] + step) & M16
            elif base == 0xAA:     # stos
                d = (s[0] << 4) + r[7]
                if size == 1:
                    self.wb(d, r[0])
                else:
                    self.ww(d, r[0])
                r[7] = (r[7] + step) & M16
            elif base == 0xAC:     # lods
                a = (src_seg << 4) + r[6]
                if size == 1:
                    self.set_r8(0, self.rb(a))
                else:
                    r[0] = self.rw(a)
                r[6] = (r[6] + step) & M16
            else:                  # scas
                d = (s[0] << 4) + r[7]
                y = self.rb(d) if size == 1 else self.rw(d)
                self.alu(7, (r[0] & 0xFF) if size == 1 else r[0], y, size)
                r[7] = (r[7] + step) & M16
            if not rep:
                return
            r[1] = (r[1] - 1) & M16
            self.icount += 1
            if base in (0xA6, 0xAE):
                if rep == 3 and not self.zf:
                    return
                if rep == 2 and self.zf:
                    return
