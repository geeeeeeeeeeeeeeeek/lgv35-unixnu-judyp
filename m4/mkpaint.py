"""
Paint the LG splash framebuffer white, then hang.

Purpose: decide whether the LG ABL jumps into our payload at all.
- Screen turns white          -> ABL jumped; the fault is inside UEFI/BootShim.
- Screen stays on the LG logo -> ABL rejected or never jumped; the fault is in the container.

Framebuffer: cont_splash_region@9d400000, size 0x2400000 (from judyp.dtb).
"""
import gzip, struct, sys, hashlib

PAGE = 4096
FB_BASE = 0x9D400000
FB_WORDS = 0x2400000 // 4          # fill the whole reserved splash region


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
        struct.pack_into("<I", k, off, 0xD503201F)   # nop

    code = [
        movz(1, FB_BASE >> 16),            # x1 = 0x9D400000
        movz(2, FB_WORDS >> 16),           # x2 = pixel word count
        0x12800003,                        # movn w3, #0  -> 0xFFFFFFFF (white)
        0xB8004423,                        # str w3, [x1], #4
        0xF1000442,                        # subs x2, x2, #1
        0xB5FFFFC2,                        # cbnz x2, -8
        0x14000000,                        # b .
    ]
    for i, insn in enumerate(code):
        struct.pack_into("<I", k, 0x100 + i * 4, insn)
    return bytes(k)


def header_v0(kernel_size, os_version, name):
    h = bytearray(1632)
    h[0:8] = b"ANDROID!"
    struct.pack_into("<I", h, 8, kernel_size)
    struct.pack_into("<I", h, 12, 0x00008000)
    struct.pack_into("<I", h, 16, 0)           # no ramdisk
    struct.pack_into("<I", h, 20, 0x01000000)
    struct.pack_into("<I", h, 24, 0)
    struct.pack_into("<I", h, 28, 0)
    struct.pack_into("<I", h, 32, 0x00000100)  # tags
    struct.pack_into("<I", h, 36, PAGE)
    struct.pack_into("<I", h, 40, 0)
    struct.pack_into("<I", h, 44, os_version)
    h[48:64] = name.encode()[:16].ljust(16, b"\0")
    return bytes(h)


def pad(data):
    return data + b"\0" * ((PAGE - len(data) % PAGE) % PAGE)


src, out = sys.argv[1], sys.argv[2]
ref = open(src, "rb").read()
os_version = struct.unpack_from("<I", ref, 44)[0]

kernel = gzip.compress(paint_kernel(), 9)
img = pad(header_v0(len(kernel), os_version, "judyp")) + pad(kernel)
img += b"\0" * (2 * 1024 * 1024 - len(img))
open(out, "wb").write(img)
print(f"out={out} kernel={len(kernel)} fb=0x{FB_BASE:X} words=0x{FB_WORDS:X} sha256={hashlib.sha256(img).hexdigest()}")
