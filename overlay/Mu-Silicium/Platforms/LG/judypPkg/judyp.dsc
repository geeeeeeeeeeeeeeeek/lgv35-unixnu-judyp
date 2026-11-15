##
#  Copyright (c) 2011 - 2022, ARM Limited. All rights reserved.
#  Copyright (c) 2014, Linaro Limited. All rights reserved.
#  Copyright (c) 2015 - 2020, Intel Corporation. All rights reserved.
#  Copyright (c) 2018, Bingxing Wang. All rights reserved.
#  Copyright (c) Microsoft Corporation.
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
##

################################################################################
#
# Defines Section - statements that will be processed to create a Makefile.
#
################################################################################
[Defines]
  PLATFORM_NAME                  = judyp
  PLATFORM_GUID                  = 5C1E9B4A-2D3F-4E68-8B90-1A2C3D4E5F60
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 0x00010005
  OUTPUT_DIRECTORY               = Build/judypPkg
  SUPPORTED_ARCHITECTURES        = AARCH64
  BUILD_TARGETS                  = RELEASE|DEBUG
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = judypPkg/judyp.fdf
  # SimpleFbDxe only: it draws into the cont_splash framebuffer the ABL leaves running, which is the
  # one display path that has ever produced the menu (E40). The LG vendor stack behind
  # USE_CUSTOM_DISPLAY_DRIVER=1 (DisplayDxe/DisplayReEnablerDxe/CPRDxe) ran the DXE heap out of
  # memory on the first firmware-built run -- FzDxe ASSERTed in UncachedMemoryAllocationLib.c(389)
  # with EFI_OUT_OF_RESOURCES -- so it stays off until the memory story is understood.
  USE_CUSTOM_DISPLAY_DRIVER      = 0

!include NapaliPkg/NapaliPkg.dsc.inc

[PcdsFixedAtBuild]
  #
  # DDR Memory
  #
  gArmTokenSpaceGuid.PcdSystemMemoryBase|0x80000000

  #
  # UEFI Stack
  #
  gArmPlatformTokenSpaceGuid.PcdCPUCoresStackBase|0x9FF90000
  gArmPlatformTokenSpaceGuid.PcdCPUCorePrimaryStackSize|0x40000

  #
  # SMBIOS
  #
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemManufacturer|"LG"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemModel|"V35 ThinQ"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemRetailModel|"judyp"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemRetailSku|"LM-V350"
  gSiliciumPkgTokenSpaceGuid.PcdSmbiosSystemBoardModel|"judyp"

  #
  # Simple Frame Buffer
  #
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferWidth|1440
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferHeight|2880
  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferColorDepth|32

  #
  # Platform PEI
  #
  gQcomPkgTokenSpaceGuid.PcdPlatformType|"WP"

[LibraryClasses]
  #
  # Memory Libraries
  #
  MemoryMapLib|judypPkg/Library/MemoryMapLib/MemoryMapLib.inf

  #
  # QCOM Libraries
  #
  ConfigurationMapLib|judypPkg/Library/ConfigurationMapLib/ConfigurationMapLib.inf

[Components]
  #
  # ACPI Tables
  #
  judyp/AcpiTables.inf

  #
  # UniXNU: the boot manager application and the driver that creates its boot option.
  #
  UniXNUPkg/Application/UniXNU/UniXNU.inf
  UniXNUPkg/Driver/UniXNUDxe/UniXNUDxe.inf

  #
  # The XNU loader. It installs gUniXNULoaderProtocolGuid, which is what UniXNU asks BDS
  # for before it touches the payload; [payload] loader = "firmware" says it lives here.
  #
  DarwinBootPkg/Driver/DarwinBoot.inf

  #
  # The boot image ramdisk as a block device: the payload FAT volume.
  #
  judypPkg/Drivers/JudypBootMemoryDxe/JudypBootMemoryDxe.inf

[LibraryClasses]
  UniXNULib|UniXNUPkg/Library/UniXNULib/UniXNULib.inf
  FdtLib|MdePkg/Library/BaseFdtLib/BaseFdtLib.inf
