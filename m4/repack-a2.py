"""
Put the UniXNU payload into the stock v1 container (stock ramdisk + cmdline),
pad to 64 MiB.

stock:   header(v1) + gzip(LG kernel) + DTB(1.24M) + ramdisk(16.6M)
ours:    header(v1) + gzip(BootShim+FD) + DTB(judyp 554K) + stock ramdisk
"""
import struct, sys

src_stock, src_a1, out = sys.argv[1], sys.argv[2], sys.argv[3]

st = open(src_stock, 'rb').read()
a1 = open(src_a1, 'rb').read()

page = struct.unpack_from('<I', st, 36)[0]
s_ks, s_ka, s_rs, s_ra = struct.unpack_from('<4I', st, 8)
a_ks = struct.unpack_from('<I', a1, 8)[0]

new_kernel = a1[page:page + a_ks]
ramdisk = st[page + s_ks:page + s_ks + s_rs]

img = bytearray(st[:page])
struct.pack_into('<I', img, 8, len(new_kernel))
img += new_kernel + ramdisk
pad = (-len(img)) % page
img += b'\0' * pad
img += b'\0' * (67108864 - len(img))
open(out, 'wb').write(img)

print(f'out={out}')
print(f'  size={len(img)} kernel={len(new_kernel)} ramdisk={len(ramdisk)}')
print(f'  header_ver={struct.unpack_from("<I", img, 40)[0]} page={page}')
