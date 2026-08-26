"""Extract encrypted files from an MPQ using mpyq's tables + filename-derived keys."""
import os, struct, sys, zlib
from mpyq import MPQArchive, MPQFileHeader

MPQ_FILE_ENCRYPTED   = 0x00010000
MPQ_FILE_FIX_KEY     = 0x00020000
MPQ_FILE_SINGLE_UNIT = 0x01000000
MPQ_FILE_EXISTS      = 0x80000000
MPQ_FILE_COMPRESS    = 0x00000200

class Archive(MPQArchive):
    def __init__(self, path):
        # skip listfile parsing (it's what blows up on encrypted archives)
        self.file = open(path, 'rb')
        self.header = self.read_header()
        self.hash_table = self.read_table('hash')
        self.block_table = self.read_table('block')
        self.files = None

    def _key(self, filename, flags, block):
        key = self._hash(os.path.basename(filename).replace('/', '\\'), 'TABLE')
        if flags & MPQ_FILE_FIX_KEY:
            key = (key + block.offset) ^ block.size
        return key & 0xFFFFFFFF

    def read_encrypted(self, filename):
        hash_entry = self.get_hash_table_entry(filename)
        if hash_entry is None:
            return None
        block = self.block_table[hash_entry.block_table_index]
        if not block.flags & MPQ_FILE_EXISTS or block.archived_size == 0:
            return None
        offset = block.offset + self.header['offset']
        self.file.seek(offset)
        raw = self.file.read(block.archived_size)
        key = self._key(filename, block.flags, block)

        sector_size = 512 << self.header['sector_size_shift']
        if not (block.flags & (MPQ_FILE_COMPRESS | MPQ_FILE_ENCRYPTED)):
            return raw  # stored: no sector table, no transforms
        if block.flags & MPQ_FILE_SINGLE_UNIT:
            sectors = [raw]
            positions = None
        else:
            n = (block.size + sector_size - 1) // sector_size
            pos_data = raw[: (n + 1) * 4]
            if block.flags & MPQ_FILE_ENCRYPTED:
                pos_data = decrypt_block(pos_data, (key - 1) & 0xFFFFFFFF)
            positions = struct.unpack('<%dI' % (n + 1), pos_data)
            sectors = [raw[positions[i]:positions[i+1]] for i in range(n)]

        out = b''
        for i, sec in enumerate(sectors):
            if block.flags & MPQ_FILE_ENCRYPTED:
                sec = decrypt_block(sec, (key + i) & 0xFFFFFFFF)
            remaining = block.size - len(out)
            if block.flags & MPQ_FILE_COMPRESS and len(sec) < min(sector_size, remaining):
                comp = sec[0]
                if comp == 0x02:
                    sec = zlib.decompress(sec[1:])
                elif comp == 0x08:
                    from mpyq import MPQArchive as _A  # pkware via mpyq's decompress
                    sec = self.decompress(bytes([8]) + sec[1:])
                else:
                    sec = self.decompress(sec)
            out += sec
        return out

# --- standalone MPQ crypto (same algorithm mpyq uses) ---
crypt_table = {}
def build_crypt_table():
    seed = 0x00100001
    for i in range(256):
        idx = i
        for j in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            t1 = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            t2 = seed & 0xFFFF
            crypt_table[idx] = t1 | t2
            idx += 0x100
build_crypt_table()

def decrypt_block(data, key):
    seed = 0xEEEEEEEE
    out = bytearray()
    for i in range(len(data) // 4):
        seed = (seed + crypt_table[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        v, = struct.unpack('<I', data[i*4:i*4+4])
        v = (v ^ (key + seed)) & 0xFFFFFFFF
        key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (v + seed + (seed << 5) + 3) & 0xFFFFFFFF
        out += struct.pack('<I', v)
    out += data[len(data) // 4 * 4:]
    return bytes(out)

if __name__ == '__main__':
    # usage: mpqx.py <archive.mpq> <outdir> — extracts every file in the listfile
    a = Archive(sys.argv[1])
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    listfile = a.read_encrypted('(listfile)')
    if not listfile:
        sys.exit('archive has no (listfile); cannot enumerate contents')
    n = 0
    for fn in listfile.decode().split():
        data = a.read_encrypted(fn)
        if data is None:
            print('missing:', fn)
            continue
        open(os.path.join(outdir, fn.split('\\')[-1]), 'wb').write(data)
        n += 1
    print('extracted', n, 'files from', sys.argv[1])
