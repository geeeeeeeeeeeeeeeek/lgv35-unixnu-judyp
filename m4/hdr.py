"""Print the decompressed ARM64 Image header of a boot image kernel."""
import struct, sys, zlib

for path in sys.argv[1:]:
    b = open(path, "rb").read()
    page = struct.unpack_from("<I", b, 36)[0]
    ksize = struct.unpack_from("<I", b, 8)[0]
    blob = b[page:page + ksize]
    if blob[:2] == b"\x1f\x8b":
        raw = zlib.decompressobj(31).decompress(blob)
    else:
        raw = blob
    text_offset, image_size, flags = struct.unpack_from("<QQQ", raw, 8)
    magic = raw[56:60]
    code0 = struct.unpack_from("<I", raw, 0)[0]
    print(f"{path}")
    print(f"  code0=0x{code0:08x} text_offset=0x{text_offset:x} image_size=0x{image_size:x} flags=0x{flags:x} magic={magic}")
    print(f"  raw_len=0x{len(raw):x} (decompressed)")
