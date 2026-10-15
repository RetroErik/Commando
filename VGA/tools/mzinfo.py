"""Print the MZ header of the original COMMANDO.EXE (read-only)."""
import struct, sys, os

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'Original game files')
exe = open(os.path.join(ROOT, 'COMMANDO.EXE'), 'rb').read()
(sig, last, pages, nreloc, hdrpar, minalloc, maxalloc, ss, sp, csum, ip, cs, reloff, ovl) = \
    struct.unpack_from('<2s13H', exe, 0)
print('sig', sig, 'size', len(exe))
print('pages', pages, 'lastpage', last, 'header bytes', hdrpar * 16)
print('minalloc %04X maxalloc %04X' % (minalloc, maxalloc))
print('SS:SP %04X:%04X  CS:IP %04X:%04X' % (ss, sp, cs, ip))
print('reloc count', nreloc, 'at', hex(reloff))
rel = []
for i in range(nreloc):
    off, seg = struct.unpack_from('<2H', exe, reloff + 4 * i)
    rel.append((seg, off))
print('image size', len(exe) - hdrpar * 16, 'file image per header', ((pages - 1) * 512 + last) - hdrpar * 16)
for seg, off in rel[:80]:
    fo = hdrpar * 16 + seg * 16 + off
    print('reloc %04X:%04X file %05X value %04X' % (seg, off, fo, struct.unpack_from('<H', exe, fo)[0]))
