"""
Control: stock boot.img, stock ramdisk, stock DTB, stock kernel with
ONLY the first instruction patched to `b .` (infinite loop).

If the phone cannot boot Android -> ABL executes the decompressed kernel at
kernel_addr, and we finally have a measurable "jumped" baseline.
"""
import struct, sys, zlib, gzip

src, out = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
page = struct.unpack_from('<I', d, 36)[0]
ks, ka, rs, ra = struct.unpack_from('<4I', d, 8)

seg = d[page:page + ks]
z = zlib.decompressobj(31)
raw = z.decompress(seg) + z.flush()
trailing = z.unused_data
ramdisk = d[page + ks:page + ks + rs]

print(f'raw={len(raw)} trailing={len(trailing)} ramdisk={len(ramdisk)}')
print(f'first insn = {raw[:4].hex()}')

patched = bytearray(raw)
patched[0:4] = struct.pack('<I', 0x14000000)

new_kernel = gzip.compress(bytes(patched), 6) + trailing
img = bytearray(d[:page])
struct.pack_into('<I', img, 8, len(new_kernel))
img += new_kernel + ramdisk
img += b'\0' * ((-len(img)) % page)
img += b'\0' * (67108864 - len(img))
open(out, 'wb').write(img)
print(f'out={out} size={len(img)} kernel={len(new_kernel)}')
