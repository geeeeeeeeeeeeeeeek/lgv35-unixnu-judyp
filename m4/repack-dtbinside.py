"""DTB inside the gzip (LG ABL appears to require it), everything else official."""
import struct, sys, zlib, gzip

stock_path, a1_path, dtb_path, out = sys.argv[1:5]
st = open(stock_path, 'rb').read()
a1 = open(a1_path, 'rb').read()
dtb = open(dtb_path, 'rb').read()

page = struct.unpack_from('<I', st, 36)[0]
s_ks, s_rs = struct.unpack_from('<I', st, 8)[0], struct.unpack_from('<I', st, 24)[0]

z = zlib.decompressobj(31)
s_raw = z.decompress(st[page:page + s_ks]) + z.flush()
magic = b'\xd0\x0d\xfe\xed'
print('stock raw=%d last8=%s dtb_inside_at=%d' % (len(s_raw), s_raw[-8:].hex(), s_raw.find(magic)))

a_ks = struct.unpack_from('<I', a1, 8)[0]
zk = zlib.decompressobj(31)
payload = zk.decompress(a1[page:page + a_ks]) + zk.flush()
print(f'payload={len(payload)}')

raw = payload + dtb
hdr = bytearray(raw[:64])
struct.pack_into('<Q', hdr, 16, len(raw))
raw = bytes(hdr) + raw[64:]

kernel = gzip.compress(raw, 6)
buf = bytearray(st[:page])
struct.pack_into('<I', buf, 8, len(kernel))
ramdisk = st[page + s_ks:page + s_ks + s_rs]

o = bytes(buf) + kernel + ramdisk
o += b'\0' * ((-len(o)) % page)
o += b'\0' * (67108864 - len(o))
open(out, 'wb').write(o)
print(f'out={out} total={len(o)} kernel={len(kernel)} raw={len(raw)}')
