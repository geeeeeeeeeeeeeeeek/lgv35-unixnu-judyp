"""
Take the stock LG boot.img, keep everything (header v1, ramdisk, cmdline, DTB trailer)
and replace only the decompressed kernel payload with the paint code.
"""
import struct, zlib, gzip, sys

PAGE = 4096
FB_BASE = 0x9D400000
FB_WORDS = 0x2400000 // 4


def movz(rd, imm16, hw=0):
    return 0xD2800000 | (hw << 21) | (imm16 << 5) | rd


def paint_kernel():
    k = bytearray(PAGE)
    struct.pack_into("<I", k, 0, 0x14000040)   # b .+0x100
    struct.pack_into("<Q", k, 8, 0x80000)      # text_offset
    struct.pack_into("<Q", k, 16, PAGE)        # image_size
    struct.pack_into("<Q", k, 24, 0xA)         # 4K pages, little endian
    struct.pack_into("<Q", k, 48, 0)
    k[56:60] = b"ARM\x64"
    struct.pack_into("<I", k, 60, 0)
    for off in range(0x40, 0x100, 4):
        struct.pack_into("<I", k, off, 0xD503201F)
    code = [
        movz(1, FB_BASE >> 16),
        movz(2, FB_WORDS >> 16),
        0x12800003,
        0xB8004423,
        0xF1000442,
        0xB5FFFFC2,
        0x14000000,
    ]
    for i, insn in enumerate(code):
        struct.pack_into("<I", k, 0x100 + i * 4, insn)
    return bytes(k)


src, out = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()

ks, ka, rs, ra, ss, sa, tags, page = struct.unpack_from('<8I', d, 8)
seg = d[page:page + ks]
ramdisk = d[page + ks:page + ks + rs]

z = zlib.decompressobj(31)
raw = z.decompress(seg) + z.flush()
trailing = z.unused_data
print(f'stock: seg={ks} raw={len(raw)} trailing={len(trailing)} raw_head={raw[:8].hex()} ramdisk={rs} hdr_ver={struct.unpack_from("<I", d, 40)[0]}')
if len(raw) >= 64:
    print(f'stock arm64 header: text_offset={hex(struct.unpack_from("<Q", raw, 8)[0])} '
          f'image_size={hex(struct.unpack_from("<Q", raw, 16)[0])} magic={raw[56:60]}')

new_kernel = gzip.compress(paint_kernel(), 9) + trailing

out_img = bytearray(d[:page])
struct.pack_into('<I', out_img, 8, len(new_kernel))
out_img += new_kernel
out_img += ramdisk
out_img += b'\0' * ((-len(out_img)) % page)

open(out, 'wb').write(out_img)
print(f'out={out} size={len(out_img)} kernel={len(new_kernel)}')
