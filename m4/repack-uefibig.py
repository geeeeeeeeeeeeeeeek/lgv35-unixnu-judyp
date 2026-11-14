"""
UEFI payload in the official LG container, padded to the official dimensions.

decompressed  = [patched ARM64 header][BootShim + FD][zero pad to 0x2e3c000]
gzip payload  = gzip(decompressed)
kernel        = gzip payload + judyp.dtb        (same layout as stock: image + dtb)
rest          = stock v1 header, stock ramdisk, pad to 64 MiB

Header fields are copied from the stock image (text_offset 0x80000,
image_size 0x2e3c000, flags 0xA, "ARM\\x64"), because BootShim itself is
position independent (uses adr) and never reads these fields at runtime.
"""
import struct, sys, zlib, gzip

stock_path, a1_path, dtb_path, out = sys.argv[1:5]

st = open(stock_path, 'rb').read()
a1 = open(a1_path, 'rb').read()
dtb = open(dtb_path, 'rb').read()

page = struct.unpack_from('<I', st, 36)[0]
s_ks, s_ka, s_rs, s_ra = struct.unpack_from('<4I', st, 8)

z = zlib.decompressobj(31)
s_raw = z.decompress(st[page:page + s_ks]) + z.flush()
stock_image_size = struct.unpack_from('<Q', s_raw, 16)[0]
stock_text_off = struct.unpack_from('<Q', s_raw, 8)[0]
print(f'stock: raw={len(s_raw)} text_offset={hex(stock_text_off)} image_size={hex(stock_image_size)}')

a_ks = struct.unpack_from('<I', a1, 8)[0]
kernel_seg = a1[page:page + a_ks]
zk = zlib.decompressobj(31)
payload = zk.decompress(kernel_seg) + zk.flush()          # BootShim + FD
print(f'payload(BootShim+FD)={len(payload)}')

img = bytearray(payload)
if len(img) > stock_image_size:
    sys.exit('payload larger than slot')
img += b'\0' * (stock_image_size - len(img))

struct.pack_into('<Q', img, 8, stock_text_off)
struct.pack_into('<Q', img, 16, stock_image_size)
struct.pack_into('<Q', img, 24, 0xA)
struct.pack_into('<Q', img, 48, 0)
img[56:60] = b'ARM\x64'
struct.pack_into('<I', img, 60, 0)

new_kernel = gzip.compress(bytes(img), 6) + dtb
hdr = bytearray(st[:page])
struct.pack_into('<I', hdr, 8, len(new_kernel))
ramdisk = st[page + s_ks:page + s_ks + s_rs]

outbuf = hdr + new_kernel + ramdisk
outbuf += b'\0' * ((-len(outbuf)) % page)
outbuf += b'\0' * (67108864 - len(outbuf))
open(out, 'wb').write(outbuf)
print(f'out={out} size={len(outbuf)} kernel={len(new_kernel)} dtb={len(dtb)}')
