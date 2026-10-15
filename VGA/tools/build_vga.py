"""Build the experimental VGA Commando: assemble src/vga.s, pack the approved artwork and write a PATCHED COPY of the
game into VGA/build.  The original files in the parent folder are only read, never written.

Layout of the new EXE (image offsets, image = EXE minus 512-byte MZ header):
    0000-834F   original code segment (patched call sites / entry trampolines)
    8350-C34F   new VGA code (CS window; reserved 16 KB)
    C350-....   artwork (paragraph aligned) then the 28 KB VGA ground ring (zero initialised)
    ....        original data segment, moved up by K paragraphs (DS and SS are corrected)
"""
import os, sys, struct, subprocess, hashlib, shutil, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')   # the user's own original game files (not in the repository)
BUILD = os.path.join(HERE, 'build')
BIN = os.environ.get('COMMANDO_BINUTILS', r'C:\FPC\3.2.2\bin\i386-win32')   # folder with GNU as, ld, nm, objcopy
EXE_SHA = '4F53975ABF756A27BA94713C32134F501F5349A80798151E78666FA6A6D52D4E'
DAT_SHA = 'E92EC0D64715DEADA88495E5415634FDE05B155C3EDEDAE2B0E00844A26AAAE9'
CODE_BASE, CODE_RESERVED = 0x8360, 0x4000   # 0x8350-0x835F stays: the last code bytes (pop bp / ret) overlap the first DS paragraph
ASSET_OFF = CODE_BASE + CODE_RESERVED
RING_BYTES = 0x7000


def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest().upper()


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=HERE, **kw)
    if r.returncode != 0:
        raise SystemExit('FAILED: %s\n%s%s' % (' '.join(cmd), r.stdout, r.stderr))
    return r.stdout


def assemble(cms=0):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import vga_assets
    r = vga_assets.build()
    vga_assets.write_tables(*r, snd_cms=cms)
    run([BIN + r'\as.exe', '--32', '-I', HERE, '-o', 'build/vga.o', 'src/vga.s'])
    run([BIN + r'\ld.exe', '-m', 'i386pe', '--image-base', '0', '--section-alignment', '1', '--file-alignment', '1',
         '-Ttext', '0x%X' % CODE_BASE, '-e', 'vga_base', '-o', 'build/vga.pe', 'build/vga.o'])
    run([BIN + r'\objcopy.exe', '-O', 'binary', '-j', '.text', 'build/vga.pe', 'build/vga.bin'])
    syms = {}
    for line in run([BIN + r'\nm.exe', 'build/vga.pe']).splitlines():
        p = line.split()
        if len(p) == 3:
            syms[p[2]] = int(p[0], 16)
    code = open(os.path.join(BUILD, 'vga.bin'), 'rb').read()
    code = code[:syms['vga_end'] - CODE_BASE]
    assert len(code) <= CODE_RESERVED, 'VGA code too large: %d' % len(code)
    return code, syms, r[-1]


CALL_E8 = 0xE8
JMP_E9 = 0xE9


def rel16(src_next, target):
    d = (target - src_next) & 0xFFFF
    return struct.pack('<H', d)


def patch(code_part, syms, cms=0):
    img = bytearray(code_part)
    log = []

    def jmp(at, hook):
        img[at] = JMP_E9
        img[at + 1:at + 3] = rel16(at + 3, syms[hook])
        log.append('jmp  %04X -> %s' % (at, hook))

    def call(at, old_target, hook):
        assert img[at] == CALL_E8, 'no call at %04X' % at
        assert (at + 3 + struct.unpack_from('<H', img, at + 1)[0]) & 0xFFFF == old_target, 'unexpected call target at %04X' % at
        img[at + 1:at + 3] = rel16(at + 3, syms[hook])
        log.append('call %04X %04X -> %s' % (at, old_target, hook))

    def imm(at, old, new):
        assert bytes(img[at:at + len(old)]) == old, 'bytes differ at %04X' % at
        img[at:at + len(new)] = new
        log.append('imm  %04X %s -> %s' % (at, old.hex(), new.hex()))

    # entry trampolines for routines that are replaced as a whole
    for at, hook, first in [(0x7590, 'hook_ramfill', 0x55), (0x77AA, 'hook_clearscreen', 0x50), (0x8139, 'hook_present', 0xE8),
                            (0x8172, 'hook_retrace', 0x53), (0x77C1, 'hook_addr', 0x56), (0x7C3F, 'hook_sprite', 0x50),
                            (0x7899, 'hook_restore', 0x50), (0x6D4E, 'hook_glyph', 0x50), (0x18A3, 'hook_title', 0x55),
                            (0x6A2B, 'hook_dissolve', 0x55), (0x76D1, 'hook_groundblit', 0x55), (0x7743, 'hook_colorkey', 0x55)]:
        assert img[at] == first, 'unexpected first byte %02X at %04X' % (img[at], at)
        jmp(at, hook)
    call(0x6A1D, 0x8310, 'hook_setmode')
    call(0x5134, 0x5F5D, 'hook_orblit')
    call(0x5157, 0x5F5D, 'hook_orblit')
    call(0x5173, 0x6498, 'hook_copyblit')
    call(0x5196, 0x6498, 'hook_copyblit')
    call(0x5585, 0x64C1, 'hook_fillrow')
    call(0x55A6, 0x64C1, 'hook_fillrow')
    call(0x571D, 0x64C1, 'hook_clearground')
    call(0x533D, 0x64C1, 'hook_clearground')
    imm(0x3313, bytes.fromhex('b80004'), bytes.fromhex('b80010'))          # RAM screen: 4000h -> 10000h paragraphs... 64 KB
    for at in (0x6C27, 0x6C4E, 0x75D7, 0x75F2, 0x77AE):                  # B800h -> A000h
        imm(at, bytes.fromhex('b800b8'), bytes.fromhex('b800a0'))
    for at in (0x6C70, 0x6CCC):                                           # next character: +3 CGA bytes -> +12 VGA pixels
        imm(at, bytes.fromhex('414141'), bytes.fromhex('83c10c'))

    # ---- sound layer (src/snd.s) ----
    jmp(0x0010, 'hook_entry')                                             # program entry: install INT 60h/61h, detect AdLib
    assert bytes(img[0xC8:0xCD]) == bytes.fromhex('b8004ccd21')           # program exit: restore vectors, silence devices
    img[0xC8] = JMP_E9
    img[0xC9:0xCB] = rel16(0xCB, syms['hook_exit'])
    img[0xCB:0xCD] = b'\x90\x90'
    log.append('jmp  00C8 -> hook_exit')
    for at in (0x66BD, 0x66F5, 0x674E, 0x67A1, 0x67BD, 0x67F2, 0x686F, 0x6895, 0x68C5, 0x6941, 0x698E):
        imm(at, bytes.fromhex('e661'), bytes.fromhex('cd60'))             # OUT 61h,AL -> INT 60h
    for at in (0x6889, 0x688D, 0x6982, 0x6986, 0x69DA, 0x69DE):
        imm(at, bytes.fromhex('e642'), bytes.fromhex('cd61'))             # OUT 42h,AL -> INT 61h
    call(0x828E, 0x69A5, 'hook_tick')                                     # sound tick in the IRQ0 handler
    imm(0x685A, bytes.fromhex('2e8b84da65'), bytes.fromhex('e8') + rel16(0x685D, syms['hook_notefetch']) + b'\x90\x90')
    assert bytes(img[0x363D:0x3640]) == bytes.fromhex('e88130')           # M key: cycle the sound device
    img[0x363D] = CALL_E8
    img[0x363E:0x3640] = rel16(0x3640, syms['hook_mkey'])
    img[0x3640] = JMP_E9
    img[0x3641:0x3643] = rel16(0x3643, 0x3697)
    log.append('call 363D -> hook_mkey; jmp 3697')
    assert bytes(img[0x60CE:0x60D1]) == bytes.fromhex('e8f005')           # pause screen: show the sound device instead of ON/OFF
    img[0x60CE:0x60EF] = b'\x90' * 33
    img[0x60CE] = CALL_E8
    img[0x60CF:0x60D1] = rel16(0x60D1, syms['hook_modetext'])
    img[0x60D1] = JMP_E9
    img[0x60D2:0x60D4] = rel16(0x60D4, 0x60EF)
    log.append('call 60CE -> hook_modetext')
    if cms:
        jmp(0x6784, 'hook_setmusic')
        jmp(0x66C1, 'hook_getmusic')
    return bytes(img), log


def build(cms=0, version='dev'):
    exe_p, dat_p = os.path.join(ROOT, 'COMMANDO.EXE'), os.path.join(ROOT, 'COMMANDO.DAT')
    assert sha(exe_p) == EXE_SHA and sha(dat_p) == DAT_SHA, 'unsupported original files'
    exe = open(exe_p, 'rb').read()
    (sig, last, pages, nreloc, hdrpar, minalloc, maxalloc, ss, sp, csum, ip, cs, reloff, ovl) = struct.unpack_from('<2s13H', exe, 0)
    hdr = bytearray(exe[:hdrpar * 16])
    size = (pages - 1) * 512 + last
    image = bytearray(exe[hdrpar * 16:size])
    assert len(image) == 71071

    code, syms, info = assemble(cms)
    code_part, log = patch(image[:CODE_BASE], syms, cms)
    data_part = bytearray(image[0x8350:])
    old = b' (M)  Toggle Music\x00'
    at = data_part.find(old)
    assert at == 0x915E, at
    data_part[at:at + len(old)] = b' (M)  Music Device\x00'     # same length as the original text
    data_part = bytes(data_part)

    assets = open(os.path.join(BUILD, 'assets.bin'), 'rb').read()
    assets += bytes(-len(assets) % 16)
    block = bytearray(code) + bytes(CODE_RESERVED - len(code)) + assets + bytes(RING_BYTES)
    if cms:      # embedded SID arrangement for the CMS device: two banks of 60000 + 53907 bytes (paragraph aligned)
        score = open(os.path.join(HERE, 'audio', 'sidenv_full.bin'), 'rb').read()
        assert len(score) == 113907
        block += score + bytes(-len(score) % 16)
    assert len(block) % 16 == 0
    K = len(block) // 16
    new_ds = (CODE_BASE + len(block)) // 16

    # the data segment moved up by K paragraphs: fix the two relocated DS immediates (and SS)
    new_image = bytearray(code_part) + block + data_part
    for at in (0x00A7, 0x8288):
        v = struct.unpack_from('<H', new_image, at)[0]
        assert v == 0x835, 'DS immediate at %04X is %04X' % (at, v)
        struct.pack_into('<H', new_image, at, new_ds)
    total = len(new_image) + len(hdr)
    struct.pack_into('<H', hdr, 2, total % 512)
    struct.pack_into('<H', hdr, 4, (total + 511) // 512)
    struct.pack_into('<H', hdr, 14, (ss + new_ds - 0x835) & 0xFFFF)
    out = os.path.join(BUILD, 'COMMANDO.EXE')
    open(out, 'wb').write(bytes(hdr) + bytes(new_image))
    for f in ('COMMANDO.DAT', 'START.COM', 'STARTC.COM'):
        shutil.copyfile(os.path.join(ROOT, f), os.path.join(BUILD, f))
    open(os.path.join(BUILD, 'patch_log.txt'), 'w').write('\n'.join(log) + '\n\nK=%d paragraphs, DS=%04X, code=%d bytes, assets=%d bytes\n%s\n' % (K, new_ds, len(code), len(assets), info))
    print('built', out, 'size', os.path.getsize(out), 'code', len(code), 'assets', len(assets), 'K', K, 'DS', hex(new_ds))
    return syms


if __name__ == '__main__':
    build(cms=int(sys.argv[1]) if len(sys.argv) > 1 else 0)
