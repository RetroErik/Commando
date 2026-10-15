"""Render a 10-second Plantronics ColorPlus clip from the emulator (DOSBox cannot show ColorPlus).

The demo starts by itself after the title; the first gameplay frame is detected from the cyan panel frame.  One frame is captured per screen
present (INT 62h in the Plantronics loader) and played back at 20 frames/s, the rate measured for the original game in DOSBox
(about 20 distinct frames/s for CGA and VGA at 4000 cycles/ms).  Output: PNG frames and an MP4 without sound.
python make_plantronics_clip.py OUTDIR [seconds]
"""
import sys, os, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_plantronics import *
import emu_game
from PIL import Image

FPS = 20
FFMPEG = os.environ.get('FFMPEG', r'C:\ffmpeg\ffmpeg.exe')


def cyan_border(im):
    px = im.load()
    return sum(1 for x in range(60, 260) for y in range(10, 16) if px[x, y] == (0, 170, 170))


out = os.path.abspath(sys.argv[1])
seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 10
os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    if f.startswith('frame_'):
        os.remove(os.path.join(out, f))
g = PlanGame()
os.chdir(PLAN)
c = g.cpu
while c.icount < 80_000_000:
    g.run(200_000)
    if cyan_border(g.frame_plantronics()) > 300:
        break
print('gameplay detected at instruction', c.icount)
frames = []
orig_on_int = g.on_int


def on_int(num):
    if num == 0x62 and len(frames) < FPS * seconds:
        frames.append(g.frame_plantronics().resize((640, 400), Image.NEAREST))
    return orig_on_int(num)


c.on_int = on_int
g.run(400_000_000, stop_cb=lambda gg: len(frames) >= FPS * seconds)
for i, im in enumerate(frames):
    im.save(os.path.join(out, 'frame_%04d.png' % i))
print('captured', len(frames), 'frames, instructions', c.icount)
mp4 = os.path.join(out, 'commando_plantronics.mp4')
subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', str(FPS), '-i', os.path.join(out, 'frame_%04d.png'),
                '-vf', 'fps=30,format=yuv420p', '-c:v', 'libx264', '-preset', 'slow', '-crf', '22', '-movflags', '+faststart', mp4], check=True)
print(mp4, os.path.getsize(mp4))
