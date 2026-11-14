#!/usr/bin/env python3
"""Patch the prebuilt judyp ButtonsDxe so the volume keys reach the UEFI console.

Why this is needed
------------------
`ButtonsDxe` (a binary blob under
`Binaries/judyp/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.efi`) reads five pins per
poll: PON power key, PM8998 GPIO6 (VOL+), PM8998 GPIO5 (VOL-), then TLMM GPIO75
(CONF0) and TLMM GPIO76 (CONF1).  Every one of those reads is followed by
`tbnz x19, #0x3f, <error>` and any failure makes `PollButtonArray` return an
error, which makes `PollButtonKeys` throw away *all* buttons and spam
`ButtonsDxe - PollButtonKeys failed status:0x...` over the framebuffer.

On this device the TLMM path dies inside `smem_alloc: ... smem_type=138` and the
PON path also fails, so nothing ever worked.  We do not need CONF0/CONF1 (they
are not wired on judyp) and we can live without the power key, so:

  * route the two TLMM reads around entirely (they never touch TLMM again),
  * NOP the five failure branches so one dead pin cannot veto the rest,
  * force the CONF0/CONF1 array slots to "released" so they never fake a key.

Result on hardware: no more error spam, VOL+ / VOL- drive the UniXNU menu.

Usage
-----
    python3 apply-buttons-patch.py [ButtonsDxe.efi] [-o ButtonsDxe.patched.efi]

`ButtonsDxe.inf` must reference the output (`PE32|ButtonsDxe.patched.efi|*`).
The script is idempotent and verifies every byte it changes.
"""

import argparse
import sys
from pathlib import Path

NOP = 0xD503201F
MOV_X19_XZR = 0xAA1F03F3

# (offset, expected original word, patched word, comment)
PATCHES = [
    # --- E42: never call ReadTlmmGpioStatus (CONF0 / CONF1) ---------------
    (0x4934, 0x97FFFFB7, MOV_X19_XZR, "CONF0: bl ReadTlmmGpioStatus -> success"),
    (0x4954, 0x97FFFFAF, MOV_X19_XZR, "CONF1: bl ReadTlmmGpioStatus -> success"),
    # --- E43: a single dead pin must not discard every key ----------------
    (0x48DC, 0xB7F80493, NOP, "PON   failure branch -> fall through"),
    (0x48FC, 0xB7F803F3, NOP, "VOL+  failure branch -> fall through"),
    (0x491C, 0xB7F80353, NOP, "VOL-  failure branch -> fall through"),
    (0x493C, 0xB7F802B3, NOP, "CONF0 failure branch -> fall through"),
    (0x495C, 0xB7F80213, NOP, "CONF1 failure branch -> fall through"),
    # after the removed TLMM calls the "mov x19, x0" would pick up a stale x0
    (0x4938, 0xAA0003F3, MOV_X19_XZR, "CONF0: force EFI_SUCCESS"),
    (0x4958, 0xAA0003F3, MOV_X19_XZR, "CONF1: force EFI_SUCCESS"),
    # CONF slots are not wired: pin them to 0 instead of a stale neighbour
    (0x4930, 0x39000A8A, 0x39000A9F, "CONF0: strb wzr,[x20,#2]"),
    (0x4950, 0x39000E8B, 0x39000E9F, "CONF1: strb wzr,[x20,#3]"),
    # carried over from the first bring-up rounds: this branch used to report
    # ScanCode=0x102 at [sp,#0x10]; make it report UnicodeChar=Enter(0x0D)
    (0x42A0, 0x52802046, 0x528001A6, "key report: w6 = 0x102 -> 0x0d (Enter)"),
    (0x42A4, 0x790023E6, 0x790027E6, "key report: strh w6,[sp,#0x10] -> [sp,#0x12]"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", default=None,
                    help="ButtonsDxe.efi (default: Mu-Silicium Binaries/judyp/... path)")
    ap.add_argument("-o", "--out", default=None, help="output (default: *.patched.efi)")
    args = ap.parse_args()

    if args.src is None:
        print("error: pass the path of Binaries/judyp/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.efi")
        print("       (the Mu-Silicium checkout is not part of this repository)")
        return 2
    src = Path(args.src)
    dst = Path(args.out) if args.out else src.with_suffix(".patched.efi")
    data = bytearray(src.read_bytes())

    patched_now = 0
    already = 0
    for off, expect, new, why in PATCHES:
        cur = int.from_bytes(data[off:off + 4], "little")
        if cur == new:
            already += 1
            continue
        if cur != expect:
            print(f"error: {src.name}+0x{off:x} = 0x{cur:08x}, expected 0x{expect:08x}")
            print("       wrong ButtonsDxe build; refusing to patch")
            return 1
        data[off:off + 4] = new.to_bytes(4, "little")
        patched_now += 1
        print(f"  +0x{off:04x}  0x{expect:08x} -> 0x{new:08x}  {why}")

    dst.write_bytes(bytes(data))
    print(f"{src.name}: {patched_now} patched, {already} already applied -> {dst}")
    if patched_now == 0 and already == len(PATCHES):
        print("nothing to do (output is identical to input)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
