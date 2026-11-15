#!/usr/bin/env python3
"""Dump the firmware volume(s) out of a judyp boot image's kernel section, so two builds can be compared."""
import gzip
import struct
import sys
from pathlib import Path

SHIM = 0x3000
FD_BASE = 0x9FC00000


def kernel_section(image: bytes) -> bytes:
    page = struct.unpack_from('<I', image, 36)[0]
    kernel = struct.unpack_from('<I', image, 8)[0]
    ramdisk = struct.unpack_from('<I', image, 16)[0]
    start = page
    end = start + kernel
    return image[start:end]


def main() -> int:
    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    sec = kernel_section(src.read_bytes())
    raw = gzip.decompress(sec)
    print(f'{src.name}: kernel section {len(sec)} -> {len(raw)} raw')
    # Layout: ARM64 image header, pad to 0x80000, shim, firmware volume.
    fd = raw[0x80000 + SHIM:]
    out.write_bytes(fd)
    print(f'fd  {len(fd)} bytes -> {out}')
    # Enumerate FFS files of every FV found by scanning for the _FVH signature.
    pos = 0
    while True:
        pos = fd.find(b'_FVH', pos)
        if pos < 0:
            break
        base = pos - 40
        fv_len = struct.unpack_from('<Q', fd, base + 32)[0]
        hdr_len = struct.unpack_from('<H', fd, base + 48)[0]
        print(f'  FV at {base:#x} len {fv_len:#x} hdr {hdr_len:#x}')
        off = base + hdr_len
        count = 0
        while off + 24 <= base + fv_len:
            guid = fd[off:off + 16]
            if guid == b'\xff' * 16 or guid == b'\x00' * 16:
                break
            ftype = fd[off + 18]
            attr = fd[off + 19]
            size = struct.unpack_from('<I', fd, off + 20)[0] & 0xFFFFFF
            if attr & 1:
                size = struct.unpack_from('<Q', fd, off + 24 + 16)[0] if False else size
            if size < 24:
                break
            count += 1
            name = ''.join(f'{b:02x}' for b in guid[:4])
            print(f'    file {count:3d} @ {off - base:#08x} type {ftype:#04x} size {size:#08x} guid {name}')
            off += (size + 7) & ~7
        print(f'  -> {count} files')
        pos = base + max(fv_len, 1)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
