#!/usr/bin/env python3
"""Pad a boot image to the full 64 MiB boot partition (judyp's boot_a/b size)."""
import sys
from pathlib import Path

TOTAL = 0x4000000
p = Path(sys.argv[1])
b = p.read_bytes()
print('before %d' % len(b))
if len(b) > TOTAL:
    raise SystemExit('too large: %d' % len(b))
p.write_bytes(b + b'\x00' * (TOTAL - len(b)))
print('after  %d' % p.stat().st_size)
