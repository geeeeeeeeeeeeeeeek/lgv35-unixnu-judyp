#!/usr/bin/env python3
"""Wrap a firmware volume in the boot image shape this phone's ABL accepts.

`unixnu bootimg` writes the standard Mu-Silicium shape -- header v0, the shim itself as the
kernel segment, no ramdisk -- and this ABL does not boot it (E04/E11/E13: Load Error, or a 2.3 s
reset). What does boot is E39/E40's shape, which keeps the stock image around our code:

    stock header (v1) + stock cmdline + stock ramdisk + stock DTB trailer
    kernel segment = gzip(ARM64 image header + 0x80000 zeros + shim + firmware volume)

The first instruction of the ARM64 header is a branch to +0x80000, i.e. to the shim; ABL loads the
segment at 0x80000 and jumps to its start. The shim already inside the shell is the known-good one
(FD_SIZE = 0x300000), so only the firmware volume is swapped and the shell must be an image that
booted before (m4/boot-e40-simplefb.img).

Usage: repack-judyp-boot.py SHELL.img SILICIUM_UEFI.fd OUT.img
"""
import gzip
import struct
import sys
import zlib

PAGE = 4096
HEADER = 0x80000          # the ARM64 header branch target, where the shim sits
SHIM = 192
FD_SIZE = 0x300000


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    shell_path, fd_path, out_path = sys.argv[1:4]
    shell = bytearray(open(shell_path, 'rb').read())
    fd = open(fd_path, 'rb').read()

    if bytes(shell[:8]) != b'ANDROID!':
        raise SystemExit(f'{shell_path} is not an Android boot image')
    kernel_size, _, ramdisk_size, _, second_size, _, _, page = struct.unpack_from('<8I', shell, 8)
    version = struct.unpack_from('<I', shell, 40)[0]
    if version != 1:
        raise SystemExit(f'expected the stock header v1 shell, got v{version}')
    if page != PAGE:
        raise SystemExit(f'expected {PAGE}-byte pages, got {page}')
    if len(fd) != FD_SIZE:
        raise SystemExit(f'{fd_path} is {len(fd)} bytes, the shim loads exactly {FD_SIZE}')

    segment = bytes(shell[page:page + kernel_size])
    # The gzip stream stops before the DTB, which the stock image appends to the kernel segment.
    inflater = zlib.decompressobj(31)
    raw = inflater.decompress(segment)
    dtb = inflater.unused_data
    if len(raw) != HEADER + SHIM + FD_SIZE:
        raise SystemExit(f'shell kernel is {len(raw)} bytes, expected '
                         f'{HEADER}+{SHIM}+{FD_SIZE}; is this an E39/E40 image?')
    if bytes(raw[0x8:0x10]) == b'' or struct.unpack_from('<Q', raw, 8)[0] != HEADER:
        raise SystemExit('shell kernel does not start with the ARM64 header the ABL needs')
    branch = struct.unpack_from('<I', raw, 0)[0]
    if branch != 0x14020000:
        raise SystemExit(f'unexpected branch {branch:#x} in the shell kernel header')

    new_raw = raw[:HEADER + SHIM] + fd
    new_raw = bytearray(new_raw)
    struct.pack_into('<Q', new_raw, 16, len(new_raw))     # image_size inside the ARM64 header
    new_kernel = gzip.compress(bytes(new_raw), 9) + dtb

    out = bytearray(shell[:page])
    struct.pack_into('<I', out, 8, len(new_kernel))
    out += new_kernel
    out += shell[page + kernel_size:page + kernel_size + ramdisk_size]
    if second_size:
        out += shell[page + kernel_size + ramdisk_size:
                     page + kernel_size + ramdisk_size + second_size]
    out += b'\0' * ((-len(out)) % PAGE)
    if len(out) < len(shell):
        out += b'\0' * (len(shell) - len(out))
    open(out_path, 'wb').write(out)
    print(f'shell={shell_path} fd={fd_path}')
    print(f'kernel {kernel_size} -> {len(new_kernel)} (raw {HEADER}+{SHIM}+{FD_SIZE}, dtb {len(dtb)})')
    print(f'image {len(shell)} -> {len(out)} bytes written to {out_path}')


if __name__ == '__main__':
    main()
