#!/usr/bin/env python3
"""Prepare the LG V35 ThinQ (judyp) UEFI payload resources in a Mu-Silicium checkout.

Unlike make-enchilada-uefi.py this does not patch a stock package: the judyp port in
Platforms/LG/judypPkg was derived complete (UniXNU loader, ACPI tables and the boot memory
driver are already in its dsc/fdf). What remains here is the device tree: the firmware volume
does not embed it, the boot image carries it, so compile Resources/DTBs/judyp.dts with dtc.

Usage: make-judyp-uefi.py MU_SILICIUM_DIR
"""
import shutil
import subprocess
import sys
from pathlib import Path

DTS = 'Resources/DTBs/judyp.dts'
MARKER = 'judypPkg/Drivers/JudypBootMemoryDxe/JudypBootMemoryDxe.inf'


def read(path):
    return path.read_text(encoding='utf-8'), None


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    uefi = Path(sys.argv[1]).resolve()

    target = uefi / 'Platforms/LG/judypPkg'
    if not (target / 'judyp.dsc').is_file():
        raise SystemExit(f'{target}/judyp.dsc missing; the judypPkg port is not checked out')
    text, _ = read(target / 'judyp.dsc')
    if MARKER not in text:
        raise SystemExit(f'{MARKER} missing from judyp.dsc; the package is incomplete')

    dts = uefi / DTS
    if not dts.is_file():
        raise SystemExit(f'{dts} missing')
    dtb = dts.with_suffix('.dtb')
    if shutil.which('dtc'):
        subprocess.run(['dtc', '-q', '-I', 'dts', '-O', 'dtb', '-o', str(dtb), str(dts)], check=True)
        print(f'device tree: {dtb}')
    else:
        print(f'dtc not found (dnf install dtc, or apt install device-tree-compiler); before unixnu bootimg, run:\n'
              f'  dtc -I dts -O dtb -o {dtb} {dts}')

    print('next: ./unixnu build firmware -D <judyp-bringup> --uefi <this checkout>')


if __name__ == '__main__':
    main()
