"""Parse the known-good M1 image (boot-e40-simplefb.img) and show its layout."""
import struct
import zlib
import gzip
import hashlib
import sys

path = sys.argv[1]
d = open(path, 'rb').read()
print('file', path, len(d), 'magic', d[:8])
ks, ka, rs, ra, ss, sa, tags, page = struct.unpack_from('<8I', d, 8)
hdr_ver = struct.unpack_from('<I', d, 40)[0]
print(f'kernel_size={ks} kernel_addr={hex(ka)} ramdisk_size={rs} ramdisk_addr={hex(ra)} '
      f'second={ss} tags={hex(tags)} page={page} hdr_ver={hdr_ver} os_ver={struct.unpack_from("<I", d, 44)[0]}')
print('name', d[48:64], 'cmdline', d[64:576].split(b'\0')[0])
print('id', d[576:608].hex())
print('extra_cmdline', d[608:1632].split(b'\0')[0])

off = page
seg = d[off:off + ks]
print('kernel seg head', seg[:4].hex(), 'tail', seg[-16:].hex())
try:
    raw = gzip.decompress(seg)
    print('gzip kernel raw', len(raw))
except Exception as exc:
    print('not plain gzip:', exc)
    z = zlib.decompressobj(31)
    raw = z.decompress(seg)
    print('raw', len(raw), 'unused', len(z.unused_data), 'unused head', z.unused_data[:4].hex())

print('raw arm64 header: code0', hex(struct.unpack_from('<I', raw, 0)[0]),
      'text_offset', hex(struct.unpack_from('<Q', raw, 8)[0]),
      'image_size', hex(struct.unpack_from('<Q', raw, 16)[0]),
      'flags', hex(struct.unpack_from('<Q', raw, 24)[0]),
      'magic', raw[56:60])
shim = raw[0x80000:0x80000 + 192]
print('shim head', shim[:32].hex())
print('shim bytes@8', hex(struct.unpack_from('<Q', shim, 8)[0]), '@16', hex(struct.unpack_from('<Q', shim, 16)[0]))
fd = raw[0x80000 + 192:]
print('fd len', len(fd), 'head', fd[:16])
print('first 4 bytes of raw after header tail', raw[-8:].hex())
print('sha1(kernel.ramdisk.second.recovery_dtbo) =',
      hashlib.sha1(d[page:page + ks] + d[page + ks:page + ks + rs] + d[page + ks + rs:page + ks + rs + ss]).hexdigest())
