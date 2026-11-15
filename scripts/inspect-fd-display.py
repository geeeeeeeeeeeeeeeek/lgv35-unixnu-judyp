"""Which display driver is inside a firmware volume? EDK II writes each FFS file's UI section as
UTF-16LE, so the module names are searchable in the raw image."""
import gzip
import struct
import sys
import zlib
from pathlib import Path

NAMES = ['SimpleFbDxe', 'DisplayDxe', 'DisplayReEnablerDxe', 'CPRDxe', 'JudypBootMemoryDxe',
         'JudypUniXNULoader', 'SiliciumPkg', 'DxeCore']


def report(label, fd):
    hits = [n for n in NAMES if n.encode('utf-16-le') in fd]
    print(f'{label}: {len(fd)} bytes, ui names found: {hits or "none"}')


ci = Path(sys.argv[1]).read_bytes()
report('ci fd', ci)

shell = Path(sys.argv[2]).read_bytes()
page = struct.unpack_from('<I', shell, 36)[0]
ks = struct.unpack_from('<I', shell, 8)[0]
seg = shell[page:page + ks]
z = zlib.decompressobj(31)
raw = z.decompress(seg)
fd = raw[0x80000 + 192:]
report('e40 fd', fd)

d = 0
for i in range(min(len(ci), len(fd))):
    d += ci[i] != fd[i]
print('differing bytes in the first', min(len(ci), len(fd)), 'bytes:', d)
print('ci fd head', ci[:16].hex(), 'e40 fd head', fd[:16].hex())
