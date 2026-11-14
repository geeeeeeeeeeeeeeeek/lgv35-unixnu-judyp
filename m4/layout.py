import struct, zlib, sys

p = sys.argv[1]
d = open(p, 'rb').read()
ks, ka, rs, ra = struct.unpack_from('<4I', d, 8)
page = struct.unpack_from('<I', d, 36)[0]
seg = d[page:page + ks]
z = zlib.decompressobj(31)
raw = z.decompress(seg) + z.flush()
trail = z.unused_data
print(f'{p}: raw={len(raw)} trail={len(trail)}')
print(f'  trail head={trail[:16].hex()}')
# DTB magics inside the decompressed image
pos = [i for i in range(0, len(raw) - 4, 4) if raw[i:i + 4] == b'\xd0\x0d\xfe\xed']
print(f'  DTB magic positions in raw: {pos[:6]} count={len(pos)}')
print(f'  raw tail 16 = {raw[-16:].hex()}')
