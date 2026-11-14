"""Inspect the structure of the kernel segment in the stock LG boot image."""
import struct, gzip, sys

d = open(sys.argv[1], 'rb').read()
page = struct.unpack_from('<I', d, 36)[0]
ks = struct.unpack_from('<I', d, 8)[0]
k = d[page:page + ks]
print(f'kernel_size={ks} first16={k[:16].hex()}')

# locate gzip / lz4 / zstd magics inside the kernel segment
for magic, name in ((b'\x1f\x8b\x08', 'gzip'), (b'\x04\x22\x4d\x18', 'lz4'), (b'\x28\xb5\x2f\xfd', 'zstd')):
    idx = k.find(magic)
    print(f'{name} magic at {idx}')

# if there is a gzip stream, try decompressing
g = k.find(b'\x1f\x8b\x08')
if g >= 0:
    try:
        raw = gzip.decompress(k[g:])
        print(f'gzip ok: {len(raw)} bytes, leading={raw[:8].hex()}')
        print(f'  text_offset={hex(struct.unpack_from("<Q", raw, 8)[0])} image_size={hex(struct.unpack_from("<Q", raw, 16)[0])} magic={raw[56:60]}')
    except Exception as e:
        print(f'gzip fail: {e}')

# check the DTB prefix
if k[:4] == b'\xd0\x0d\xfe\xed':
    dtb_len, = struct.unpack_from('>I', k, 4)
    print(f'DTB prefix: length={dtb_len}, ends at {8 + dtb_len}')
    rest = k[8 + dtb_len:8 + dtb_len + 16]
    print(f'bytes after DTB: {rest.hex()}')
