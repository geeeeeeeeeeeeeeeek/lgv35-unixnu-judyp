"""
Build a boot image whose kernel is an infinite loop with a valid ARM64 Image header.

Purpose: decide whether the LG ABL jumps into our kernel at all.
- If it jumps: the phone hangs (no fastboot for as long as it runs) -> UEFI/BootShim problem.
- If it rejects: the phone returns to fastboot within a second, like the A1 image.
"""
import gzip, struct, sys, hashlib

PAGE = 4096

def loop_kernel():
    k = bytearray(PAGE)
    struct.pack_into("<I", k, 0, 0x14000040)   # b .+0x100 (over the header, into code)
    struct.pack_into("<Q", k, 8, 0x80000)      # text_offset
    struct.pack_into("<Q", k, 16, PAGE)        # image_size
    struct.pack_into("<Q", k, 24, 0xA)         # flags: 4K pages, little endian
    struct.pack_into("<Q", k, 48, 0)
    k[56:60] = b"ARM\x64"
    struct.pack_into("<I", k, 60, 0)
    for off in range(0x40, 0x100, 4):          # NOPs between header and entry
        struct.pack_into("<I", k, off, 0xD503201F)
    struct.pack_into("<I", k, 0x100, 0x14000000)  # entry: b .
    return bytes(k)

def header_v0(kernel_size, ramdisk_size, os_version, name):
    h = bytearray(1632)
    h[0:8] = b"ANDROID!"
    struct.pack_into("<I", h, 8, kernel_size)
    struct.pack_into("<I", h, 12, 0x00008000)
    struct.pack_into("<I", h, 16, ramdisk_size)
    struct.pack_into("<I", h, 20, 0x01000000)
    struct.pack_into("<I", h, 24, 0)
    struct.pack_into("<I", h, 28, 0)
    struct.pack_into("<I", h, 32, 0x00000100)
    struct.pack_into("<I", h, 36, PAGE)
    struct.pack_into("<I", h, 40, 0)
    struct.pack_into("<I", h, 44, os_version)
    h[48:64] = name.encode()[:16].ljust(16, b"\0")
    return bytes(h)

def pad(data):
    return data + b"\0" * ((PAGE - len(data) % PAGE) % PAGE)

src = sys.argv[1]
out = sys.argv[2]
ref = open(src, "rb").read()
os_version = struct.unpack_from("<I", ref, 44)[0]

kernel = gzip.compress(loop_kernel(), 9)
img = pad(header_v0(len(kernel), 0, os_version, "judyp")) + pad(kernel)
img += b"\0" * (64 * 1024 * 1024 - len(img))
open(out, "wb").write(img)
print(f"out={out} kernel={len(kernel)} sha256={hashlib.sha256(img).hexdigest()}")
