"""Contact sheet of PNG files: montage.py OUT COLS FILES..."""
import sys
from PIL import Image, ImageDraw
out, cols = sys.argv[1], int(sys.argv[2])
files = sys.argv[3:]
ims = [Image.open(f).convert('RGB') for f in files]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * (w + 4), rows * (h + 16)), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(zip(files, ims)):
    x, y = (i % cols) * (w + 4), (i // cols) * (h + 16)
    sheet.paste(im, (x, y + 14))
    d.text((x + 2, y + 1), f.replace('\\', '/').split('/')[-1], fill=(255, 255, 0))
sheet.save(out)
print(sheet.size)
