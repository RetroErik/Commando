"""Run the original COMMANDO.EXE (or a patched copy) headlessly in the 8086 emulator.

Usage: python emu_game.py [--exe PATH] [--instr N] [--snap-every M] [--out DIR]
"""
import os, sys, struct, argparse, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu86 import CPU, Halt
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')   # the user's own original game files (not in the repository)
CGA_PAL = [(0, 0, 0), (85, 255, 255), (255, 85, 255), (255, 255, 255)]
PSP_SEG = 0x1000
LOAD_SEG = PSP_SEG + 0x10


class Game:
    def __init__(self, exe_path, tick_period=30000):
        self.cpu = c = CPU()
        self.exe = open(exe_path, 'rb').read()
        self.tick_period = tick_period
        self.unknown_ints = {}
        self.video_mode = 3
        self.dos_next_seg = 0
        self.vga_reads = 0
        self.log = []
        self.screen_mem_blocks = []
        self.load()
        c.on_int = self.on_int
        c.on_service = self.service
        c.on_in = self.on_in
        c.on_out = self.on_out
        self.next_tick = tick_period
        self.palette = [(0, 0, 0)] * 256
        self.ticks = 0
        self.ports = {}
        self.pit_div = 0

    def load(self):
        c, exe = self.cpu, self.exe
        (sig, last, pages, nreloc, hdrpar, minalloc, maxalloc, ss, sp, csum, ip, cs, reloff, ovl) = struct.unpack_from('<2s13H', exe, 0)
        size = (pages - 1) * 512 + last
        image = exe[hdrpar * 16: size]
        base = LOAD_SEG * 16
        c.mem[base:base + len(image)] = image
        for i in range(nreloc):
            off, seg = struct.unpack_from('<2H', exe, reloff + 4 * i)
            a = base + seg * 16 + off
            v = struct.unpack_from('<H', c.mem, a)[0]
            struct.pack_into('<H', c.mem, a, (v + LOAD_SEG) & 0xFFFF)
        # PSP
        c.mem[PSP_SEG * 16:PSP_SEG * 16 + 2] = b'\xcd\x20'
        struct.pack_into('<H', c.mem, PSP_SEG * 16 + 2, 0x9FC0)
        # BIOS data area
        struct.pack_into('<H', c.mem, 0x413, 640)
        struct.pack_into('<H', c.mem, 0x410, 0x0021)
        # IVT: every vector -> F000:n (python services)
        for n in range(256):
            struct.pack_into('<HH', c.mem, n * 4, n, 0xF000)
        c.s[0] = c.s[3] = PSP_SEG
        c.s[1] = (cs + LOAD_SEG) & 0xFFFF
        c.s[2] = (ss + LOAD_SEG) & 0xFFFF
        c.r[4] = sp
        c.ip = ip
        c.r[0] = 0
        self.prog_end_seg = LOAD_SEG + (len(image) + 15) // 16 + minalloc
        self.dos_next_seg = (self.prog_end_seg + 0x10) & ~0xF

    # ---- video
    def cga_frame(self, seg=0xB800, offset=0):
        m = self.cpu.mem
        base = seg * 16 + offset
        im = Image.new('P', (320, 200))
        pal = []
        for c in CGA_PAL:
            pal += list(c)
        im.putpalette(pal + [0] * (768 - len(pal)))
        px = im.load()
        for y in range(200):
            row = base + (y & 1) * 0x2000 + (y >> 1) * 80
            for xb in range(80):
                b = m[row + xb]
                x = xb * 4
                px[x, y] = b >> 6
                px[x + 1, y] = (b >> 4) & 3
                px[x + 2, y] = (b >> 2) & 3
                px[x + 3, y] = b & 3
        return im

    # ---- services
    def on_in(self, port, size):
        if port == 0x3DA:
            self.vga_reads += 1
            v = (8 if (self.vga_reads // 3) % 4 == 0 else 0) | (1 if self.vga_reads & 1 else 0)
            return v
        if port == 0x60:
            return self.last_scancode
        if port == 0x201:
            return 0xFF
        if port == 0x388:
            # minimal OPL2 status: timer 1 overflow flags appear a while after reg 4 = 21h (card detection)
            if self.opl_timer_started and self.icount_now() - self.opl_timer_started > 200:
                return 0xC0
            return 0x00
        return self.ports.get(port, 0)

    last_scancode = 0

    def key(self, scancode):
        """Deliver a keyboard scancode through the game's INT 9 handler (if installed)."""
        self.last_scancode = scancode
        if self.cpu.rw(9 * 4 + 2) != 0xF000:
            self.cpu.pending_irq.append(9)

    opl_timer_started = 0
    opl_reg = 0
    io_log = None          # set to [] to record (icount, port, value) for the ports in io_watch
    io_watch = (0x42, 0x61, 0x388, 0x389, 0x220, 0x221, 0x222, 0x223)

    def icount_now(self):
        return self.cpu.icount

    def on_out(self, port, v, size):
        self.ports[port] = v
        if port == 0x388:
            self.opl_reg = v
        elif port == 0x389:
            if self.opl_reg == 4 and (v & 1):
                self.opl_timer_started = self.cpu.icount
            elif self.opl_reg == 4 and v == 0x60:
                self.opl_timer_started = 0
        if self.io_log is not None and port in self.io_watch:
            self.io_log.append((self.cpu.icount, port, v))
        if port == 0x40:
            self.pit_bytes = getattr(self, 'pit_bytes', []) + [v]

    def on_int(self, n):
        c = self.cpu
        vec_off = c.rw(n * 4)
        vec_seg = c.rw(n * 4 + 2)
        if vec_seg != 0xF000:
            return False   # a real handler installed by the game
        self.service(n)
        return True

    def service(self, n):
        handler = getattr(self, 'int_%02X' % n, None)
        if handler is None:
            self.unknown_ints[n] = self.unknown_ints.get(n, 0) + 1
            return
        handler()

    def ret_cf(self, cf):
        # modify the CF in the flags the real INT would have returned
        self.cpu.cf = cf

    def int_08(self):
        pass

    def int_10(self):
        c = self.cpu
        ah = (c.r[0] >> 8) & 0xFF
        if ah == 0:
            self.video_mode = c.r[0] & 0xFF
            self.log.append(('mode', self.video_mode, c.icount))
        elif ah == 0x10 and (c.r[0] & 0xFF) == 0x12:
            first, count = c.r[3], c.r[1]
            a = (c.s[0] << 4) + c.r[2]
            for i in range(count):
                r, g, b = c.mem[a + 3 * i: a + 3 * i + 3]
                self.palette[(first + i) & 255] = (min(255, r * 4 + (r >> 4)), min(255, g * 4 + (g >> 4)), min(255, b * 4 + (b >> 4)))
        elif ah == 0x0F:
            c.r[0] = 0x5000 | self.video_mode
            c.r[3] &= 0x00FF
        elif ah == 0x06:
            self.log.append(('scroll', c.r[0], c.r[3] >> 8, c.icount))

    palette = [(0, 0, 0)] * 256

    def vga_frame(self):
        m = self.cpu.mem
        im = Image.new('P', (320, 200))
        pal = []
        for col in self.palette:
            pal += list(col)
        im.putpalette(pal)
        im.frombytes(bytes(m[0xA0000:0xA0000 + 64000]))
        return im

    def frame(self):
        return self.vga_frame() if self.video_mode == 0x13 else self.cga_frame()

    def int_11(self):
        self.cpu.r[0] = 0x0021

    def int_12(self):
        self.cpu.r[0] = 640

    key_queue = None

    dat = None

    def int_13(self):
        """Serve floppy reads from COMMANDO.DAT like the original STARTC.COM launcher (track*4096 + (sector-1)*512)."""
        c = self.cpu
        if self.dat is None:
            self.dat = open(os.path.join(ROOT, 'COMMANDO.DAT'), 'rb').read()
        ah = (c.r[0] >> 8) & 0xFF
        dl = c.r[2] & 0xFF
        if ah == 2 and dl == 0:
            count = c.r[0] & 0xFF
            track = (c.r[1] >> 8) & 0xFF
            sector = c.r[1] & 0xFF
            off = track * 4096 + (sector - 1) * 512
            data = self.dat[off: off + count * 512]
            a = (c.s[0] << 4) + c.r[3]
            c.mem[a:a + len(data)] = data
            c.r[0] = count
            c.cf = 0
            self.log.append(('int13', track, sector, count, c.s[0] - LOAD_SEG - 0x835, c.r[3]))
        else:
            c.r[0] = 0x0400
            c.cf = 1

    def int_16(self):
        c = self.cpu
        if self.key_queue is None:
            self.key_queue = []
        ah = (c.r[0] >> 8) & 0xFF
        if ah in (1, 0x11):
            if self.key_queue:
                c.r[0] = self.key_queue[0]
                c.zf = 0
            else:
                c.zf = 1
        elif ah in (0, 0x10):
            c.r[0] = self.key_queue.pop(0) if self.key_queue else 0
        elif ah == 2:
            c.r[0] &= 0xFF00

    def press(self, bios_key):
        """Queue a BIOS key (scan<<8 | ascii) for INT 16h."""
        if self.key_queue is None:
            self.key_queue = []
        self.key_queue.append(bios_key)

    def int_1A(self):
        c = self.cpu
        c.r[1] = (self.ticks >> 16) & 0xFFFF
        c.r[2] = self.ticks & 0xFFFF
        c.r[0] &= 0x00FF

    def int_21(self):
        c = self.cpu
        ah = (c.r[0] >> 8) & 0xFF
        al = c.r[0] & 0xFF
        r = c.r
        c.cf = 0
        if ah == 0x25:
            struct.pack_into('<HH', c.mem, al * 4, r[2], c.s[3])
        elif ah == 0x35:
            r[3] = c.rw(al * 4)
            c.s[0] = c.rw(al * 4 + 2)
        elif ah == 0x30:
            r[0] = 0x0003
        elif ah == 0x34:
            c.s[0] = 0x0050
            r[3] = 0
        elif ah == 0x48:
            need = r[3]
            seg = self.dos_next_seg
            if seg + need >= 0x9F00:
                c.cf = 1
                r[0] = 8
                r[3] = max(0, 0x9F00 - seg)
            else:
                r[0] = seg
                self.dos_next_seg = seg + need
                self.screen_mem_blocks.append((seg, need))
        elif ah in (0x49, 0x4A):
            pass
        elif ah == 0x4C:
            raise Halt('exit %02X' % al)
        elif ah == 0x09:
            a = (c.s[3] << 4) + r[2]
            s = bytearray()
            while c.mem[a] != 0x24:
                s.append(c.mem[a])
                a += 1
            self.log.append(('print', bytes(s)))
        elif ah == 0x2C:
            r[1] = 0x0C00
            r[2] = 0x0000
        elif ah == 0x2A:
            r[1] = 1999
            r[2] = 0x0101
        elif ah in (0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x4E):
            c.cf = 1
            r[0] = 2
        else:
            self.unknown_ints[(0x21, ah)] = self.unknown_ints.get((0x21, ah), 0) + 1

    def int_20(self):
        raise Halt('int 20')

    def tick(self):
        self.ticks += 1
        c = self.cpu
        if c.rw(0x20 + 2) != 0xF000:
            c.pending_irq.append(8)

    virtual_time = False
    vt_last_retrace = 0
    retrace_calls = 0
    frame_calls = 0
    vt_acc = 0
    fallback_period = 600000

    def run(self, max_instr, snap_every=None, outdir=None, snap_cb=None, stop_cb=None):
        c = self.cpu
        n = 0
        snaps = 0
        t0 = time.time()
        try:
            while n < max_instr:
                before = c.icount
                if self.virtual_time and c.s[1] == LOAD_SEG:
                    if c.ip == 0x8172:
                        # deterministic time: every retrace wait advances the game clock by 1/60 s (1.82 PIT ticks)
                        self.retrace_calls += 1
                        self.vt_last_retrace = c.icount
                        self.vt_acc += 182
                        for _ in range(self.vt_acc // 100):
                            self.tick()
                        self.vt_acc %= 100
                    elif c.ip == 0x57DC:
                        self.frame_calls += 1
                c.step()
                n += max(1, c.icount - before)
                if self.virtual_time:
                    if c.icount - self.vt_last_retrace > 20000:      # a loop that never waits for retrace (title, name entry)
                        self.vt_last_retrace = c.icount
                        self.tick()
                    if c.icount >= self.next_tick:
                        self.next_tick += self.fallback_period
                        self.tick()
                elif c.icount >= self.next_tick:
                    self.next_tick += self.tick_period
                    self.tick()
                if snap_every and snap_cb and (c.icount // snap_every) > snaps:
                    snaps = c.icount // snap_every
                    snap_cb(self, snaps)
                if stop_cb and stop_cb(self):
                    break
        except Halt as e:
            self.log.append(('halt', str(e), c.icount))
        return time.time() - t0


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--exe', default=os.path.join(ROOT, 'COMMANDO.EXE'))
    ap.add_argument('--instr', type=int, default=3_000_000)
    ap.add_argument('--snap-every', type=int, default=0)
    ap.add_argument('--out', default=os.path.join(HERE, 'test', 'emu'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    g = Game(a.exe)

    def snap(game, i):
        game.cga_frame().convert('RGB').save(os.path.join(a.out, 'frame_%03d.png' % i))

    dt = g.run(a.instr, a.snap_every, a.out, snap)
    g.cga_frame().convert('RGB').save(os.path.join(a.out, 'final.png'))
    c = g.cpu
    print('instr %d  time %.1fs  CS:IP %04X:%04X  mode %d  ticks %d' % (c.icount, dt, c.s[1], c.ip, g.video_mode, g.ticks))
    print('unknown ints', g.unknown_ints)
    print('log', g.log[-12:])

