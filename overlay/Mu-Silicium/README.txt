Mu-Silicium judyp overlay (LG V35 ThinQ), M1 2026-11-14

How to apply into a Mu-Silicium checkout (from overlay/Mu-Silicium/):
  cp -r Platforms Resources Silicium-ACPI <mu-silicium-checkout>/

Contents:
  Platforms/LG/judypPkg/            full port derived from OnePlus enchiladaPkg
                                    (DXE heap moved to 0x99200000/64MB to avoid LG
                                     slpi 0x97C00000/20M + spss 0x99000000/1M)
  Resources/Configs/judyp.toml      FD base 0x9FC00000 size 0x300000 (same as enchilada)
  Resources/DTBs/judyp.dts          SDM845 ABL DT with LG judy reserved-memory values;
                                    compiled dtb ships next to it (judyp.dtb)
  Silicium-ACPI/Platforms/LG/judyp  AcpiTables.inf (reuses Napali AML, new FILE_GUID)

Also required in the checkout (not mirrored, 6.8MB copy of Binaries/enchilada):
  cp -r Binaries/enchilada Binaries/judyp

Build (WSL, /root/UniXNU):
  ./unixnu build firmware -D /root/UniXNU-judyp-bringup --uefi /root/Mu-Silicium
M0-verified output: Build/judypPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd (3 MB)
