#!/usr/bin/env python3
"""Decompress the inner FVMAIN of a judyp firmware volume and report its size."""
import lzma
import struct
import sys
import zlib
from pathlib import Path

HEADER = 0x80000
SHIM = 192
GUIDED = bytes.fromhex('98584eee14396e44c15894b7d403c77b'[:0]) or b''


def firmware_volume(image: bytes) -> bytes:
    _, _, _, _, _, _, _, page = struct.unpack_from('<8I', image, 8)
    kernel = struct.unpack_from('<I', image, 8)[0]
    raw = zlib.decompressobj(31).decompress(image[page:page + kernel])
    return raw[HEADER + SHIM:]


def main() -> int:
    for path in sys.argv[1:]:
        fd = firmware_volume(Path(path).read_bytes())
        # FVMAIN sits inside a GUIDED/LZMA section; look for the 5-byte LZMA props + 8-byte size
        # signature used by LzmaCustomDecompressLib (0x5D, dict 16 MB, then the original length).
        best = None
        for off in range(0, len(fd) - 13, 4):
            if fd[off] != 0x5D:
                continue
            size = struct.unpack_from('<Q', fd, off + 5)[0]
            if 0x100000 < size < 0x1000000:
                try:
                    out = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(
                        fd[off:], max_length=size)
                except lzma.LZMAError:
                    continue
                if len(out) == size:
                    best = (off, size, out)
                    break
        if not best:
            print(f'{path}: no LZMA FVMAIN found')
            continue
        off, size, out = best
        files = out.count(b'_FVH')
        print(f'{path}: fd {len(fd)} B, FVMAIN at {off:#x}, {size} B decompressed, {files} FV header(s)')
        # Count FFS files in the decompressed volume.
        base = out.find(b'_FVH') - 40
        if base < 0:
            continue
        fv_len = struct.unpack_from('<Q', out, base + 32)[0]
        hdr = struct.unpack_from('<H', out, base + 48)[0]
        pos, count = base + hdr, 0
        total = 0
        while pos + 24 <= base + fv_len:
            guid = out[pos:pos + 16]
            if guid in (b'\xff' * 16, b'\x00' * 16):
                break
            size_f = struct.unpack_from('<I', out, pos + 20)[0] & 0xFFFFFF
            if size_f < 24:
                break
            count += 1
            total += size_f
            pos += (size_f + 7) & ~7
        print(f'  inner FV {fv_len:#x} B, {count} FFS files, {total:#x} B of files')
        Path(path + '.fvmain.bin').write_bytes(out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
