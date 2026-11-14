"""
Same control container as boot-ctl-loop.img, but the decompressed image is
padded to exactly the stock size with zeros (entry = infinite loop).

Only variable vs stock: first instruction + zero padding.
If this hangs -> ABL rejects small payloads; if it returns to fastboot ->
something else is going on.
"""
import struct, sys, zlib, gzip

src, out = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
page = struct.unpack_from('<I', d, 36)[0]
ks, ka, rs, ra = struct.unpack_from('<4I', d, 8)

z = zlib.decompressobj(31)
raw = z.decompress(d[page:page + ks]) + z.flush()
trailing = z.unused_data
ramdisk = d[page + ks:page + ks + rs]

stock_img_size = struct.unpack_from('<Q', raw, 16)[0]
big = bytearray(len(raw))
big[0:4] = struct.pack('<I', 0x14000000)          # b .
struct.pack_into('<Q', big, 16, stock_img_size)   # keep image_size semantics

new_kernel = gzip.compress(bytes(big), 6) + trailing
img = bytearray(d[:page])
struct.pack_into('<I', img, 8, len(new_kernel))
img += new_kernel + ramdisk
img += b'\0' * ((-len(img)) % page)
img += b'\0' * (67108864 - len(img))
open(out, 'wb').write(img)
print(f'raw={len(raw)} image_size={hex(stock_img_size)} gz={len(new_kernel)} out={len(img)}')
