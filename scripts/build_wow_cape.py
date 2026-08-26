"""Build capes/wow from decoded retail cursor PNGs.

usage: build_wow_cape.py <png_dir> <cape_dir>
"""
import json, os, sys
from PIL import Image

# gauntlet slot -> retail cursor art
MAPPING = {
    'arrow':     'Point',        # main pointer: the gauntlet
    'ctxarrow':  'Point',
    'link':      'Point',
    'pointing':  'Point',
    'forbidden': 'UnablePoint',  # red-tinted gauntlet
    'copydrag':  'Pickup',       # loot bag
    'closed':    'Pickup',
    'open':      'Pickup',
}

def main(png_dir, cape_dir):
    os.makedirs(cape_dir, exist_ok=True)
    for slot, src in MAPPING.items():
        im = Image.open(os.path.join(png_dir, src + '.png'))
        im.save(os.path.join(cape_dir, slot + '.png'))
        im.resize((im.width * 2, im.height * 2), Image.LANCZOS).save(
            os.path.join(cape_dir, slot + '@2x.png'))
    with open(os.path.join(cape_dir, 'hotspots.json'), 'w') as f:
        json.dump({slot: {'x': 0, 'y': 0} for slot in MAPPING}, f)
    print('built', cape_dir, 'with', len(MAPPING), 'slots')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
