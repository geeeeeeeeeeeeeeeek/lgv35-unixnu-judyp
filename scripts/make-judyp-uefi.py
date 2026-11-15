#!/usr/bin/env python3
"""Prepare the LG V35 ThinQ (judyp) UEFI payload resources in a Mu-Silicium checkout.

Unlike make-enchilada-uefi.py this patches no stock package beyond the one GUID declaration
JudypBootMemoryDxe needs: the judyp port in Platforms/LG/judypPkg was derived complete (UniXNU
loader, ACPI tables and the boot memory driver are already in its dsc/fdf). What remains here is
that declaration and the device tree: the firmware volume does not embed it, the boot image
carries it, so compile Resources/DTBs/judyp.dts with dtc.

Usage: make-judyp-uefi.py MU_SILICIUM_DIR
"""
import shutil
import subprocess
import sys
from pathlib import Path

DTS = 'Resources/DTBs/judyp.dts'
MARKER = 'judypPkg/Drivers/JudypBootMemoryDxe/JudypBootMemoryDxe.inf'

# JudypBootMemoryDxe consumes the HOB the previous stage's x0 is published in. Upstream SiliciumPkg
# does not declare that GUID, so EDK II rejects the driver's [Guids] entry and the firmware build stops
# at build.py error 4000. The value is the one uefi-sheng and the enchilada port use. Only the
# declaration is added here; publishing the HOB also needs the SEC entry-argument patch, which is the
# change that historically kept this family from lighting the panel, so it stays out of the build until
# a boot attempt needs the payload ramdisk volume.
SEC_DEC = 'Silicon/Silicium/SiliciumPkg/SiliciumPkg.dec'
SEC_GUID = 'gSiliciumEntryArgHobGuid'
SEC_GUID_LINE = (
    '  # HOB holding the first argument (x0) the previous stage entered SEC with.\n'
    '  gSiliciumEntryArgHobGuid            = { 0xDAEE82E6, 0x8090, 0x4E72, '
    '{ 0xBF, 0xB9, 0x78, 0xC1, 0x3C, 0xD4, 0xE3, 0x59 } }\n')

# BootShim.S fills the ARM64 image header with FD_SIZE alone, but unixnu bootimg refuses an image whose
# header does not describe the shim plus the firmware volume, and the header is what the bootloader uses
# to size the image. Both labels sit in the default .text section, so the shim length is an assembly-time
# constant here.
SHIM_SIZE_LINE = '  .quad FD_SIZE         /* Image Size */'
SHIM_SIZE_PATCHED = '  .quad FD_SIZE + (_Payload - _Head)  /* Image Size: shim plus firmware volume */'


def read(path):
    return path.read_text(encoding='utf-8'), None


def declare_boot_shim_size(uefi):
    """Make the shim's ARM64 header describe the whole image, as unixnu bootimg verifies."""
    shim = uefi / 'BootShim/BootShim.S'
    text = shim.read_text(encoding='utf-8')
    if SHIM_SIZE_LINE not in text:
        # Local trees that carry the older hand-written line already describe the whole image.
        if SHIM_SIZE_PATCHED in text or '_Payload - _Head' in text:
            return
        raise SystemExit(f'neither the stock nor the patched image size line is in {shim}')
    shim.write_text(text.replace(SHIM_SIZE_LINE, SHIM_SIZE_PATCHED), encoding='utf-8')
    print('BootShim/BootShim.S: image size now covers the shim plus the firmware volume')


def declare_entry_arg_guid(uefi):
    """Add the entry-argument HOB GUID to the SEC package's [Guids] section, once."""
    dec = uefi / SEC_DEC
    text = dec.read_text(encoding='utf-8')
    if SEC_GUID in text:
        return
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        # The token space GUID is the first [Guids] entry; the Pcds below it hold a dot, not " = {".
        if line.startswith('  gSiliciumPkgTokenSpaceGuid') and '= {' in line:
            lines.insert(index + 1, SEC_GUID_LINE)
            dec.write_text(''.join(lines), encoding='utf-8')
            print(f'{SEC_DEC}: declared {SEC_GUID}')
            return
    raise SystemExit(f'no [Guids] anchor in {dec}')


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

    declare_entry_arg_guid(uefi)
    declare_boot_shim_size(uefi)

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
