"""Build boot.img exactly like A1: header v0, no ramdisk, gzip(BootShim+FD) + DTB, padded to 64 MiB."""
import struct, sys, gzip

shim_path, fd_path, dtb_path, out = sys.argv[1:5]
shim = open(shim_path, 'rb').read()
fd = open(fd_path, 'rb').read()
dtb = open(dtb_path, 'rb').read()

raw = shim + fd
# BootShim's own ARM64 header must describe the real payload size.
raw = bytearray(raw)
struct.pack_into('<Q', raw, 16, len(raw))
raw = bytes(raw)

kernel = gzip.compress(raw, 6) + dtb
dtb_ok = dtb[:4] == b'\xd0\x0d\xfe\xed'

PAGE = 4096
hdr = bytearray(PAGE)
hdr[0:8] = b'ANDROID!'
struct.pack_into('<I', hdr, 8, len(kernel))   # kernel_size
struct.pack_into('<I', hdr, 12, 0x8000)       # kernel_addr
struct.pack_into('<I', hdr, 16, 0)            # ramdisk_size
struct.pack_into('<I', hdr, 20, 0)            # ramdisk_addr
struct.pack_into('<I', hdr, 24, 0)            # second_size
struct.pack_into('<I', hdr, 28, 0)            # second_addr
struct.pack_into('<I', hdr, 32, 0)            # tags_addr
struct.pack_into('<I', hdr, 36, PAGE)         # page_size
struct.pack_into('<I', hdr, 40, 0)            # header_version
struct.pack_into('<I', hdr, 44, 0)            # os_version
hdr[48:64] = b'judyp\0' + b'\0' * 10
hdr[64:64 + 12] = b'console=ttyMSM0\0'

buf = bytes(hdr) + kernel
buf += b'\0' * ((-len(buf)) % PAGE)
buf += b'\0' * (67108864 - len(buf))
open(out, 'wb').write(buf)
print('shim=%d fd=%d dtb=%d dtb_magic=%s kernel=%d total=%d -> %s'
      % (len(shim), len(fd), len(dtb), dtb_ok, len(kernel), len(buf), out))
