#!/usr/bin/env bash
# Pack a UniXNU UEFI firmware (SILICIUM_UEFI.fd) into a flashable judyp boot image.
#
# The Android boot image's `kernel` is not a kernel here: it is
#   ARM64 Image header + 0x80000 zero pad + BootShim + UEFI FD
# and Android's bootloader jumps to it exactly like a Linux kernel.  BootShim
# (from Mu-Silicium) then relocates the FD to FD_BASE and enters it.  The
# original kernel_dtb / ramdisk of the stock boot image are kept untouched.
#
# Usage:
#   ./pack-boot-img.sh <stock-boot.img> <SILICIUM_UEFI.fd> <out.img> [BootShim.S]
#
# Requires: clang + llvm-objcopy (aarch64 target), magiskboot, python3.
set -euo pipefail

STOCK=${1:?stock boot_a.img}
FD=${2:?SILICIUM_UEFI.fd}
OUT=${3:?output image}
SHIM_SRC=${4:-}

FD_BASE=0x9fc00000
FD_SIZE=0x300000
TOFF=0x80000          # text_offset expected by the bootloader
TOTAL_IMG=0x4000000   # boot partition size

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- 1. BootShim: FD_BASE/FD_SIZE are baked in, and the header is required ---
if [ -z "$SHIM_SRC" ]; then
    echo "error: pass the path of Mu-Silicium/BootShim/BootShim.S" >&2
    exit 2
fi
clang --target=aarch64-none-elf -c \
      -DFD_BASE=$FD_BASE -DFD_SIZE=$FD_SIZE -DREQUIRES_KERNEL_HEADER=1 \
      "$SHIM_SRC" -o "$WORK/shim.o"
llvm-objcopy -O binary "$WORK/shim.o" "$WORK/shim.bin"
SHIM_SIZE=$(stat -c%s "$WORK/shim.bin")
echo "BootShim: $SHIM_SIZE bytes (FD_BASE=$FD_BASE FD_SIZE=$FD_SIZE)"

# --- 2. kernel = header + pad + shim + FD ------------------------------------
python3 - "$WORK/shim.bin" "$FD" "$WORK/kernel.bin" "$TOFF" <<'PY'
import struct, sys
from pathlib import Path
shim = Path(sys.argv[1]).read_bytes()
fd = Path(sys.argv[2]).read_bytes()
out = Path(sys.argv[3])
toff = int(sys.argv[4])
body = shim + fd
total = toff + len(body)
blob = bytearray(total)
struct.pack_into('<I', blob, 0, 0x14000000 | (toff // 4))  # code0: `b +0x80000`
struct.pack_into('<Q', blob, 8, toff)                      # text_offset
struct.pack_into('<Q', blob, 16, total)                    # image_size
struct.pack_into('<Q', blob, 24, 0xa)                      # flags: LE, 4K pages, no place
blob[56:60] = b'ARM\x64'                                   # magic
blob[toff:] = body
out.write_bytes(bytes(blob))
print('kernel: %d (0x%x) = pad 0x%x + shim %d + fd %d' % (total, total, toff, len(shim), len(fd)))
PY

# --- 3. swap the stock kernel, keep dtb + ramdisk, repack --------------------
mkdir -p "$WORK/unpack"
cd "$WORK/unpack"
cp "$STOCK" boot.img
magiskboot unpack boot.img >/dev/null
cp "$WORK/kernel.bin" kernel
magiskboot repack boot.img "$WORK/out.img" >/dev/null

# --- 4. pad to the full partition -------------------------------------------
python3 "$HERE/pad64.py" "$WORK/out.img" >/dev/null
cp "$WORK/out.img" "$OUT"
ls -l "$OUT"
echo "flash: fastboot flash boot_a <img> && fastboot set_active a"
