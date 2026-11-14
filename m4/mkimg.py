"""
Build a boot image v0 from an explicit kernel/ramdisk pair (LG V35 judyp, 64 MiB partition).

Purpose: isolate why ABL refuses the A1 image while it accepts the LOS image.
The only differences to be tested are ramdisk, cmdline and os_version.
"""
import struct, sys, hashlib

PAGE = 4096
BOOT_MAGIC = b"ANDROID!"

def read(path):
    with open(path, "rb") as f:
        return f.read()

def header_v0(kernel_size, ramdisk_size, os_version, name, cmdline):
    h = bytearray(1632)
    h[0:8] = BOOT_MAGIC
    struct.pack_into("<I", h, 8, kernel_size)
    struct.pack_into("<I", h, 12, 0x00008000)      # kernel_addr
    struct.pack_into("<I", h, 16, ramdisk_size)
    struct.pack_into("<I", h, 20, 0x01000000)      # ramdisk_addr
    struct.pack_into("<I", h, 24, 0)               # second_size
    struct.pack_into("<I", h, 28, 0)               # second_addr
    struct.pack_into("<I", h, 32, 0x00000100)      # tags_addr
    struct.pack_into("<I", h, 36, PAGE)
    struct.pack_into("<I", h, 40, 0)               # header_version
    struct.pack_into("<I", h, 44, os_version)
    h[48:64] = name.encode()[:16].ljust(16, b"\0")
    h[64:64 + 512] = cmdline.encode()[:511].ljust(512, b"\0")
    return bytes(h)

def pad(data, size=PAGE):
    return data + b"\0" * ((size - len(data) % size) % size)

def main(kernel_src, ramdisk_src, out, size_mb=64):
    ks = read(kernel_src)
    kernel_size = struct.unpack_from("<I", ks, 8)[0]
    kernel = ks[PAGE:PAGE + kernel_size]

    rs = read(ramdisk_src)
    rk = struct.unpack_from("<I", rs, 8)[0]
    ramdisk_size = struct.unpack_from("<I", rs, 16)[0]
    os_version = struct.unpack_from("<I", rs, 44)[0]
    cmdline = rs[64:64 + 512].split(b"\0")[0].decode()
    ramdisk_start = (1 + (rk + PAGE - 1) // PAGE) * PAGE
    ramdisk = rs[ramdisk_start:ramdisk_start + ramdisk_size]

    img = pad(header_v0(len(kernel), len(ramdisk), os_version, "judyp", cmdline))
    img += pad(kernel)
    img += pad(ramdisk)
    total = size_mb * 1024 * 1024
    if len(img) > total:
        sys.exit("image larger than partition")
    img += b"\0" * (total - len(img))

    with open(out, "wb") as f:
        f.write(img)
    print(f"out={out} size={len(img)} kernel={len(kernel)} ramdisk={len(ramdisk)}")
    print(f"sha256={hashlib.sha256(img).hexdigest()}")
    print(f"cmdline={cmdline}")

if __name__ == "__main__":
    main(*sys.argv[1:])
