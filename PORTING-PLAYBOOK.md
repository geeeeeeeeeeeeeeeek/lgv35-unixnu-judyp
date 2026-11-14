# LG V35 (judyp) UniXNU 移植手册

> 依据：UniXNU 官方文档 `docs/porting/{steps,bring-up,uefi-firmware,packaging,log-capture}.md`
> 　　＋ link-nemo.com「Nemo」LG V35 全系列实战文章（BL 解锁 / fastboot 进入 / TWRP / vbmeta / 9008）
> 目的：修正此前"无证据盲刷"的错误做法，按官方 bring-up 顺序重排工作。
> 最后更新：2026-11-14

---

## 一、结论先行

### 1.1 已确认成立的事实

| 事实 | 证据来源 |
|---|---|
| judyp UEFI 固件可构建，FD 3MB 整，零错误 | M0/M1 构建日志 |
| 我们的 boot.img 结构：`gzip(BootShim + FD) + 追加 DTB`，BootShim 存在且 ARM64 头正确 | 解包验证：`_FVH`@232，`ARM\x64` magic 正确，`text_offset=0x9FC00000`，`image_size=0x3000C0` |
| LG 原厂 ABL **不校验 boot 内容签名** | LOS 22.2 用非 LG 签名 boot 可正常开机 |
| LG 原厂 ABL 在 boot **判定不可启动**时，会主动进入 fastboot（救援机制） | link-nemo：刷安卓8 boot 进 fastboot；用户的机型行为一致 |
| 原厂 boot / LOS boot / 我们的 boot 头部字段几乎全同（仅 kernel_size 不同） | 头部 diff |
| 真机内存布局 19/19 保留区核对通过 | M2 live FDT 比对 |

### 1.2 关键未知（必须用证据消除，不许再猜）

**核心问题：`立即回到 BL` 到底是 ABL 静态拒绝，还是 UEFI 执行后崩溃复位？**

两者从外部表现上无法区分，但**耗时不同**：

| 判定 | 预期时间特征 | 含义 |
|---|---|---|
| ABL 静态拒绝（header/大小/校验） | 重启后 **< 3 秒** 回到 fastboot | boot.img 本身不合格 |
| BootShim 执行 → FD 早期崩溃 → 看门狗复位 → 重试耗尽 | **5～20 秒** 才回 fastboot | 固件代码问题 |
| FD 跑到菜单但无显示 | 卡住不返回 / USB 出现 `05C6:F000` | 显示驱动问题 |

**此前 6 次实验全部没有测量过这个时间差，也没有监控过 USB PID。这是方法性缺失。**

---

## 二、UniXNU 官方适配流程（权威版本）

### 2.1 八个移植步骤（`porting/steps.md`）

| # | 步骤 | 产出 |
|---|---|---|
| 1 | **收集设备输入**：SoC、CPU 布局、RAM 保留区、中断控制器、存储、面板、触控、无线、固件版本。来源：原厂 DTS、固件源码、硬件实测 | 硬件清单 + 缺失输入列表 + `porting.toml` 记录 |
| 2 | **选择共享支持**：`profiles/arch/arm64`、`UniXNU-<soc>-common`、`profiles/os/<profile>`、`UniXNU-<device>`、`uefi-<device>` | 锁定源码版本 |
| 3 | **创建设备仓库**：`board.toml` / `feeds.toml` / `porting.toml` / DTS / `proprietary-files.txt` / README / AGENTS.md | 可构建的仓库骨架 |
| 4 | **解析并检查构建**：`defconfig` → `fetch` → `status --json` → `tree` | 依赖解析树 |
| 5 | **硬件描述与固件**：DTS → DTB；UEFI 必需集成；固件构建；boot image 打包 | FD + boot.img |
| 6 | 驱动适配（各子系统） | 驱动可用 |
| 7 | Payload / 内核 | payload.img + kernel.macho |
| 8 | 验证与发布 | 设备记录 + 清单 |

### 2.2 Bring-up 七个 Stage（`porting/bring-up.md`）—— **严格按序，一次只隔离一个 stage**

| Stage | 目标 | 验收信号 |
|---|---|---|
| **1. UEFI** | 固件跑到 UEFI Shell / 菜单 / UniXNU | FD 大小匹配 `[uefi_fd] size`；**boot image header 匹配 bootloader 要求**；`fastboot boot` 后**不复位**；**framebuffer 有输出或串口有 UEFI 输出**；块设备与 payload 卷可见 |
| 2. UniXNU | 菜单出现、配置解析 | 串口行以 `UNIXNU:` 开头；报告 entry/driver/patch/ACPI/slice/kit 计数 |
| 3. Payload | 读取 `unixnu.toml` 与 payload 文件 | 配置路径、`xnu` entry、哈希匹配、ADT sidecar 存在 |
| 4. DarwinBoot | 校验 kernel/ADT/trust cache 后退出 boot services | 串口以 `DARWINBOOT:` 开头；打印 virtual/physical base、args/entry 地址、framebuffer 参数、EL1 |
| 5. Kernel entry | XNU 到 platform expert | 内核版本与启动参数；`/cpus`、`/arm-io`、`/defaults`、`/options` 存在 |
| 6. Storage & root | 块驱动发布 userdata，根卷挂载 | 链接速率、命令队列、`OS`/`SystemOS` 分区、UUID 匹配、launchd |
| 7. Userland | launchd 起、首进程可见 | Data 卷挂载、显示/控制台输出、`boot-progress=2` |

> **我们当前卡在 Stage 1**，且 Stage 1 的验收条件（framebuffer 输出或串口输出）**从未建立**。

### 2.3 日志采集是 bring-up 的第一件事（`porting/log-capture.md`）

> 原文：**"Set up log capture as you bring up the board."**

四层证据链，逐层升级：

| 层级 | 手段 | 适用阶段 |
|---|---|---|
| **① UEFI 菜单内** | Advanced Logger + `AdvancedLogDxe` + **二维码导出（OneSend 扫传）** | 固件能到菜单 |
| ② XNU entry | UART 或 framebuffer 诊断（彩色条 / 绿色交接条） | 内核阶段 |
| ③ Storage | 预留 log 区 + 内核写入器 + Linux/recovery 读取器 | 存储可用后 |
| ④ 自动化 | 定时复位 + 主机 runner | 反复测试 |

**关键结论：只要固件能跑到菜单，日志可以用手机扫码拿走，完全不需要拆机、不需要串口。**

`porting/log-capture.md` 明确写道：
> "**If firmware stops before the menu, capture the platform UART or photograph its last visible output.**"

也就是说只有"连菜单都到不了"才考虑串口。

### 2.4 boot image 的硬性要求（`porting/uefi-firmware.md`）

Mu-Silicium 设备配置 `Resources/Configs/<device>.toml`：

```toml
[boot_shim]
requires_kernel_header = true      # bootloader 检查镜像开头的 ARM64 头

[uefi_fd]
base = 0x9FC00000                  # FD 加载的物理地址（编译进 BootShim）
size = 0x300000                    # FD 精确大小

[boot_image_kernel]
kernel_compression = "gzip"        # shim + FD 一起压缩
append_dtb = true                  # DTB 追加在 kernel 字段末尾

[boot_image]
header_version = 1                 # Android boot image 头部版本
```

打包命令实际做的事（官方给出）：

```sh
clang --target=aarch64-none-elf -c \
  -DFD_BASE=<base> -DFD_SIZE=<size> \
  -DREQUIRES_KERNEL_HEADER=<0|1> \
  BootShim/BootShim.S -o shim.o
# → 追加 FD → 整体 gzip → 追加 DTB → 打成 Android boot image
```

**验收三查**：
- FD 大小 == `[uefi_fd] size`
- shim header 含 `ARM\x64` 且 base/size 字段正确
- 解包 boot.img 逐部件比对

### 2.5 固件必需集成（Stage 1 就要求）

DSC `[Components]` 与 FDF 固件卷都需包含：

| 模块 | 作用 |
|---|---|
| `UniXNUPkg/Application/UniXNU/UniXNU.inf` | 启动菜单与配置读取 |
| `UniXNUPkg/Driver/UniXNUDxe/UniXNUDxe.inf` | 启动项注册 |
| `DarwinBootPkg/Driver/DarwinBoot.inf` | XNU loader |
| `UniXNUPkg/Driver/UniXNURamDiskDxe/UniXNURamDiskDxe.inf` | FDT initrd → 只读块设备 |
| `MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf` | 磁盘访问 |
| `FatPkg/EnhancedFatDxe/Fat.inf` | 暴露 payload FAT |

共享库映射：
```ini
HobLib|MdePkg/Library/DxeHobLib/DxeHobLib.inf
FdtLib|MdePkg/Library/BaseFdtLib/BaseFdtLib.inf
```

**必需服务**：`EFI_GRAPHICS_OUTPUT_PROTOCOL`（菜单/显示）、`EFI_SIMPLE_TEXT_IN_PROTOCOL`（输入）、`EFI_SIMPLE_FILE_SYSTEM_PROTOCOL`、`EFI_BLOCK_IO_PROTOCOL`、`EFI_SERIAL_IO_PROTOCOL`（有 UART 时）、`EFI_ACPI_TABLE_PROTOCOL`、`EFI_FIRMWARE_VOLUME2_PROTOCOL`。

### 2.6 硬件之前先跑 QEMU

> "**QEMU before hardware**" — `JOBS=8 bash package/Scripts/smoke.sh`

在真机之前，用 QEMU 验证 UEFI 包、菜单、payload fixture。我们**跳过了这一步**。

---

## 三、我们做到哪 vs 官方要求

| 官方要求 | 我们的状态 | 差距 |
|---|---|---|
| 1. 硬件清单 + `porting.toml` | 零散记在 project_memory.md | ❌ 无正式记录文件 |
| 2. 共享支持锁定 | board.toml 已 judyp 化 | ✅ |
| 3. 设备仓库完整 | board.toml/DTS/scripts 有 | ⚠️ 无 `porting.toml`，无 `AGENTS.md` |
| 4. 构建解析 | `unixnu status` 全绿 | ✅ |
| 5. FD + boot.img | FD 构建成功；boot.img 结构正确 | ⚠️ **header_version 配置冲突** |
| **Stage 1 验收：framebuffer 或串口输出** | **从未建立** | ❌ **最大缺口** |
| 日志采集链 | **完全没有**：无 AdvancedLogDxe、无 Advanced Logger、无 Tools 菜单 | ❌ **最大缺口** |
| QEMU 预验证 | 跳过 | ❌ |
| 时间/证据记录 | 6 次实验只有"回 BL"一句 | ❌ 无法定位 |

### 3.0 judypPkg 集成核对（2026-11-14，更正前一版）

前一版说"缺 DiskIoDxe / Fat / RamDiskDxe"是错的，逐行核对后更正：

- **DiskIoDxe / PartitionDxe / Fat.inf / EnglishDxe 本来就有**：在 `judypPkg/Include/APRIORI.inc`（35–43 行）与 `DXE.inc`（43–46 行），judyp.fdf 通过 `!include Include/APRIORI.inc` 带进 FVMAIN。
- **`JudypBootMemoryDxe` 就是本平台的 `UniXNURamDiskDxe`**：移植自 uefi-sheng 的 `ShengBootMemoryDxe`，读 `/chosen linux,initrd-start/-end` 后发布 `EFI_BLOCK_IO_PROTOCOL`（源码 379 行 `mBlockIo`）。不需要再加 `UniXNURamDiskDxe`。
- **唯一真实缺失：`AdvancedLogDxe`**（及 `AdvancedLoggerAccessLib`、`QrEncoderLib`）、`[payload] tools = true`、`PcdUniXNUDeviceModel`。A1 已全部补齐，FD 重建后仍为 3,145,728 字节。
- **但平台没有 Advanced Logger 生产者**：`SiliciumPkg.dsc.inc` 的 DebugLib 是 `BaseDebugLibSerialPort` + `FrameBufferSerialPortLib`，没有任何模块产生 `gAdvancedLoggerProtocolGuid`。因此 `AdvancedLogDxe` 现在只会安静地不 dispatch，`Tools → Advanced Logger` 会报 no log。**Stage 1 的证据暂时主要靠屏幕 DEBUG 文本（FrameBufferSerialPortLib 写 "Display Reserved" 区）+ USB PID + 耗时。**

**显示链**：`USE_CUSTOM_DISPLAY_DRIVER = 1`，走 LG 自己的 `Binaries/judyp/QcomPkg/Drivers/DisplayDxe` + `DisplayReEnablerDxe`，不是 SimpleFbDxe。`Binaries/judyp` 目录确实存在（来自 V35 固件提取），与 enchilada 的显示二进制不是一套。

### 3.1 header_version 的真相（更正）

`bootimg.py` 的取值顺序（`scripts/unixnu/bootimg.py:62-69`）：
`DEFAULTS` → Mu 的 `Resources/Configs/<device>.toml [boot_image]` → `board.toml [bootimg.image]`，**board.toml 最后覆盖**。

judyp 的 `board.toml` 是 `header_version = 0`，理由写在同一文件 448–457 行：**这台手机自己的 boot_a 按 v0 解析**，LineageOS 22.2 的 boot.img 就是 v0 且能正常开机。所以 **v0 不是问题，不要改成 v1**（已把 Mu 侧 judyp.toml 同步为 0，消除误导值）。

此前引用的 "Header v4 was required; the v0 image stayed in fastboot" 出自 `docs/.vitepress/device-records/cupid-lengcece.toml`（小米 12），**不是 enchilada，也不适用于 judyp**。

### 3.2 DTB 不是草稿（已核实）

`judyp.dtb` = 554,858 字节，与 Mu 的 enchilada.dtb 555,398 同量级 → 完整版。打包用的就是 **Mu 的 `Resources/DTBs/judyp.dtb`**；A1 的 boot-a1.img 已逐字节比对通过。设备仓库里的 `dts/*.dtb` 才是可能有 2.7KB 草稿的地方，我们不从那里取。

### 3.3 这个仓库是 enchilada 的克隆（重要）

`/root/UniXNU-judyp-bringup` 的 git remote 是 `keyfan/UniXNU-enchilada-bringup`，`porting.toml` 第 1–11 行仍写 OnePlus 6，`evidence/` 里的 `stage2-uefi-menu-reached.md`、`05C6:F000`、ramdisk 18MiB 窗口等**全是 enchilada 的实测**，不是这台 V35 的。引用任何"已测"结论前必须先确认出处，别把 enchilada 的成绩当成 judyp 的。

---

## 四、LG V35 平台特殊性（link-nemo 实战经验）

### 4.1 启动链与 fastboot 的真实含义

| 机制 | 说明 |
|---|---|
| **正常启动** | ABL 读 boot_a → 校验 → 加载 kernel |
| **boot 不可启动** | LG ABL **主动进入 fastboot**（不是变砖，是救援） |
| **安卓10 机进 fastboot 的标准做法** | 用 LGUP PARTITION DL 单刷安卓8 KDZ 的 `boot_a` → 重启 → 进 fastboot |
| **fastboot 同会话限制** | 一次会话第二次 `fastboot boot` 必报 Load Error；每次尝试前需 `set_active` |

> **推论**：用户看到的"没有 LG logo、立即回 BL"更符合 **ABL 判定 boot 不可启动**，而不是 UEFI 执行后崩溃（崩溃会走重试与看门狗，耗时明显更长）。
> **但这必须用时间测量证伪，不能当结论用。**

### 4.2 解锁与分区操作要点

| 操作 | 方法 |
|---|---|
| BL 解锁 | 9008(QFIL + `prog_ufs_firehose_Sdm845_lge.elf`) 刷**工程机 abl** → `fastboot oem unlock` → **刷回原 abl_a** |
| 解锁标志 | 开机出现黄色感叹号提示 |
| A/B 机无独立 recovery | **TWRP 刷在 boot_a**（boot_b 用于 system_b） |
| 进 TWRP | ① 系统内 `adb reboot recovery`；② 音量减+电源 → 黑屏 → LG logo 亮时按两下电源 → 保持音量减 → 白屏黑字选 yes×2 |
| data 未解密时 | ROM 要放 SD 卡或 `adb sideload`，不能放内置存储 |
| 双清顺序 | 先清 data，再清 data + Dalvik（拆成两步） |
| vbmeta | 社区有"修改版 vbmeta_a.img"，`fastboot flash --disable-verity --disable-verification vbmeta_a <img>`，disable 参数随 flash 注入生效 |
| OP 分区 | 影响铃声 / LG 应用 / VoLTE；卡刷包内做法 `rm -rf /OP/* && cp -a /system/system/OP/* /OP/` |
| 救砖兜底 | 9008 + QFIL + rawprogram XML 全分区刷；资源站 `rnm.sbtx.cc` |

### 4.3 社区已验证可启动的 boot 特征

TWRP boot / magisk boot / 原厂 boot / LOS boot 全部：
- `header_version = 0`
- kernel = 真实 Linux ARM64 Image（gzip + ARM64 头）
- **非空 cmdline、非空 product/board 字段**
- os_version 与系统版本匹配

> 我们试过"字段全抄原厂"，但仍被拒。说明差异不在这些字段本身。

---

## 五、修正后的执行顺序

### 阶段 A：补齐证据能力（先做，不碰手机测试）

1. ✅ **A1. 日志导出**：DSC/FDF 已加 `AdvancedLogDxe.inf` + `AdvancedLoggerAccessLib` + `QrEncoderLib` + `PcdUniXNUDeviceModel|"judyp"`，`board.toml [payload] tools = true`。FD 重建通过，仍为 3,145,728 字节。**注意：平台尚无日志生产者，QR 导出暂为空**。
2. ✅ **A2. DTB**：确认 `judyp.dtb` 是完整版（554,858 字节），boot-a1.img 内逐字节一致。
3. ✅ **A3. header_version**：确认为 **v0**（不是 v1），Mu 侧 `judyp.toml` 已同步为 0；新 boot.img 头已解剖验证 v0 + 无 ramdisk。
4. ⏳ **A4. QEMU 冒烟**：官方 `package/Scripts/smoke.sh` 只验证 UniXNU 自身（自带 ESP fixture），不覆盖 Mu 固件；WSL 正在装 `qemu-system-arm`。若跑通可作为「UniXNU 能在标准 AArch64 UEFI 下出菜单」的旁证，但它**不能替代真机 Stage 1**。
5. ✅ **A5. `porting.toml`**：已整体重写为 judyp 记录（14 个区域全部到位），`porting-record.py check` 通过。原文件是 enchilada 的克隆（第 1–11 行写 OnePlus 6），已在记录里如实标注"Stage 1 未验证"，并把继承来的 enchilada 实测结论与 judyp 区分开。

### 阶段 B：Stage 1 验收（带证据的真机测试）

每次实验固定记录四件事：**时间戳、USB PID 时间线、屏幕现象、FD/boot.img 的 sha256**。

1. **B1. 时间测量**：`fastboot reboot` 后每 200ms 轮询 `fastboot devices`，测"回 BL 耗时"。
   - < 3s → 静态拒绝，查 header/大小/签名
   - 5–20s → 执行后崩，查 FD 早期
   - 不返回 → 可能已跑起来但无显示
2. **B2. USB PID 监控**：轮询 `VID_05C6` 的 PID。fastboot 与 UEFI 的 PID 不同；出现新 PID = 固件在跑。
3. **B3. 禁用 `fastboot boot`**：已实测无效（连 LOS 的 boot.img 也是约 4s 回 fastboot）。只能用 `set_active <slot>` + `flash boot_<slot>`，再用电源键正常重启。
4. **B4. 逐项二分**：header v1 vs v0 / ramdisk 1 字节 vs 空 / DTB 完整 vs 草稿 / FD base-size 一致性。**一次只改一个变量。**
5. **B0. 首轮只用 A1 镜像**：`build/boot-a1.img`（1,753,088 B，sha256 `ccd49a1ba663ec4d3240ddeb6fcfd99ccf43a494d9fb05f4b9c9c5ef8e31e5e0`），64MiB 补齐版 `boot-a1-64m.img`（sha256 `3ce4191a26f5750725a4597b97a678cb55c9cbf89435220861b022b3377197cc`），FD sha256 `0aeba258be6174d00d8ba3f17b1bee1bd1d2026e5b7b4af0325e266de152f209`。这一版与之前 6 次的唯一差别是固件卷里多了 AdvancedLogDxe，其余逐字节可控。

### 阶段 C：进入 Stage 2 及以后

菜单出现后，立刻用 **Tools → Advanced Logger → 扫码**取日志，然后才往 payload / DarwinBoot 推进。

---

## 五点五、2026-11-14 22:53–22:59 真机实测（第一份运行时证据）

证据文件在 `m4/`：`stage1-attempt-01.log`、`stage1-control-los.log`、`stage1-bootloop-01.log`、`getvar-all.txt`。

**1. `fastboot boot` 在这台机器上无效（已证实）**
- 我们的 `boot-a1.img`：`Sending OKAY 0.041s` / `Booting OKAY 0.074s`，约 2.6s 后重新出现在 fastboot
- 对照 LOS 的 `boot.img`（sha `dc3b39bb…b5da`，64MiB）：同样 `Booting OKAY`，约 4s 后回到 fastboot
- 结论：ABL 接受下载并"启动"，但两次都回到 fastboot；**这条路径不能用来判断镜像好坏**，此前用它做的任何推断都作废

**2. `fastboot reboot` 也没有真正尝试启动**
- 重启后 USB 断开一次、约 3.2s 回到 fastboot，`current-slot` 仍为 b
- `slot-retry-count:b` 保持 `5` **没有递减** → ABL 根本没尝试跳转；这 3.2s 是"重启后直接回到 fastboot"，不是崩溃

**3. 槽位状态（关键，此前完全没看）**
```
current-slot      : b
slot-unbootable:a : yes     slot-retry-count:a : 0    slot-successful:a : no
slot-unbootable:b : no      slot-retry-count:b : 5    slot-successful:b : no
partition-size:boot_a/b : 0x4000000 = 67,108,864 = 64 MiB   ← 用户指正的 64M，确认
```
- **a 槽已被标记为不可启动、重试次数为 0**。此前把镜像刷进 boot_a 的实验，即使镜像本身没问题，ABL 也不会去启动它
- 两个槽的 `successful` 都是 `no`
- 这解释了为什么"怎么刷都回 BL"：实验对象（a 槽）本来就不在启动路径上

**4. 下一步的正确协议（待用户许可后执行）**
1. `fastboot set_active b` 明确指定槽位（不要依赖默认）
2. `fastboot flash boot_b <img>`，刷完立刻 `fastboot getvar slot-retry-count:b` 记基准值 5
3. 用**电源键**正常重启（不依赖 `fastboot reboot`），再读 `slot-retry-count:b`
   - 变成 4 → ABL 确实尝试过启动，这时的耗时和现象才有意义
   - 仍是 5 → 又是直接回 fastboot，不能下任何关于镜像的结论
4. 先刷 LOS 做基准（应进 Android、adb 可见），再刷 A1 复现差异

**5. QEMU 冒烟暂时不可用**：`smoke.sh` 需要 Mu_Basecore 的 libfdt/mipisyst/brotli 子模块，当前网络走 `ghfast.top` 代理，克隆失败。A4 记为"环境受阻"，不代表固件有问题。

**6. 46 秒实验的正确解释（已由用户确认）**：刷 LOS 的 boot 到 boot_a 后设备离开 USB 46 秒才回 fastboot —— 这是**真的启动了** LOS 内核，但系统分区仍是官方 Android 10，必然起不来。**这不是 UEFI 镜像的失败证据**，不能拿来推断 A1。

**7. 官方 A10 恢复成功（已验证）**：
```
boot_a.img sha256 70DD8DDDDF1E146B4B2D1FEB6B6A0FFA27558109379F53262397965F89C73F44
boot_b.img sha256 A2CF40EAACF68ECC0C93F88200B061554B465E7D7036E8E511171547CC3C8D81
set_active a 后 slot-unbootable:a = no，重启正常进 Android 10
```
位置：`E:\lgv35\backup\lgv35bak\`（全套分区备份，含 system/vendor/vbmeta/dtbo 的 a/b 两份）。**这是唯一的救砖基线，A1 失败时用 `fastboot flash boot_a boot_a.img` 一条命令即可恢复。**

**8. 由 7 得出的实验安全网**：a 槽刷 A1、b 槽保留官方 A10。A1 若失败，ABL 会回滚到 b，手机会自动进 Android 10——不会变砖，也不会卡在 fastboot。

**9. 关于"a 槽 unbootable"的更正**：`set_active a` 能把 `slot-unbootable` 重置为 `no`（已实测）。因此它不是永久损坏，但**刷写后不 `set_active` 就重启**，ABL 确实不会启动该槽——这仍是之前实验无效的原因。

### 5.10 Stage 1 判别实验记录（2026-11-14 夜，全部单变量）

| # | 镜像 | 构成 | 结果 |
|---|---|---|---|
| 1 | 官方 A10 boot_a | v1 / 16MB ramdisk / 有 cmdline | 正常进 Android（基准） |
| 2 | LOS 22.2 boot | v0 / ramdisk / cmdline / AVB footer | 跑 46 秒后 ABL 回滚（内核起来了，系统不匹配） |
| 3 | **A1** | v0 / **无 ramdisk** / 无 cmdline / `gzip(shim+FD)+DTB` | **约 3 秒回 fastboot** |
| 4 | A1 + LOS 的 ramdisk 与 cmdline | v0 / ramdisk / cmdline / 同样内核 | **约 3 秒回 fastboot** |
| 5 | 4KB 死循环内核 | v0 / 合法 ARM64 头 / gzip / 补齐 64MiB | **约 3 秒回 fastboot** |
| 6 | LOS 镜像抹掉末尾 64B AVB footer | 其余字节完全不变 | **照样跑 40 秒不返回** |

由 3/4/5 可判定：**失败与 ramdisk、cmdline、header 版本、text_offset、压缩方式、内核代码都无关**——连一个 4KB 的死循环都跑不起来。
由 6 可判定：**AVB 没有被强制校验**（无 footer 的 LOS 照样执行），所以"未签名"不是原因。
剩余唯一未排除的分叉：ABL 究竟有没有跳进我们的内核（3 秒是"拒绝"还是"跳了之后被复位/看门狗打死"）。

四种内核解压后的 ARM64 头实测：
```
STOCK  code0=0x147e0000 text_offset=0x80000    image_size=0x2e5a000  flags=0xa
LOS    code0=0x14xxxxxx text_offset=0x80000    image_size≈0x2e5a000  flags=0xa
A1     code0=0x10000601 text_offset=0x9fc00000 image_size=0x3000c0   flags=0x0
```
A1 的 `flags=0` 与 `text_offset=0x9FC00000` 与官方/LOS 都不同，已列为下一个待验证项（但实验 5 已把 text_offset 设回 0x80000 且 flags=0xa，仍然失败，故两者都不是充分原因）。

**尚未采集的证据（只能靠屏幕）**：这 3 秒里 LG logo 有没有出现。出现 = ABL 跳了，问题在 SEC/PEI；完全不出现 = ABL 在加载阶段就中止。

---

## 六、待确认清单

| # | 问题 | 解决方式 |
|---|---|---|
| 1 | 回 BL 的精确耗时 | B1 自动测量 |
| 2 | UEFI 是否真的被执行（USB PID 是否变化） | B2 监控 |
| 3 | ~~`judyp.dtb` 是完整版还是草稿~~ | 已确认完整（554,858 B） |
| 4 | ~~`board.toml` 与 `judyp.toml` 谁生效~~ | 已确认：board.toml 覆盖（`bootimg.py:62-69`），且两者均为 v0 |
| 5 | LG ABL 是否要求 v1 | 已排除：本机 boot_a 解析 v0，LOS 的 v0 可开机；不再测 v1 |
| 6 | ~~FD base/size 是否与 BootShim 一致~~ | 已确认：`text_offset=0x9FC00000`，`image_size=0x3000C0`，FD=0x300000 |
| 7 | ~~固件卷是否含显示驱动~~ | 已确认：`Binaries/judyp/.../DisplayDxe` + `DisplayReEnablerDxe`（LG 原厂），非 SimpleFbDxe |
| 8 | 平台是否需要真正的 Advanced Logger 生产者 | Stage 2 前决定；Stage 1 用屏幕文本 + USB PID 即可 |
| 9 | 本机 RAM 是 6GiB 还是 8GiB（board.toml 写 0x180000000） | 进 LOS 后 `adb shell head -1 /proc/meminfo` + `getprop ro.boot.msz` |

---

## 七、纪律（写给自己的）

1. **没有运行时证据，不改下一个变量。**
2. **一次只改一个变量**，记录 sha256。
3. **优先 `fastboot boot`，不写分区**；写分区前确认有回退镜像。
4. **不做拆机 / 串口方案**，除非官方文档的扫码日志路径确实走不通。
5. **每次实验前先确认设备在线**，USB 掉线时不要连发命令。
