"""Disassemble a range of the original EXE load image: dis.py START END  (hex, image offsets)."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
img = os.path.join(HERE, 'analysis', 'image.bin')
a, b = int(sys.argv[1], 16), int(sys.argv[2], 16)
objdump = r'C:\FPC\3.2.2\bin\i386-win32\objdump.exe'
out = subprocess.run([objdump, '-D', '-b', 'binary', '-m', 'i8086', '-M', 'intel',
                      '--start-address=0x%X' % a, '--stop-address=0x%X' % b, img],
                     capture_output=True, text=True).stdout
for line in out.splitlines():
    if ':\t' in line:
        addr, rest = line.split(':\t', 1)
        parts = rest.split('\t')
        print('%04X  %-18s %s' % (int(addr, 16), parts[0].strip(), parts[1].strip() if len(parts) > 1 else ''))
