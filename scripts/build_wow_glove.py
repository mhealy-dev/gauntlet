"""Build gloves/wow from decoded retail cursor PNGs.

usage: build_wow_cape.py <png_dir> <glove_dir>
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

def save_pair(im, directory, slot):
    im.save(os.path.join(directory, slot + '.png'))
    im.resize((im.width * 2, im.height * 2), Image.LANCZOS).save(
        os.path.join(directory, slot + '@2x.png'))

def main(png_dir, glove_dir):
    # contextual glove: gauntlet pointer, but system cursors keep their meaning
    os.makedirs(glove_dir, exist_ok=True)
    for slot, src in MAPPING.items():
        save_pair(Image.open(os.path.join(png_dir, src + '.png')), glove_dir, slot)
    with open(os.path.join(glove_dir, 'hotspots.json'), 'w') as f:
        json.dump({slot: {'x': 0, 'y': 0} for slot in MAPPING}, f)
    print('built', glove_dir, 'with', len(MAPPING), 'slots')

    # solid glove: one gauntlet for everything, via default.png
    solid_dir = glove_dir + '-solid'
    os.makedirs(solid_dir, exist_ok=True)
    save_pair(Image.open(os.path.join(png_dir, 'Point.png')), solid_dir, 'default')
    with open(os.path.join(solid_dir, 'hotspots.json'), 'w') as f:
        json.dump({'default': {'x': 0, 'y': 0}}, f)
    print('built', solid_dir, '(single pointer; see its skip file)')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
