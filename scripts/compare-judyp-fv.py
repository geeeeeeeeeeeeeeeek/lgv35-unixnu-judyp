#!/usr/bin/env python3
"""Compare the firmware volumes of two judyp boot images module by module.

Uses the same shell shape repack-judyp-boot.py writes: kernel segment = gzip(ARM64 header +
0x80000 zeros + shim(192) + FD), so the FD starts at 0x80000+192 of the inflated segment.
"""
import struct
import sys
import zlib
from pathlib import Path

HEADER = 0x80000
SHIM = 192


def firmware_volume(image: bytes) -> bytes:
    _, _, _, _, _, _, _, page = struct.unpack_from('<8I', image, 8)
    kernel = struct.unpack_from('<I', image, 8)[0]
    raw = zlib.decompressobj(31).decompress(image[page:page + kernel])
    return raw[HEADER + SHIM:]


def files(fd: bytes):
    pos = 0
    out = []
    while True:
        pos = fd.find(b'_FVH', pos)
        if pos < 0:
            return out
        base = pos - 40
        fv_len = struct.unpack_from('<Q', fd, base + 32)[0]
        hdr_len = struct.unpack_from('<H', fd, base + 48)[0]
        print(f'FV @{base:#x} length {fv_len:#x} header {hdr_len:#x}')
        off = base + hdr_len
        while off + 24 <= base + fv_len:
            guid = fd[off:off + 16]
            if guid in (b'\xff' * 16, b'\x00' * 16):
                break
            ftype = fd[off + 18]
            attr = fd[off + 19]
            size = struct.unpack_from('<I', fd, off + 20)[0] & 0xFFFFFF
            if size < 24:
                break
            out.append((guid.hex(), ftype, size))
            off += (size + 7) & ~7
        pos = base + max(fv_len, 1)


def main() -> int:
    a, b = (firmware_volume(Path(p).read_bytes()) for p in sys.argv[1:3])
    fa, fb = files(a), files(b)
    print(f'{sys.argv[1]}: {len(fa)} files, {len(a)} bytes')
    print(f'{sys.argv[2]}: {len(fb)} files, {len(b)} bytes')
    ga = {g for g, _, _ in fa}
    gb = {g for g, _, _ in fb}
    print(f'only in first: {len(ga - gb)}')
    for g, t, s in fa:
        if g not in gb:
            print(f'  {g} type {t:#04x} size {s:#x}')
    print(f'only in second: {len(gb - ga)}')
    for g, t, s in fb:
        if g not in ga:
            print(f'  {g} type {t:#04x} size {s:#x}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
