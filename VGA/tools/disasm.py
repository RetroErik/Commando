"""Split the original EXE into load image (without MZ header) and run objdump on the code area."""
import os, subprocess
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')
exe = open(os.path.join(ROOT, 'COMMANDO.EXE'), 'rb').read()
img = exe[0x200:]
open(os.path.join(HERE, 'analysis', 'image.bin'), 'wb').write(img)
objdump = r'C:\FPC\3.2.2\bin\i386-win32\objdump.exe'
out = subprocess.run([objdump, '-D', '-b', 'binary', '-m', 'i8086', '-M', 'intel',
                      '--stop-address=0x8350', os.path.join(HERE, 'analysis', 'image.bin')],
                     capture_output=True, text=True).stdout
open(os.path.join(HERE, 'analysis', 'code_disasm.txt'), 'w').write(out)
print(len(out.splitlines()), 'lines')
