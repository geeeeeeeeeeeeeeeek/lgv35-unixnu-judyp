"""
Stock container, kernel = pure infinite loop (no memory access at all).

If the phone stays on the logo and never returns to fastboot -> ABL jumped into our
payload, and the earlier failure was the framebuffer store faulting.
If it keeps rebooting -> the payload never ran (or a watchdog kills it).
"""
import struct, zlib, gzip, sys

PAGE = 4096


def hang_kernel():
    k = bytearray(PAGE)
    struct.pack_into("<I", k, 0, 0x14000040)   # b .+0x100
    struct.pack_into("<Q", k, 8, 0x80000)      # text_offset
    struct.pack_into("<Q", k, 16, PAGE)        # image_size
    struct.pack_into("<Q", k, 24, 0xA)
    struct.pack_into("<Q", k, 48, 0)
    k[56:60] = b"ARM\x64"
    struct.pack_into("<I", k, 60, 0)
    for off in range(0x40, 0x100, 4):
        struct.pack_into("<I", k, off, 0xD503201F)
    struct.pack_into("<I", k, 0x100, 0x14000000)   # b .
    return bytes(k)


src, out = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
ks, ka, rs, ra = struct.unpack_from('<4I', d, 8)
page = struct.unpack_from('<I', d, 36)[0]

z = zlib.decompressobj(31)
z.decompress(d[page:page + ks]); z.flush()
trailing = z.unused_data
ramdisk = d[page + ks:page + ks + rs]

new_kernel = gzip.compress(hang_kernel(), 9) + trailing
img = bytearray(d[:page])
struct.pack_into('<I', img, 8, len(new_kernel))
img += new_kernel + ramdisk
img += b'\0' * ((-len(img)) % page)
open(out, 'wb').write(img)
print(f'out={out} size={len(img)} kernel={len(new_kernel)}')
