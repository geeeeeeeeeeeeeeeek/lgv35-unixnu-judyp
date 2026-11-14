# LG V35 ThinQ (judyp) — UniXNU 移植

在 LG V35 ThinQ（`judyp`，SDM845，Bootloader 已解锁）上跑 [UniXNU](https://github.com/KeyofBlueS/UniXNU)
（UEFI 固件 + 后续 XNU/macOS 引导）的移植工作区。仓库派生自 `UniXNU-enchilada-bringup`
（OnePlus 6，同为 SDM845），LG 的差异都集中在 `board.toml`、`overlay/` 和 `patches/` 里。

逐次实验的完整台账见 **[EXPERIMENTS.md](EXPERIMENTS.md)**，本文件只记结论与复现步骤。

## 当前状态

| 能力 | 状态 |
| --- | --- |
| UEFI 固件启动、画面输出（SimpleFbDxe） | ✅ 可用 |
| UniXNU 启动菜单显示、倒计时、条目列表 | ✅ 可用 |
| 音量上/下键操作菜单（上/下选择） | ✅ 可用（勉强够用，见下） |
| 电源键（确认/回车） | ❌ PON 读取失败，无事件 |
| 触摸 | ❌ 未做（E44） |
| 启动 XNU/内核 | 未开始（倒计时结束会去引导默认项，然后重启） |

按键"勉强可用"的含义：音量键能选菜单，但电源键不可用，且菜单倒计时（约 1~2 分钟）结束后会自动
去引导默认条目并重启，观察窗口有限。

## 硬件事实（实测/反编译所得）

* SoC SDM845，DDR 6 GiB（`0x180000000`），`boot_a`/`boot_b` 各 64 MiB，`header_version = 0`。
* 面板：LG SW43402，1440×2880 cmd-mode DSC P-OLED。
* 触控：FocalTech `ftm4`，GENI I2C `0xA98000`，地址 `0x49`（不是 OnePlus 的 Synaptics）。
* 按键（`Resources/DTBs/judyp.dts`）：

  | 键 | 来源 | input code |
  | --- | --- | --- |
  | 音量加 | `pm8998 gpio6`（active low） | 0x73 |
  | 音量减 | `pm8998 gpio5`（active low） | 0x72 |
  | 电源 | `pm8998 pon kpdpwr` | 0x74 |
  | 霍尔 | `tlmm gpio 0x7c` | — |

## 构建固件

需要 `UniXNU` 与 `Mu-Silicium` 两个检出，本仓库用 `-D` 传入：

```bash
cd ~/UniXNU
./unixnu firmware --uefi ~/Mu-Silicium -D ~/UniXNU-judyp-bringup -j8 --skip-setup
# 产物：~/Mu-Silicium/Build/judypPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd
```

* `--skip-setup` 必须带（跳过需要 macOS 工具的 payload 步骤）。
* 构建会把 `{tree}/package` 复制到 `out/judyp/tree/package`；`Menu.c` 的改动在
  `~/UniXNU/package/UniXNUPkg/Library/UniXNULib/Menu.c`，用
  `patches/unixnu-menu/*.patch` 打到 UniXNU 检出上即可复现。

## 刷机镜像的配方（重要）

Android boot image 的 `kernel` 段里装的**不是内核**，而是：

```
ARM64 Image 头(64B) + 0x80000 全零 + BootShim + UEFI FD(3 MiB)
```

ABL 会像引导 Linux 一样跳到它，BootShim 再把 FD 搬到 `FD_BASE` 并进入。`kernel_dtb` 和
`ramdisk` 保持原厂不动。

* ARM64 头：`code0 = 0x14000000 | (0x80000>>2)`（即 `b +0x80000`）、`text_offset = 0x80000`、
  `image_size = 总长`、`flags = 0xa`、magic `ARM\x64`。
* BootShim 必须用这些宏编译，否则 ABL 不认：

  ```bash
  clang --target=aarch64-none-elf -c \
        -DFD_BASE=0x9fc00000 -DFD_SIZE=0x300000 -DREQUIRES_KERNEL_HEADER=1 \
        BootShim.S -o shim.o
  ```

* 用 `magiskboot unpack` / `repack` 替换 `kernel`，再补零到 64 MiB。
* 一键脚本：[scripts/pack-boot-img.sh](scripts/pack-boot-img.sh)

刷入（任何时刻只允许**一个** fastboot 进程，并发会 `Too many links`）：

```bash
fastboot flash boot_a out.img
fastboot set_active a
fastboot reboot
```

## 踩过的坑（按重要性）

1. **显示走 SimpleFbDxe，不要碰 DisplayDxe。**
   `USE_CUSTOM_DISPLAY_DRIVER = 0` 是唯一能出画面的配置；置 1（DisplayDxe）会在约 20 秒后黑屏挂死。
2. **`REQUIRES_KERNEL_HEADER=1` 不能省。** 少这个宏时 BootShim 的入口偏移不对，ABL 跳进去直接黑屏。
3. **DEBUG 日志是画到屏幕上的。**
   Mu-Silicium 的 `DebugLib` 是 `FrameBufferSerialPortLib`，它把文本画进 framebuffer（光标位置存在
   framebuffer 末尾 8 字节），没有 PCD 能关。所以任何高频 `DEBUG()` 都会把 UI 刷掉——调试时"看不到
   菜单"往往不是没启动，而是被日志盖住了。
4. **`ButtonsDxe` 装的 SimpleTextIn 没有 DevicePath，ConSplitter 看不到。**
   `ConPlatformDriverBindingSupported` 要求句柄带 DevicePath，否则不聚合进 `gST->ConIn`。驱动的协议
   装在 ImageHandle 上，所以菜单必须自己 `LocateHandleBuffer` 找到这些"孤立"实例直接轮询
   （`Menu.c` 的 `CollectOrphanInputs()` / `ReadInputKey()`）。
5. **`PollButtonArray` 是"一票否决"：任一脚读失败就丢弃全部按键。**
   它依次读 PON 电源键、PM8998 GPIO6（VOL+）、GPIO5（VOL-）、TLMM 75（CONF0）、TLMM 76（CONF1），
   每步后面都跟 `tbnz x19,#0x3f,<error>`。judyp 上 TLMM 读会内部触发
   `smem_alloc: SMEM allocation failed! smem_type=138`，PON 读也失败 → 一个键都没有，屏幕上只剩
   `ButtonsDxe - PollButtonKeys failed status:0x...` 刷屏。
   解决办法是二进制补丁（见下）。
6. **SMEM 不可用是更深的根因。** `PlatformInfo` 的 hw version（`smem_type=138` 那次分配）在 UEFI 下
   拿不到，任何走 hw version 的 QcomPkg 驱动都可能失败。电源键、触摸大概率都卡在这条线上。
7. **菜单倒计时结束会引导默认条目然后重启**，看起来像"自己重启了"。调试输入时注意这个 1~2 分钟窗口。

## 输入：ButtonsDxe 二进制补丁

[patches/buttons-judyp/apply-buttons-patch.py](patches/buttons-judyp/apply-buttons-patch.py) 把预编译的
`Binaries/judyp/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.efi` 补成 `ButtonsDxe.patched.efi`
（`ButtonsDxe.inf` 里改成引用后者），做的事：

| 地址 | 原值 | 补后 | 作用 |
| --- | --- | --- | --- |
| `0x4934` / `0x4954` | `bl ReadTlmmGpioStatus` | `mov x19,xzr` | 完全不再读 TLMM（CONF0/CONF1 在 judyp 上没接） |
| `0x48dc`/`0x48fc`/`0x491c`/`0x493c`/`0x495c` | `tbnz x19,#0x3f,<err>` | `nop` | 单个脚读失败不再否决全部按键 |
| `0x4938` / `0x4958` | `mov x19,x0` | `mov x19,xzr` | CONF 块恒返回成功（否则会捡到上次遗留的 x0） |
| `0x4930` / `0x4950` | `strb w10/w11,[x20,#2/#3]` | `strb wzr,…` | CONF 槽恒为"未按下"，避免误报按键 |
| `0x42a0` / `0x42a4` | `mov w6,#0x102` @`sp+0x10` | `mov w6,#0x0d` @`sp+0x12` | 该分支改成上报 `UnicodeChar=Enter` |

脚本是幂等的，并且逐字节校验原值；输出与已通过验收的二进制完全一致。

## 仓库结构

```
board.toml                 unixnu 构建驱动读取的板级描述（judyp 与 enchilada 的差异都在这里）
overlay/Mu-Silicium/       覆盖到 Mu-Silicium 检出上的 LG 平台包（judypPkg、judyp.toml、DXE 列表等）
package/                   本仓库的 kit（在构建树里呈现为 kits/judyp）
patches/                   Mu-Silicium / UniXNU / XNU 的补丁
  buttons-judyp/           ButtonsDxe 二进制补丁脚本（本文"输入"一节）
  unixnu-menu/             Menu.c 的"轮询孤立 SimpleTextIn"补丁
scripts/                   工具脚本：pack-boot-img.sh、pad64.py、check-judyp.py 等
m2-dump/ m3/ m4/           各阶段从机子上抓下来的镜像/证据，以及各轮产出的 boot 镜像（*.img 已被忽略）
EXPERIMENTS.md             实验台账（编号 E1…E43，每步先登记再测）
```

上游 enchilada 版 README 的正文可以在 git 历史里找到（本文件替换了它）。

## 复现一份能用的固件

1. 按上文构建 `SILICIUM_UEFI.fd`。
2. 打 Menu 补丁：
   `git -C ~/UniXNU apply ~/UniXNU-judyp-bringup/patches/unixnu-menu/0001-*.patch`（已打过则跳过）。
3. 打 ButtonsDxe 补丁：
   `python3 patches/buttons-judyp/apply-buttons-patch.py ~/Mu-Silicium/Binaries/judyp/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.efi`
   并确认 `ButtonsDxe.inf` 的 `PE32|` 行指向 `ButtonsDxe.patched.efi`；然后重新构建。
4. 打包：
   `scripts/pack-boot-img.sh m2-dump/boot_a.img <FD> m4/boot-judyp.img ~/Mu-Silicium/BootShim/BootShim.S`
5. 手机关机，按住 **音量下 + 电源** 进 bootloader，然后
   `fastboot flash boot_a m4/boot-judyp.img && fastboot set_active a && fastboot reboot`。

## 已知未完成

* 电源键：PON 读取失败（`PollPowerKey` → PON 协议方法返回错误），菜单里按电源键没有事件。
* 触摸：驱动未做；judyp 的 `ftm4` 需要 GENI I2C + FocalTech 协议，现有 enchilada 的 `S3706B` 代码不能直接用。
* hw version / SMEM：`smem_type=138` 分配失败，可能是上面两个问题的共同根因，值得单独查
  （`PlatformInfoDxe` → SMEM）。
* XNU 启动：倒计时结束后引导默认条目会重启，尚未开始调试内核入口。

## 上游与致谢

* [UniXNU](https://github.com/KeyofBlueS/UniXNU) — UEFI 固件构建与运行框架
* [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) — SDM845 的 UEFI 端口（BootShim、SimpleFbDxe、QcomPkg）
* `UniXNU-enchilada-bringup` — OnePlus 6 的移植工作区，本仓库的起点
