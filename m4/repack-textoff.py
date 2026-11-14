"""A1 payload with text_offset patched to the stock value (0x80000)."""
import struct, sys, zlib, gzip

stock_path, a1_path, dtb_path, out = sys.argv[1:5]
st = open(stock_path, 'rb').read()
a1 = open(a1_path, 'rb').read()
dtb = open(dtb_path, 'rb').read()

page = struct.unpack_from('<I', st, 36)[0]
s_ks, s_rs = struct.unpack_from('<I', st, 8)[0], struct.unpack_from('<I', st, 24)[0]

z = zlib.decompressobj(31)
stock_text = struct.unpack_from('<Q', z.decompress(st[page:page + s_ks]) + z.flush(), 8)[0]
print('stock text_offset=%#x' % stock_text)

a_ks = struct.unpack_from('<I', a1, 8)[0]
zk = zlib.decompressobj(31)
payload = bytearray(zk.decompress(a1[page:page + a_ks]) + zk.flush())
print('a1 text_offset=%#x image_size=%#x' % (struct.unpack_from('<Q', payload, 8)[0], struct.unpack_from('<Q', payload, 16)[0]))

struct.pack_into('<Q', payload, 8, stock_text)

kernel = gzip.compress(bytes(payload), 6) + dtb
buf = bytearray(st[:page])
struct.pack_into('<I', buf, 8, len(kernel))
ramdisk = st[page + s_ks:page + s_ks + s_rs]

o = bytes(buf) + kernel + ramdisk
o += b'\0' * ((-len(o)) % page)
o += b'\0' * (67108864 - len(o))
open(out, 'wb').write(o)
print('out=%s total=%d kernel=%d' % (out, len(o), len(kernel)))
