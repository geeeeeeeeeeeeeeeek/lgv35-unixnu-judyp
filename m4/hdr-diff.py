"""Dump and diff Android boot image headers (v0/v1) for stock vs our images."""
import struct, sys, gzip, io, hashlib, os


def parse(path):
    d = open(path, 'rb').read()
    if d[:8] != b'ANDROID!':
        return {'path': path, 'error': 'no ANDROID! magic'}
    ks, ka, rs, ra, ss, sa, tags, page = struct.unpack_from('<8I', d, 8)
    osv, = struct.unpack_from('<I', d, 44)
    name = d[48:64].rstrip(b'\0').decode('ascii', 'replace')
    hi = struct.unpack_from('<I', d, 40)[0]
    info = {
        'path': os.path.basename(path), 'size': len(d),
        'kernel_size': ks, 'kernel_addr': hex(ka),
        'ramdisk_size': rs, 'ramdisk_addr': hex(ra),
        'second': ss, 'tags_addr': hex(tags), 'page': page,
        'header_version': hi, 'os_version': hex(osv), 'name': name,
        'cmdline_len': len(d[64:512].rstrip(b'\0')),
    }
    kstart = page
    kernel = d[kstart:kstart + ks]
    info['kernel_sha'] = hashlib.sha256(kernel).hexdigest()[:16]
    try:
        raw = gzip.decompress(kernel)
        info['kernel_raw'] = len(raw)
        info['text_offset'] = hex(struct.unpack_from('<Q', raw, 8)[0]) if len(raw) >= 16 else '-'
        hdr_img = struct.unpack_from('<Q', raw, 16)[0] if len(raw) >= 24 else 0
        info['hdr_image_size'] = hex(hdr_img)
        info['hdr_flags'] = hex(struct.unpack_from('<Q', raw, 24)[0]) if len(raw) >= 32 else '-'
        info['hdr_magic'] = raw[56:60].decode('ascii', 'replace') if len(raw) >= 60 else '-'
        if hdr_img and hdr_img < len(raw):
            info['trailing_after_image_size'] = len(raw) - hdr_img
    except Exception as e:
        info['kernel_raw'] = f'not gzip ({e})'
    if rs:
        info['ramdisk_sha'] = hashlib.sha256(d[kstart + ks:kstart + ks + rs]).hexdigest()[:16]
    return info


for p in sys.argv[1:]:
    i = parse(p)
    print('=' * 60)
    for k, v in i.items():
        print(f'{k:26} {v}')
