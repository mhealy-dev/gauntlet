"""Decode BLP2 RAW1 (palettized) cursors to RGBA PNG, honoring 1/4/8-bit alpha."""
import os, struct, sys
from PIL import Image

def decode(path):
    d = open(path, 'rb').read()
    magic, version = d[:4], struct.unpack('<I', d[4:8])[0]
    assert magic == b'BLP2' and version == 1, (magic, version)
    enc, alpha_bits, pref, has_mips = d[8], d[9], d[10], d[11]
    w, h = struct.unpack('<II', d[12:20])
    offs = struct.unpack('<16I', d[20:84])
    sizes = struct.unpack('<16I', d[84:148])
    assert enc == 1, f'only RAW1 palettized supported, got {enc}'
    palette = [struct.unpack('<4B', d[148+i*4:152+i*4]) for i in range(256)]  # BGRA
    mip = d[offs[0]:offs[0]+sizes[0]]
    idx = mip[:w*h]
    adata = mip[w*h:]
    im = Image.new('RGBA', (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            i = y*w + x
            b, g, r, _ = palette[idx[i]]
            if alpha_bits == 0:
                a = 255
            elif alpha_bits == 1:
                a = 255 if (adata[i // 8] >> (i % 8)) & 1 else 0
            elif alpha_bits == 4:
                nib = (adata[i // 2] >> (4 * (i % 2))) & 0xF
                a = nib * 17
            else:
                a = adata[i]
            px[x, y] = (r, g, b, a)
    return im

if __name__ == '__main__':
    src_dir, dst_dir = sys.argv[1], sys.argv[2]
    os.makedirs(dst_dir, exist_ok=True)
    for f in sorted(os.listdir(src_dir)):
        if not f.endswith('.blp'): continue
        im = decode(os.path.join(src_dir, f))
        im.save(os.path.join(dst_dir, f.replace('.blp', '.png')))
    print('done')
