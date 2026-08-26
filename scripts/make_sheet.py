"""Build a labelled contact sheet of dumped cursors.

usage: make_sheet.py <png_dir> <meta_file> <out.png>

<meta_file> is dump_cursors' stdout: "N width height frameCount" per line.
Animated cursors come back as a vertical frame strip, so we crop to frame 1.
"""
import os, sys
from PIL import Image, ImageDraw

CELL, COLS, SCALE = 130, 7, 2

def main(png_dir, meta_file, out_path):
    frames = {}
    for line in open(meta_file):
        parts = line.split()
        if len(parts) == 4:
            frames[int(parts[0])] = int(parts[3])

    files = sorted((f for f in os.listdir(png_dir) if f.endswith('.png')),
                   key=lambda f: int(f[:-4]))
    rows = (len(files) + COLS - 1) // COLS
    sheet = Image.new('RGBA', (COLS * CELL, rows * CELL), (32, 32, 38, 255))
    draw = ImageDraw.Draw(sheet)

    for i, f in enumerate(files):
        n = int(f[:-4])
        im = Image.open(os.path.join(png_dir, f)).convert('RGBA')
        count = frames.get(n, 1)
        if count > 1:                       # vertical strip -> first frame
            im = im.crop((0, 0, im.width, im.height // count))
        im = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
        box = CELL - 18
        if im.width > box or im.height > box:
            im.thumbnail((box, box), Image.NEAREST)

        cx, cy = (i % COLS) * CELL, (i // COLS) * CELL
        draw.rectangle([cx + 1, cy + 1, cx + CELL - 2, cy + CELL - 2],
                       outline=(70, 70, 80, 255))
        sheet.alpha_composite(im, (cx + (CELL - im.width) // 2,
                                   cy + (CELL - im.height) // 2 + 8))
        draw.text((cx + 6, cy + 4), 'cursor.%d%s' % (n, ' *' if count > 1 else ''),
                  fill=(255, 210, 70, 255))

    sheet.save(out_path)
    print('wrote', out_path, '(%d cursors)' % len(files))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
