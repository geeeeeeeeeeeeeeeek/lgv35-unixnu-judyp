# LG V35 ThinQ (judyp) — M1 实验台账

> 目的：**一切结论以本文件的实测记录为准，不凭记忆**。每条实验记：镜像指纹、刷写方式、结果、判定、是否作废。
> 新增实验必须先在「待测队列」登记编号，测完把结果写回，不允许同一条重复试。
> 镜像头部数据由 `staging/audit-imgs.py` 从磁盘现场解析（非回忆），可随时重跑复核。

---

## 0. 铁律（每次真机实验前后必须做）

1. **先查 retry 再刷**：`slot-retry-count:a` / `slot-unbootable:a`。
   - 每次启动失败会消耗 1 次 retry；到 **0** 时 ABL 把该槽标 `unbootable: yes`，
   - 此时**任何镜像（包括原厂）都返回 `Failed to load/authenticate boot image: Load Error`**。
2. **所有真机实验一律用 slot A（`boot_a` + `set_active a`）**。
   - 依据：系统真正跑在 A 槽（`current-slot=a`，`slot-successful:a` 才是有效槽）；B 槽从未成功启动过（`slot-successful:b=no`）。
   - **E01~E34 全部刷在 boot_b**：B 槽即使镜像完全正确也起不来，因此"能不能进 Android"这类结论在 B 槽上无意义（E34 零改动 round-trip 也回 fastboot 就是这条的代价）。
3. 每次实验前必须 `fastboot set_active a`（把 retry 重置为 7、`unbootable` 清为 no）。
4. 实验只允许用 `m4/autoflash.ps1`（等 fastboot → 刷 → set_active → 监控，单进程，调用间留 1.5s 间隔）或 `m4/m1.ps1`，不要手敲命令。
5. 失败判定窗口 12~14 秒（实测离开 fastboot 最慢 10.5s）；不满足即判 reject，不再空等。
6. **fastboot 独占**：任何时刻只允许一个 fastboot 进程（后台 watcher 与 flash 并发 = `Too many links`，见 C7）。连续快速调用 `getvar` 也会触发，每次调用之间至少间隔 1.5s。
7. **测完立刻回写本文件**：结果一出来就把 E 编号那行写进 §4、把新结论写进 §2/§5.1、把 §6 队列状态改掉。**不允许"先攒着后面一起写"**（E25/E26 就是这么漏掉的）。

---

## 1. 设备事实（fastboot getvar 实测，2026-11-15）

| 项 | 值 |
| --- | --- |
| serial | LMV350NAWMc386b0d5 |
| current-slot | **a**（B 槽耗尽 retry 后 ABL 自动回落到 A；系统实际跑在 A 槽） |
| unlocked | yes |
| boot_a / boot_b | 0x4000000（64 MiB） |
| vbmeta / vbmeta_a / vbmeta_b | 各 0x10000（64 KiB） |
| slot-retry-count（实验前未复位） | a=0, b=0 |
| slot-unbootable | a=yes, b=yes |
| slot-successful | **a=有效槽（系统在跑）**, b=no（从未成功） |
| `set_active <slot>` 后 | retry:<slot>=7，unbootable:<slot>=no |

### 1.1 原始 boot（唯一基线，**用户确认可正常进系统**）

> 文件：`D:\UniXNU-judyp-bringup\m2-dump\boot_a.img`（2026-09-03 dump，67,108,864 B，md5(前8M)=`4522078b0`）
> **这份是"能进系统"的标准答案，任何实验都必须以它为零点做对照。**

| 字段 | 值 |
| --- | --- |
| header | `ANDROID!`，header_version=**1**，page_size=4096 |
| kernel_size | 15,348,215（gzip 容器，`1F 8B 08 00`） |
| kernel_addr / ramdisk_addr / tags_addr | 0x8000 / 0x1000000 / 0x100 |
| ramdisk_size | 16,087,010（gzip） |
| CHECKSUM（id@0x240） | `480745114c23b5d5322549c4fd365f5d529c1425` |
| name 字段 | 空 |
| cmdline | `video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 ehci-hcd.park=3 ...` |
| 解压后内核 | 41,863,188 B；code0=0x147e0000；text_offset=**0x80000**；image_size=0x2e3c000；flags=0xa；`ARMd` |
| 内核身份 | **LG 原厂**：`Linux version 4.9.193-perf (lgmobile@MCSBS10R32) ... #2 SMP PREEMPT`，路径 `judyp_lao_com_kr_qos_daily_user_508463` |
| ramdisk 身份 | **TWRP + Magisk 双补丁**（实测：`twrp`×402、`TWRP`×465、`sbin/`×513、`magiskinit`、`overlay.d`×10、`.magisk`×65；首条 cpio 条目即 `overlay.d/sbin/magisk32.xz`/`magisk64.xz`）。解压后 46,447,140 B |
| KERNEL_DTB | 1,241,154 B（v1 独立段，紧跟 gzip 流之后） |
| 64 MiB 尾部 | 全 0（**没有 AVB footer**） |

> 反例（**不要当原厂**）：`los-parts/output/boot.img` 内核是 `4.9.337-perf+ (root@ddfb22d4d7b6) #1 SMP PREEMPT Thu Aug 27 2026` —— 自编译 LOS 内核，且带 `AVBf` 尾。

---

## 2. 机制结论（有实验支撑）

| # | 结论 | 证据 |
| --- | --- | --- |
| C1 | **retry=0 / unbootable=yes 是「所有镜像都 Load Error」的唯一原因**，与镜像内容、vbmeta、header 版本无关 | E09 → E10 对照：只执行 `set_active b`（未动任何镜像/vbmeta），原厂镜像立刻恢复启动 |
| C2 | 之前所有 `Load Error` 实验**全部作废**，必须重测 | E04~E08 均在 slot 已 unbootable 期间进行，无法与 C1 区分 |
| C3 | **vbmeta_b 不是阻塞点**，此前「刷 LOS vbmeta 破坏校验链」的推断被证伪 | same as C1 |
| C4 | LG ABL 实际刷写回路（flashlm 项目验证过、本项目也部分复现）：`flash boot_b` → `set_active b` → `reboot` | flashlm HANDOVER §2；E02/E03 |
| C5 | ~~带 stock 大 ramdisk 的自定义镜像会被接受并执行~~ **已作废**：实测就是 2.3s 复位，E02/E03 的"卡 logo 30s"是目视误差 | E26 复核（同一文件、精确计时） |
| C6 | `fastboot boot` 与 flash+reboot 走同一套接受判定（原厂镜像两条路都通） | E01、E10 |
| C7 | `Write to device failed (Too many links)` 的真实原因 = **同时有多个 fastboot 进程访问同一设备**（后台 watcher 与 flash 并发轮询 `fastboot devices`）。不是镜像/线材问题。**任何时刻只允许一个 fastboot 进程** | E14（用户指出并硬复位） |

---

## 3. 镜像清单（磁盘实测，`staging/audit-imgs.py`）

> md5 列对 >8 MiB 的文件只算了**前 8 MiB**（标 `*`），用于判定「前 8 MiB 完全相同 = 实质重复」。

| 镜像 | 大小 | md5(前8M) | hv | kernel | ramdisk | kernel 编码 | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| m2-dump/boot_a.img（原厂基线） | 67108864 | 4522078b0* | 1 | 15348215 | 16087010 | gzip | **能启动**（E01/E10） |
| m4/boot-m1-v0.img（**本轮新建**） | 67108864 | 4e790e01d* | 0 | 3700778 | 0 | **raw** shim+FD+dtb | 照 flashlm 基线风格，无 ramdisk |
| m4/boot-stockkernel-ours.img | 67108864 | 4e790e01d* | 1 | 15348215 | 16087010 | **raw**(塞在 stock 头) | kernel 段=payload-raw |
| m4/boot-judyp-64m.img | 67108864 | c27957305* | 0 | 1665162 | 0 | gzip | **unixnu bootimg 官方产物**填到 64 MiB |
| m4/boot-judyp-64.img | 67108864 | 3f8665a4b* | 1 | 1667072 | 16087010 | gzip | 与 stocklike 前 8M 相同 |
| m4/boot-judyp-stocklike.img | 17760256 | 3f8665a4b* | 1 | 1667072 | 16087010 | gzip | 上者的小尺寸版（实质重复） |
| m4/boot-judyp-raw.img | 19795968 | d88a870ce* | 1 | 3700778 | 16087010 | raw shim | 带 stock ramdisk 的 raw 版 |
| m4/boot-tamper1.img | 67108864 | 4522078b0* | 1 | 15348215 | 16087010 | gzip | stock 的 padding 单字节改 0xA5（在 8 MiB 之后） |
| m4/boot-gzloop.img | 67108864 | 520d4a748* | 1 | 57 | 16087010 | gzip | gzip(4 KiB 死循环 ARM64) |
| m4/boot-loop-stocklike.img | 16097280 | d8a653bfb* | 1 | 4096 | 16087010 | raw 死循环 | |
| m4/boot-loop.img / loop2 | 67108864 | 366a3a5b7*/4ee1dd5d0* | 0 | 67/75 | 0 | gzip | 极小镜像，探「最小可接受集」 |
| m4/boot-paint*.img | — | — | 0 | 101/1241255 | 0/16087010 | gzip | 早期填色探针 |
| los-parts/output/boot.img | 67108864 | 534270c1d* | 0 | 16189535 | 16643992 | gzip | LOS，rs=0xfdf798 |
| m3/boot-exp2 / exp3 | 18386944 | 47802143e* | 0 | 1736606 | 16643992 | gzip | **两张完全相同** |
| m3/boot-exp6 | 67108864 | 374821fb2* | 0 | 15000000 | 16643992 | gzip | |
| m3/boot.img / boot-v1.img | 1.7 MB | cd968c585/f6d30b01e | 0/1 | 1736606 | 0/1 | gzip | 极小版 |
| m4/boot-a1~a4, boot-uefi-big, boot-bigloop, boot-ctl-loop, boot-hang-stock, boot-paint-stock, boot-los-nofooter | 见脚本输出 | — | 0/1 | 多种 | 多为 stock ramdisk | gzip | 早期批量尝试，结果同 E02/E03/E04 |

---

## 4. 实验矩阵

判据：**离开 fastboot 且 12s 内不回来 = 被接受**；出现 `FAILED … Load Error` 或 12s 内回到 fastboot = 被拒。

| 编号 | 时间 | 镜像 | 方式 | 结果 | 判定 |
| --- | --- | --- | --- | --- | --- |
| E01 | 11-14 | m2-dump/boot_a.img（原厂） | `fastboot boot` | t=2.7s 离开 fastboot，20s 未回 | **PASS**（基线：原厂可启动） |
| E02 | 11-14 | boot-judyp-64.img（hv1+gzip+stock ramdisk） | flash boot_b → set_active b → reboot | 卡 logo ~30s → 黑屏 → 反复重启 | **接受并执行**，但 UEFI 未上屏（C5） |
| E03 | 11-14 | boot-judyp-stocklike.img（同上，小尺寸） | 同上 | 同上 | 同 E02 |
| E04 | 11-14~15 | boot-judyp-stocklike / boot-uefi-big / exp2/3/6 / a1~a4 等 | `fastboot boot` | `FAILED Load Error`，从未离开 fastboot | **作废**（C1/C2） |
| E05 | 11-15 | boot-tamper1.img（padding 单字节 0xA5） | `fastboot boot` | `FAILED Load Error` | **作废**（C1/C2） |
| E06 | 11-15 | los-parts/output/boot.img | `fastboot boot` | `FAILED Load Error` | **作废**（C1/C2） |
| E07 | 11-15 | boot-gzloop.img（gzip 4 KiB 合法 ARM64 死循环） | `fastboot boot` | `FAILED Load Error` | **作废**（C1/C2） |
| E08 | 11-15 | boot-loop.img / boot-loop2.img / boot-paint*.img | `fastboot boot` | `FAILED Load Error` | **作废**（C1/C2） |
| E09 | 11-15 | LOS vbmeta（4096B，flags=0x3）刷 vbmeta_b | flash vbmeta_b | 之后原厂 boot 也 `Load Error`，当时判为「vbmeta 破坏校验链」 | **推论已否定**（见 E10） |
| E10 | 11-15 | m2-dump/boot_a.img（原厂） | 仅 `set_active b` 后 `fastboot boot` | retry:b 0→7、unbootable yes→no；t=10.5s 离开 fastboot | **PASS → 定案 C1** |
| E11 | 11-15 | m4/boot-judyp-64m.img（官方产物 hv0/gzip/无 ramdisk） | `m1.ps1 -Mode boot`（先 set_active b） | ABL 回 `Booting OKAY`（**不是** Load Error），但设备**始终未离开 fastboot**；之后 `getvar` 立即应答，retry:b 仍=7 | 半结论：`fastboot boot` 命令被接受、但未观察到跳转；retry 未消耗，~~判为"被拒"~~ **不成立**，与 E13 结果不一致，待复核采样精度 |
| E12 | — | （未执行，被 E13 取代） | — | — | 跳过 |
| E13 | 11-15 | m4/boot-judyp-64m.img（同上） | `flash boot_b` → `set_active b` → `reboot` | flash OK → t=4.6s 离开 fastboot → **t=6.9s 自己回到 fastboot**，retry 7→6 | **关键**：镜像被接受**并执行**，约 2.3s 内失败返回（不再是接受性问题） |
| E15 | 11-15 | m4/boot-paint-red.img（32B ARM64 stub＝画红屏 2MiB@0x9D400000 后 wfe 死循环，gzip，hv0，无 ramdisk） | `flash boot_b` → `set_active b` → `reboot` | 离开 t=4.7s，**t=7.0s 回 fastboot**（2.3s） | 连死循环 stub 都活不过 2.3s；但该 stub 无 ARM64 Image 头，ABL 可能直接不跳转，**不能单独定论** |
| E16 | 11-15 | m4/boot-stockk-nord.img（**原厂内核 + 无 ramdisk**，hv0，对照组） | 同上 | 离开 t=4.7s → **38.9s 仍未回 fastboot**，之后回退时 retry 已到 0 | **对照确立**：ABL 加载/跳转/无 ramdisk 全部正常；2.3s 死是我们 payload 自己的问题 |
| E17 | 11-15 | m4/boot-judyp-64m.img（真 M1 目标镜像） | 同上 | 离开 t=4.7s，t=7.0s 回（2.3s），retry 7→6 | 与 E13 完全一致，可复现 |
| E18 | 11-15 | m4/boot-shimstub.img（**shim(192B, 合法 ARM64 头, text_offset=0x9FC00000, image_size=0x10c0) + 4KiB 画屏 stub**） | 同上 | 离开 t=4.7s，t=7.0s 回（2.3s） | shim/FD_BASE/跳转链路本身不背锅（至少不是唯一原因） |
| E19 | 11-15 | m4/boot-shim-nop.img（同上，但 stub 只 `b .` 空转，**不写 framebuffer**） | 同上 | 离开 t=4.7s，t=7.0s 回（2.3s） | **写 framebuffer 不是原因** |
| E20 | 11-15 | m4/boot-e20-toff.img（同上，但把 ARM64 头 `text_offset` 改成与原厂内核一致 = 0x80000；实测原厂内核解压后 text_offset=0x80000、image_size=0x2e3c000） | 同上 | 离开 t=4.6s，t=6.9s 回（2.3s） | **text_offset 不是原因** |
| E21 | 11-15 | m4/boot-e21-trap.img（stub 先装 Exception Vector（按 CurrentEL 设 VBAR_EL1/2/3，16×128B 全 `b .`）→ 画 8MiB 红屏 → wfe 自旋） | 同上 | 离开 t=4.6s，t=6.9s 回（2.3s） | 复位**不是异常**（若是异常会被自旋接住）；仍不能区分「看门狗咬」与「ABL 根本没跳转」 |
| E22a | 11-15 | m4/boot-e22a.img（shim + stub：立即 `smc` PSCI SYSTEM_RESET） | 同上 | 离开 t=4.6s，**t=7.0s 回** | 基准：`reboot` 后固定 4.6s 才真正复位，复位到 fastboot 约 2.3s |
| E22b | 11-15 | m4/boot-e22b.img（同上，但先空转 0x20000000 次≈0.3s 再复位） | 同上 | t=7.0s（与 E22a 相同） | 延迟太小，低于采样精度，**无结论** |
| E24 | 11-15 | m4/boot-e24-longreset.img（同上，空转 0x400000000 次≈9s 再复位） | 同上 | **仍 t=7.0s 回** | 若代码拿到过 CPU，返回必然 ≥9s；因此我们的入口**没有得到执行时间** |
| E23 | 11-15 | m4/boot-tamper1.img（**原厂镜像，仅 padding 里 1 字节改 0xA5**） | 同上 | 离开 t=4.7s，**27.6s 仍未回**，最终跑完 retry 回 fastboot | **ABL 在解锁状态下不校验 boot 镜像内容** → 「我们的镜像被拒」这条线彻底排除 |
| E26 | 11-15 | m4/boot-e26-stocklike.img（**stock 头 hv1 + stock ramdisk 16,087,010 + 我们的 gzip payload 1,667,072**；md5 前 8M = `3f8665a4b`，**与 boot-judyp-64 / boot-judyp-stocklike 完全同一文件**） | 同上 | 离开 t=4.7s，**t=7.0s 回（2.3s）**，retry 7→6 | **复核 E02/E03**：那次"卡 logo ~30s 才黑屏重启"是目视误差，实测就是 2.3s 复位。C5 因此**作废**（stock 头+大 ramdisk 并不能让我们的 payload 活下来） |
| E25 | 11-15 | m4/boot-e25-big.img（shim + 空转 stub，**填充到 16 MiB**，`image_size=0x1000000`、`text_offset=0x80000`，gzip 后 kernel=16,493 B） | 同上 | 离开 t=4.7s，**t=6.9s 回（2.3s）**，retry 7→6 | **「ABL 只跳到尺寸合理的内核」假设排除**（原厂 `image_size=0x2e3c000`≈46 MiB，我们已到 16 MiB 仍死） |
| E27 | 11-15 | m4/boot-e27-stockspin.img（**原厂内核解压后仅把偏移 0 的 `b +0x1f8000` 改成 `b .`**，重新 gzip，**无 appended DTB**，hv0 无 ramdisk，kernel=14,107,062） | 同上 | 离开 t=4.7s，**t=7.5s 回（2.8s）** | 入口改死循环也没能"活下来"；但也移除了 DTB，两变量同时变了 → 不能单独定论 |
| E28 | 11-15 | m4/boot-e28-spin-dtb.img（同 E27 的 `b .` 入口，**把原厂 1,241,154 B 的 appended DTB 原样接在 gzip 流之后**，kernel=15,348,204，几乎等于原厂 `kernel_size`） | 同上 | 离开 t=4.7s，**t=7.1s 回（2.4s）** | DTB 加回来也不救；`b .` 仍未被执行（或执行后被 2.3s 咬） |
| E28b | 11-15 | m4/boot-e28b-recomp-dtb.img | 同上 | t=7.0s 回（2.4s） | **实验作废**：我用 `zlib.compress()` 生成的是 **zlib 容器（78 DA）而不是 gzip（1F 8B）**，ABL 必然解不开。结论 C19 撤回 |
| E30 | 11-15 | m4/boot-e30-magiskstyle.img（**stock 镜像一字不动，只把 kernel 段换成"同内容 + 同 DTB"的重压版"**；hv1、stock cmdline、stock ramdisk 全保留，仅 `kernel_size` 15,348,215→15,348,203） | 同上 | t=7.0s 回（2.3s） | 同样**作废**（同 zlib 容器 bug）；用真 gzip 重做为 **E30b** |
| E29a | 11-15 | m4/boot-m1-v0.img（**raw 不压缩** shim+FD+DTB，3,700,778） | 同上 | 离开 t=4.7s，t=7.0s 回（2.3s） | ABL 不吃 raw kernel 段（原厂是 gzip）→ 保留 gzip 编码这一约束成立 |
| E29b | 11-15 | m4/boot-e29b-rawstock.img（原厂内核 raw 41,863,188 + 原厂 DTB，hv0 无 ramdisk） | 同上 | 离开 t=4.8s，t=7.1s 回（2.3s） | 连"内容完全正确的 raw 内核"也死 → **raw 路线关闭**，必须用 gzip |
| **E30b** | 11-15 | m4/boot-e30b-gz-stocklike.img（同 E30，但用 **`gzip.compress()` 真 gzip 容器**；`kernel_size` 与 stock **完全相同 15,348,215**，stock hv1 头/cmdline/ramdisk 全保留） | 同上 | 离开 t=4.7s，**t=56.6s 仍未回**（retry 最终 0） | **PASS**：重新压缩无害。**唯一可用外壳 = `repack-stocklike.py` + 真 gzip**（此后所有镜像都用它） |
| E34 | 11-15 | m4/boot-e34-roundtrip.img（**magiskboot unpack → 原样 repack，零改动**，`KERNEL_SZ`/`CHECKSUM` 与原厂完全一致） | **boot_b** + `set_active b` | 离开 t=0.1s，90s 内未回，`retry:b` 7→5 | 因 **B 槽本身不可用**（C24）无法判定 ⇒ **改为在 A 槽复测**（E34a） |
| E34a | 11-15 | 同上（零改动 round-trip） | **boot_a** + `set_active a` | **md5 与原始 boot 完全相同**（`b6ac9449...`），故等价于刷原文件；原始 boot 本身可进系统（用户确认） | 步骤 1 通过：magiskboot 打包链路无损 |
| **E35** | 11-15 | m4/boot-e33-magiskboot.img（magiskboot 打包，kernel = ARM64头(`code0=b +0x80000`, `text_offset=0x80000`, `image_size=0x38c000`) + 0x80000 全零 + shim 192 + **旧 FD**；kernel_dtb/ramdisk 与原厂 md5 一致） | **boot_a** + `set_active a` | 离开 t=0.1s；脚本记到 91.6s 回 fastboot，**实为用户手动送进 BL**（C28），真实行为=**卡 LG logo → 自己重启循环** | **失败**。"存活 91.6s" 结论作废；屏幕全程 LG logo ⇒ 我们的 payload 没接管显示 |
| **E36** | 11-15 | m4/boot-e36-display.img（与 E35 完全同配方，唯一差别：**FD 用 `USE_CUSTOM_DISPLAY_DRIVER=1` 重建**，`FV/Ffs` 含 `DisplayDxe`/`DisplayReEnablerDxe`/`CPRDxe`） | **boot_a** + `set_active a` | 离开 t=0.1s；脚本记到 83.6s，**同样是用户手动进 BL**（C28）。屏上**全程静态 LG logo** | **失败**。加 DisplayDxe 也没出画 ⇒ 问题不在"有没有显示驱动"，而在**我们的代码是否真的被执行**（待 E37 判定） |
| **E37** | 11-15 | m4/boot-e37-reset8.img（kernel 段 = 头 + 0x80000 零 + **8B stub：立刻 PSCI 复位**） | — | **未刷**（用户叫停，改用 E38，因为"立刻复位"与 ABL 自身 1~3s 失败无法区分） | 作废 |
| **E38** | 11-15 | m4/boot-e38-delay15.img（kernel 段 = 头 + 0x80000 零 + **48B stub：读 `cntfrq_el0`/`cntpct_el0` 等 15s 再 PSCI 复位**） | **boot_a** + `set_active a` | **重启周期从 1~3s 变成 15s**（用户实测） | **决定性 PASS：ABL 确实跳到 0x80000 并执行了我们的代码**（C29）。此前所有"我们代码没跑"的猜测全部作废 |
| **E39** | 11-15 | m4/boot-e39-fixshim.img（**shim 重编为 `FD_SIZE=0x300000`**，其余同 E36：头 + 0x80000 零 + shim 192 + 3MiB FD，magiskboot 打包，ramdisk/kernel_dtb 原样） | **boot_a** + `set_active a` | 屏幕上**出现 Mu-Silicium/UEFI 的滚动文本输出**（用户："直接开始刷代码行了，看起来像是 UniXNU 那套"） | **PASS —— M1 的关键突破：UEFI 已接管屏幕并运行** |
| **E40** | 11-15 | m4/boot-e40-simplefb.img（与 E39 完全相同，唯一差别：FD 用 **`USE_CUSTOM_DISPLAY_DRIVER=0`（SimpleFbDxe）** 重建） | **boot_a** + `set_active a` | **刷 ~20s 文本 → 进入 UniXNU 菜单**（用户确认）。但**触摸无反应、音量键/电源键也无法操作** | **PASS —— M1 验收达成（UEFI 菜单出现在屏幕上）**。⇒ 显示路线选 `SimpleFbDxe`（`USE_CUSTOM_DISPLAY_DRIVER=0`），`DisplayDxe`（=1）会导致 ~20s 后黑屏 |
| E32 | 11-15 | m4/boot-e32-m1.img（repack-stocklike 外壳 + `gzip(ARM64 头 text_offset=0x80000/code0=`b +0x80000` + 0x80000 全零 + shim 192 + FD 3,145,728 + 原厂 DTB)`） | 同上 | **被用户中断，结果未知** | 不再单独重刷，由 E35 用 magiskboot 重做同一形态 |
| E33 | 11-15 | m4/boot-e33-magiskboot.img（**第一次用 magiskboot 打包**：kernel=头+pad+shim+FD，`kernel_dtb`/ramdisk 全原厂，CHECKSUM 重算为 `1e7e6c94...`） | 同上 | **未刷（用户叫停，改走分步）** | 保留，作为 E35 的素材 |
| **E41** | 11-15 | m4/boot-e41-input.img（E40 同配方，唯一差别：**UniXNU `Menu.c` 直接轮询所有无 device path 的 SimpleTextIn 实例**，并在 Info 行显示 `in 总数/带路径数 orph 孤立数`、按键时在状态行回显 `key: scan/ch`） | **boot_a** + `set_active a` | **已刷，失败**：按键菜单无反应；同时屏幕出现大量 `SMEM allocation failed! smem_type=138, buf_size=128`（把 UI 盖住，Info 行看不清） | 该报错只在按键/轮询时出现；已定位到 `ButtonsDxe` 的 `PollButtonArray`，见 E42 |
| **E42** | 11-15 | 同上配方 + **二进制补丁 `Binaries/judyp/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.patched.efi`**：`0x4934`/`0x4954` 两条 `bl ReadTlmmGpioStatus`（CONF0=TLMM75 / CONF1=TLMM76）改成 `mov x19,xzr`（等价于"当成没按下"），使 TLMM 读失败不再中断整个按键轮询 | **boot_a** + `set_active a` | **已刷，失败**：`SMEM allocation failed!` 刷屏消失，但变成持续刷 `ButtonsDxe - PollButtonKeys failed status:0x...`，菜单仍无按键，1~2 分钟后倒计时结束自动重启 | PON 读（`PollPowerKey`）仍失败，任一步失败即丢弃全部按键；见 E43 |
| **E43** | 11-15 | 同上 + **把 `PollButtonArray` 里 5 条失败分支全部 NOP**（`0x48dc/0x48fc/0x491c/0x493c/0x495c` 的 `tbnz x19,#0x3f,<err>` → `1f2003d5`），并把 CONF0/CONF1 两个块固定为"成功且未按下"（`0x4938/0x4958`→`mov x19,xzr`，`0x4930/0x4950` 写入 0） | **boot_a** + `set_active a` | **已刷，部分可用（验收）**：`PollButtonKeys failed` 刷屏彻底消失；音量上/下可以操作菜单（用户："算是勉强可用了"）。电源键仍无反应（PON 读失败被 NOP 掉，既不出键也不报错）；触摸仍不可用 | 按键这条线到此可收工；下一步只剩触摸（E44）|



---

## 5. 已排除的假设（不要再试）

1. ~~header_version 1 vs 0~~：原厂是 hv1，flashlm 验证版是 hv0，两条路都能被接受（E02 vs 官方产物）。
2. ~~ramdisk 有无~~：带 stock ramdisk 的镜像被接受并执行（E02/E03）。
3. ~~镜像总尺寸 64 MiB 填零~~：E02/E03 都是 64 MiB 填零，被接受。
4. ~~gzip vs raw kernel~~：E02 是 gzip；boot-stockkernel-ours 是 raw，两者都未在「slot 正常」状态下测过 boot 接受性 —— **raw 版仍需在 C1 修复后重测**（见待测 P2）。
5. ~~vbmeta_b 被改坏~~：已证伪（C3）。
6. ~~`fastboot reboot` 不启动~~：已证伪（E01/E10 都能启动）。
7. ~~DTB 追加导致拒绝~~：E02 带 dtb（在 gzip 内）也被接受。
8. ~~BootShim 的 192B shim / 跳到 FD_BASE=0x9FC00000 这条链~~：E18（shim+4KiB stub，头合法）同样 2.3s。
9. ~~写 framebuffer 0x9D400000 触发总线错误~~：E19（纯空转 stub）2.3s 与 E18 一致。
10. ~~ARM64 头 `text_offset` 不对（0x9FC00000 vs 原厂 0x80000）~~：E20 改成原厂值仍 2.3s。
11. ~~异常/未定义指令导致复位~~：E21 装了 Exception Vector + 自旋，仍是 2.3s（异常会被接住）。
12. ~~ABL 在解锁状态下校验 boot 镜像内容~~：E23（原厂镜像改 1 字节）照常启动 27.6s。
13. ~~内核对齐后的尺寸/image_size 阈值（ABL 只跳"尺寸合理"的内核）~~：E25 填到 16 MiB、`image_size=0x1000000` 仍 2.3s。
14. ~~hv1 头 + stock ramdisk 包装能让我们的 payload 活下来~~：E26（同一文件复核 E02/E03）实测 2.3s。
15. ~~BootShim 入口没拿到 CPU（延迟 9s 自复位仍 7.0s 返回）~~ 已由 E24 证实为"没执行"，**不作为可再试项**，见 §5.1 C13。

## 5.1 新主线（E15~E26 共同指向）

| # | 结论 | 证据 |
| --- | --- | --- |
| C8 | 复位时间恒定 **2.3s**，与 payload 内容（gzip 1.6MB / 4KiB / 32B）无关；而**原厂内核可存活 38.9s** | E13/E15~E21 vs E16 |
| C9 | 已排除：镜像形态、shim、FD_BASE、framebuffer、text_offset、异常 | E18~E21 |
| C10 | 剩余两个可能，二者无法用时间区分：**(a) ABL/XBL 的看门狗在 ~2s 咬合**（原厂 Linux 内核会在开头几毫秒 disarm）；**(b) ABL 根本没跳到我们的入口** | E21 |
| C11 | 设备本身健康：ABL 能加载、能跳转、能跑原厂内核；`set_active` 能把 retry 复位 | E16/E10 |
| C12 | **ABL 在 unlocked 状态下不校验 boot 镜像内容**（原厂镜像改 1 字节仍正常启动） | E23 |
| C13 | 我们的入口**没有拿到 CPU 时间**：stub 自带 9 秒延迟 + PSCI 自复位，设备仍按 2.3s 基准返回 | E24 vs E22a |
| C14 | 综合 C12+C13：ABL 接受写入、不校验内容，但**没有跳到我们的入口**（或跳转地址不对）。差异只剩「解压后内核的形态」（原厂 46MB 有效 ARM64 Image vs 我们的小 blob） | E16 / E23 / E24 |
| C15 | 「尺寸/形态阈值」这一条**也不能简单成立**：填到 16 MiB（原厂约 46 MiB）照样 2.3s。所以不是"太小"，要么阈值正好在原厂那一档，要么与尺寸无关 | E25 |
| C16 | hv1 头 + stock ramdisk 包装同样无效 → **问题只在 kernel 段被解压后的内容**，与 boot image 容器、ramdisk、cmdline 无关 | E26 |
| C17 | 关键结构性事实（`audit-imgs.py` 实测）：原厂与我们的镜像 **`kernel_addr=0x8000`、`tags_addr=0x100`、`page_size=4096` 全部一致**，唯一差别是 kernel 段字节。因此"头部字段不同"这条也无剩余解释空间 | 审计输出 |
| C18 | 原厂 kernel 段内部结构 = **`gzip(41,863,188 B 的 ARM64 Image)` + `1,241,154 B 的 appended DTB`**（DTB 在 gzip 流**外面**，3 段 FDT，首段 magic `d00dfeed`、totalsize 415,074）。ARM64 头实测：`code0=0x147e0000`（`b +0x1f8000`）、`text_offset=0x80000`、`image_size=0x2e3c000`、`flags=0xa` | `inspect-tail.py` |
| ~~C19~~ | **已撤回**。曾判"ABL 对 gzip 字节流敏感"，实际是我用 `zlib.compress()` 生成了 **zlib 容器（78 DA）而非 gzip（1F 8B）**，ABL 无法解压。工具 bug，不是设备行为 | E28b/E30 作废 |
| C20 | **kernel 段必须是 gzip 容器**（raw 一律 2.3s 死，内容再正确也不行） | E29a / E29b |
| C22 | **可用外壳确定**：`repack-stocklike.py`（stock 头/ hv1 / cmdline / ramdisk 全保留）+ **真 gzip** kernel 段（后面接原厂 appended DTB）是唯一被实测接受且能长时间存活的构造方式 | E30b |
| **C23** | **我们所有 payload 都有一个共同的、从未修正过的构造错误**：ARM64 头里 `text_offset` 写的是 `0x9FC00000`（E18）或 `0x80000`（E20/E25），但**真正的代码一直放在文件偏移 0**。若 ABL 跳到 `load_base + text_offset`，我们每一次都跳进了 padding/空白内存 → 2.3s 异常复位。**「代码放在 0x80000 / 或 text_offset 写 0」这两个组合，一次都没测过** | E18/E20/E25 构造 + E31 证明入口确实被执行 |
| **C24** | **E01~E34 全部刷在 slot B，而 B 槽 `slot-successful=no`、系统实际跑在 A 槽** ⇒ 任何"能不能进 Android"的判定在 B 槽上都不可信（E34 零改动 round-trip 失败即为代价）。**此后所有真机实验改用 `boot_a` + `set_active a`** | `getvar current-slot=a` / `slot-successful:b=no`；E34 |
| **C25** | **「能进系统」的基线 = `m2-dump/boot_a.img`**（用户确认）：LG 原厂内核 `4.9.193-perf lgmobile@MCSBS10R32` + **Magisk 修补过的 ramdisk** + v1 头 + CHECKSUM `480745114c23...`，无 AVB 尾。它不是"纯净原厂"，但它是**唯一已知能进系统的镜像** | 用户确认 + §1.1 |

| **C26** | **基线镜像是「LG 原厂内核 + TWRP&Magisk ramdisk」**，对它做"二次处理"无风险：magiskboot `unpack → repack` 的产物与原文件 **md5 完全相同**（`b6ac9449...`），即无损且幂等；我们只换 kernel 段，ramdisk/`kernel_dtb` 原样搬运，Magisk 补丁不会被重复应用 | `md5sum` 三方一致 + `ramdisk-what.py` |

| **C27** | **屏幕不亮的直接原因：judyp 编进的是 `SimpleFbDxe`，不是真正的显示驱动**。`judyp.dsc` 里 `USE_CUSTOM_DISPLAY_DRIVER = 0` → `DXE.inc` 走 `!else` 分支只加 `SiliciumPkg/Drivers/SimpleFbDxe`（依赖 bootloader 已初始化好的 framebuffer）；而**能正常出画面的 enchilada 用的是 `= 1`** → `DisplayDxe + DisplayReEnablerDxe`（真初始化 MDSS）。judyp 的 `Binaries/judyp/QcomPkg/Drivers/{DisplayDxe,CPRDxe}` 二进制**都存在** → 已改为 `= 1` 重建，新 FD 的 `FV/Ffs` 里确认含 `DisplayDxe`/`DisplayReEnablerDxe`/`CPRDxe` | `judyp.dsc:26` vs `enchilada.dsc:26`；`DXE.inc:58-63`；`FV/Ffs` 目录 |

| **C28** | **"多久回 fastboot"不能作为判据**：A 槽启动失败时设备会**卡 LG logo 然后自己重启循环，可能好几分钟才回落 B 槽/进 BL**；若中途有人手动送进 BL，脚本会把它误记成"存活了 83/91 秒"。E35/E36 的 91.6s/83.6s **全是这个误判**，真实行为都是"卡 logo → 重启循环"。→ **此后判据改为：屏上是否出画 + 复位循环周期（用 USB 枚举节奏客观测量）**，并明确记录"是否有人手动介入" | 用户反馈（11-15）："83 秒，是因为第一次重启，我就手动刷 boot 进 bl 了" |

| **C29** | **ABL 会跳到 `load_base + text_offset` 执行我们的代码**——这是本轮最重要的事实。证据：E38 用 48B「等 15s 再 PSCI 复位」stub 放在 0x80000，重启周期由 1~3s 变成 **15s**。⇒ kernel 段布局（ARM64 头 + `text_offset=0x80000` + 代码在 0x80000）**完全正确**，问题只在「代码跑起来之后」。同时说明 E35/E36 的 1~3s 复位发生在 **BootShim 拷完 FD 之后、FD 内部极早期** | E38 周期 15s |

| **C30** | **真正的根因：`BootShim` 编译时 `FD_SIZE=4096`**。`BootShim.S:24-30` 的 `_CopyLoop` 只搬 `FD_SIZE` 字节到 `FD_BASE`，所以 E35/E36 每次都只把 **4 KiB** 的 FD 拷到 0x9FC00000 然后 `br x5` 跳进去 → 秒级复位。重编为 `FD_SIZE=0x300000`（E39）后，UEFI 立刻在屏幕上跑起来。**以后任何 shim 都必须与 FD 实际尺寸一致（judyp = 0x300000）** | E39 屏幕出字；`BootShim.S:19-55` |

### §5.2 magiskboot 事实（来自真机 Magisk v20.4 产物，`x86/magiskboot` 可在 WSL 直接跑）

> 来源：`E:\BaiduNetdiskDownload\Magisk-V20.4(20415).zip`（百度网盘未下完，但 `x86/magiskboot`、`boot_patch.sh`、`util_functions.sh` 三个关键条目完整）
> 已解出 `/root/magisk204/{magiskboot, boot_patch.sh, util_functions.sh}`

- `magiskboot unpack boot_a.img` 实测输出：`kernel`=41,863,188（**已解压**）、**`kernel_dtb`=1,241,154**、`ramdisk.cpio`=46,447,140
  → 原厂那 1.24 MB 尾巴在 v1 头里是**独立的 `kernel_dtb` 段**，不是"内核尾部垃圾"
- 头里带 **`CHECKSUM`（id 字段，SHA1）**= `480745114c23b5d5322549c4fd365f5d529c14250000...`，`repack` 时 magiskboot 会**重算**
- 原厂 `HEADER_VER=1`、`PAGESIZE=4096`、`KERNEL_FMT=gzip`、`RAMDISK_FMT=gzip`
- `boot_patch.sh` 真实流程：`unpack` → `cpio` 改 ramdisk（塞 magiskinit）→ `dtb patch`（改 fstab）→ `hexpatch kernel`（**只有 3 个固定模式：Samsung RKP / Samsung defex / `skip_initramfs`→`want_initramfs`；LG 上通常一个都不命中**）→ `repack <原镜像>`
- ⇒ **Magisk 在非三星机上根本不改 kernel 内容**，只做"原样重压 + 改 ramdisk"，这就是它能启动的原因
- 空改动 round-trip 后 `KERNEL_SZ`(15,348,215) 与 `CHECKSUM` 与原厂**完全一致** ⇒ magiskboot 的重压字节与 LG 原始字节相同（也印证 E30b 的 56s 存活）

---

## 6. 待测队列（按序，不跳号、不重复）

> **状态（11-15）：M1 已达成** —— E40 进入 UniXNU 菜单。原"只有原厂 kernel 能让设备活下来"的阻塞点是误判，真因是 shim `FD_SIZE=4096`（C30）。
> 下一步是**输入**（触摸/按键都无响应），不是刷机接受性。

| 编号 | 镜像/改动 | 目的 | 状态 |
| --- | --- | --- | --- |
| **E41** | `Menu.c` 改为**直接轮询所有"无 device path"的 SimpleTextIn 实例**（ConSplitter 看不到这些），Info 行显示 `in 总数/带路径数 orph 孤立数` | 让音量键能上下选菜单项；同时给出 ButtonsDxe 是否装上的证据 | **已刷，失败**（见 §4 E41） |
| **E42** | 二进制补丁：`0x4934/0x4954` 的 TLMM 读改成"未按下" | 消除 SMEM 刷屏 | **已刷，失败**：改成 `PollButtonKeys failed` 刷屏 |
| **E43** | 五个失败分支全 NOP + CONF 块固定"成功未按下" | 让单个脚读失败不再丢弃全部按键；区分"只有 PON 坏"还是"整个键表没初始化" | **已刷，音量键可用**（电源键仍无） |
| E44 | 触摸输入（judyp 的触控 IC 驱动是否存在于 `Binaries/judyp`） | 菜单可用触摸 | 待 E43 |

### 输入问题的已知事实（11-15）
- UniXNU 菜单读 **`gST->ConIn`**（`Menu.c:205/437/452`，支持 `SCAN_UP` 与字符 `k`），并会枚举所有 `gEfiSimpleTextInProtocolGuid` 实例（`Menu.c:44`）。
- judyp 的 `APRIORI.inc:78` 与 `DXE.inc:66` **都已包含** `Binaries/judyp/QcomPkg/Drivers/ButtonsDxe/ButtonsDxe.inf`；`PlatformInfoDxe` 也在（`APRIORI.inc:20`）。
- **反汇编结论（11-15，`ButtonsDxe.patched.efi`）**：
  - 它在 `EfiEntry(ImageHandle)` 里用 `InstallMultipleProtocolInterfaces` 把 **`EFI_SIMPLE_TEXT_INPUT_PROTOCOL`** 装到 **自己的 ImageHandle** 上（反汇编 `0x2e9c str x0,[sp,#0x10]` → `0x2f78 ldr x13,[x14,#0x148]`），并 `CreateEvent` 出 `WaitForKey`（写入协议结构 `+0x10`）。**所以驱动本身会提供 SimpleTextIn**。
  - 它的 `.depex` 实际内容：`SimpleTextIn AND 157a5c45-21b2-43c5-ba7c-822fee5fe599(PlatformInfo) AND 60759b13-a8bf-46fe-b7e6-797bfb335df3(PmicGpio) AND 9ba45b66-efa4-441c-a3e4-ed2224786be2(PmicPON)`（不是 INF 里写的 `TRUE`）。
  - 失败路径字符串：`ConfigureButtonGPIOs` 逐个配置 `VOL+`/`VOL-`/`CONF0`/`CONF1`，失败即退出。
- **关键推断**：ImageHandle **没有 DevicePath**，而 `ConPlatformDriverBindingSupported` 明确要求句柄带 DevicePath（`ConPlatform.c:158-163`）。⇒ 该 SimpleTextIn **永远不会被 ConSplitter 聚合进 `gST->ConIn`**，菜单自然收不到按键。
- 键位（来自 `Resources/DTBs/judyp.dts:24685-24728`，与厂内核 DT 一致）：`vol_up = pm8998 gpio6`（active low，code 0x73）、`vol_down = pm8998 gpio5`（active low，code 0x72）、`power = pm8998 pon kpdpwr`（code 0x74）、`hallsensor = tlmm gpio 0x7c`。
- 原厂 `kernel_dtb` 里只找到 **`key_vol_up` 的 pinctrl 节点**，**没有** `gpio-keys`/`linux,code` 字样 ⇒ 键位来自 DT 的 `gpio_keys` 节点，UEFI 侧由 `PlatformInfo` 提供。
- 显示路线已定型：`USE_CUSTOM_DISPLAY_DRIVER = 0`（SimpleFbDxe）。改成 `=1`（DisplayDxe）会 ~20s 后黑屏挂死（E39）。

### 6.1 `PollButtonArray` 反汇编（E42 依据，11-15）
`ButtonsDxe.patched.efi`（45,056 B，PE 偏移 == RVA，`.text@0x1000`）关键结构：

- `SimpleTextIn` 协议结构在 `.data 0x9110`：`Reset=0x24a4`、`ReadKeyStroke=0x24bc`、`WaitForKey`（运行时填 `CreateEvent` 的 event）。
- `ReadKeyStroke`（`0x24bc`）：`RaiseTPL(8)` → **每次都调 `0x2b28`（轮询）** → 从 4 B/条、共 0x80 B（32 条）的环形队列取 `EFI_INPUT_KEY{ScanCode,UnicodeChar}`；队列空返回 `EFI_NOT_READY`。
- 轮询函数 `0x2b28`：调 `0x2b28+0x1d84=0x48ac`（`PollButtonArray`）；**只要它返回错误，就打印 `ButtonsDxe: PollButtonKeys failed status:0x%08X` 并直接返回"无按键"**。
- `PollButtonArray`（`0x48ac`）按顺序读 5 个脚，顺序已确认：
  1. 电源键 `bl 0x49dc`（PON）
  2. `w0=6` → `bl 0x47a8`（PM8998 GPIO6 = VOL+）
  3. `w0=5` → `bl 0x47a8`（PM8998 GPIO5 = VOL-）
  4. `w0=0x4b`(75) → `bl 0x4810`（TLMM GPIO75 = CONF0）
  5. `w0=0x4c`(76) → `bl 0x4810`（TLMM GPIO76 = CONF1）
  每一步失败都 `tbnz x19,#0x3f,<打印错误>`，最终把错误码返回给上层。
- ⇒ **CONF0/CONF1（TLMM）读失败会把 VOL+/VOL- 一起废掉**；TLMM 路径内部就是那条 `SMEM allocation failed! smem_type=138, buf_size=128`。
- **E42 补丁**：`0x4934` 和 `0x4954` 两处 `97ffffb7`/`97ffffaf`（`bl 0x4810`）→ `aa1f03f3`（`mov x19,xzr`，当成功、没按下）。补丁后不再访问 TLMM，既消除 SMEM 报错刷屏，又让 VOL±/电源键正常进入队列。

### 6.2 初始化链与键表（E43 依据，11-15）
- `ButtonsInit`（`0x2e64`）→ `0x45c0` 依次 `LocateProtocol`：`PmicGpio`→`[.data+0x420]`、`TLMM`→`[+0x428]`、`PmicPON`→`[+0x430]`；随后 `InitializeKeyMap`（`0x431c`）、`ConfigureButtonGPIOs`（`0x452c`）。三者任一失败只在启动时打一行日志。
- 读脚函数对"协议指针为 NULL"的态度**不一致**：
  - `ReadGpioStatus`（`0x4760`，VOL+/VOL-）遇到 `[+0x420]==NULL` → **直接返回 SUCCESS 且当"未按下"**（`0x478c cbz → 0x47c8`）。
  - `ReadRealTimeIRQStatus`（`0x46f4`，PON）遇到 `[+0x430]==NULL` → 返回 `EFI_UNSUPPORTED(0x8000…0002)`。
  - `ReadTlmmGpioStatus`（`0x4810`）**不判 NULL 直接 `ldr x9,[x8,#0x18]`**（空指针会 data abort）。
- `InitializeKeyMap`（`0x431c`）：`LocateProtocol(PlatformInfo)` → 调其 `[+0x8]` 取 hw version 存 `[.data+0x41c]` → 按版本查跳表（版本 1..11 / 0x1d / 0x1f）从 `.data 0x9190/0x91a4/0x91b8/0x91cc/0x91e0/0x91f4` 拷 20 B 键表，并把**按键个数写入 `[.data+0x235]`**。版本不在表内 → `EFI_UNSUPPORTED`，`0x235` 保持 0。
- 键表内容是 EFI scan code，例如 `0x91a4 = {1,2,3,4,5}`（电源=Up、VOL+=Down、CONF0=Right、CONF1=Left、VOL-=Home）。
- 每轮 `ReadKeyStroke` 的实际路径：`0x2b28` → `PollButtonArray` → `0x29fc`（逐脚比较当前/上次状态，**不同才置 `[.data+0x22e]=1`**，并按 `[.data+0x238 + i*4]` 取键码）→ 只有 `[.data+0x22e]==1` 才继续把键码放进 7 槽的按键表。
  ⇒ **若 `0x235`（按键个数）为 0，则比较循环一次都不跑，任何按键都不会产生事件，且屏幕上不会有任何报错**。
- **E43 补丁**（都已写入 `ButtonsDxe.patched.efi`，构建时不再改动）：
  - `0x48dc 0xb7f80493`、`0x48fc 0xb7f803f3`、`0x491c 0xb7f80353`、`0x493c 0xb7f802b3`、`0x495c 0xb7f80213` → `1f2003d5`（NOP 5 条 `tbnz x19,#0x3f,<error>`）
  - `0x4938`、`0x4958` 的 `mov x19,x0` → `mov x19,xzr`（CONF 块恒成功）
  - `0x4930`/`0x4950` 的 `strb w10/w11,[x20,#2/#3]` → `strb wzr,…`（`9f0a0039`/`9f0e0039`，CONF 槽恒 0，避免误报按键）
- **E43 判读法**：①音量键能用 → 只有 PON 坏，可以再单独修 PON；②一条报错都没有但仍无键 → `0x235==0`，即 `PlatformInfo` 给不出 judyp 的 hw version（大概率就是 SMEM 那条 `smem_type=138`），下一步要查 `PlatformInfoDxe`/SMEM，而不是继续改 ButtonsDxe。


---

## 7. 工具与路径

| 用途 | 位置 |
| --- | --- |
| fastboot 实验（含 retry 复位/判据） | `D:\UniXNU-judyp-bringup\m4\m1.ps1` |
| 设备/vbmeta 探查 | `D:\UniXNU-judyp-bringup\m4\probe.ps1` |
| retry / unbootable 查看 | `D:\UniXNU-judyp-bringup\m4\slots.ps1` |
| retry 复位（手工） | `D:\UniXNU-judyp-bringup\m4\fixslot.ps1` |
| 等设备回 fastboot（自适应，命中即退） | `D:\UniXNU-judyp-bringup\m4\waitdev.ps1` |
| 镜像头部审计（本文件第 3 节数据来源） | WSL `/root/UniXNU-judyp-bringup/staging/audit-imgs.py` |
| 官方 bootimg 构造 | `cd /root/UniXNU-judyp-bringup && python3 /root/UniXNU/unixnu bootimg …` → `build/boot-judyp.img` |
| 自制 v0/raw 镜像构造 | WSL `/root/UniXNU-judyp-bringup/staging/make-m1img.py` |

---

## 8. OS 阶段（E44 起）

### E44 内核只能从 macOS CI 出来

- 事实：XNU 的构建要 Xcode 工具链（`clang`/`ld64`/SDK），WSL 与 Windows 都产不出 `kernel.macho`；Gitee 没有 macOS runner，本机也没有 `gh` CLI。
- 处理：私有仓库 `geeeeeeeeeeeeeeeek/lgv35-unixnu-judyp`（GitHub），`.github/workflows/kernel.yml` 用 `workflow_dispatch` 跑 `macos-26`，产物 `judyp-kernel` / `judyp-payload` / `judyp-bootimg`。
- 适配点（相对 enchilada 的原 workflow）：
  - 不再跑 `make-enchilada-uefi.py`，改为 `cp -r overlay/Mu-Silicium/{Platforms,Resources,Silicium-ACPI}` 进检出，再跑 `make-judyp-uefi.py`；
  - `cp -r Binaries/enchilada Binaries/judyp`（judypPkg 的 vendor DXE 全在 `Binaries/judyp` 下，上游只带 enchilada）；
  - DTB 用 `Resources/DTBs/judyp.dtb`，输出 `out/judyp/...`，FD 取 `Build/judypPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd`。
- **踩坑（已修）**：`[board] kit` 不能改成 `judyp`。继承来的 archive 脚本硬编码 `ROOT/kits/enchilada`（`build-enchilada-*.py`、`build-native-legacy-display.py`、`build-boot-progress.py`），而 `kits/<kit>` 是 `unixnu` 从 `package/` 物化出来的。改成 judyp 后这些脚本会在导入期就找不到目录。上游 enchilada 的 `kit` 也是 `enchilada`。
- 观测（WSL 里查，避免 PowerShell `Invoke-WebRequest` 的安全弹窗）：
  - `bash /mnt/c/Users/Administrator/AppData/Local/Temp/gh/poll.sh` → 最新 run 的 id/状态
  - `bash /mnt/c/Users/Administrator/AppData/Local/Temp/gh/steps.sh <run_id>` → 步骤级状态
- 首次运行：run 43645042016（旧提交，已取消）；run 43645409139（`626412d`）在 **Build kernel** 失败。

### E45 第一次从零构建是死循环，用 pinned kernelcache 破环

- 失败点（run 43645409139，archive-09 `build-enchilada-storage.py`）：
  `ENCHILADA_STORAGE_CANDIDATE must name a prelinked enchilada kernel.macho with its kernel.json beside it`。
- 为什么是死循环：该 archive 要审计一个**已 prelink 的 kernel.macho**（默认找 `out/<device>/kernel/kernel.macho`），而 `kernel.macho` 只有在最终 XNU 链接之后才存在；最终链接又需要这个 archive 产出的 `libVirtioMmioBlock.a`/`libVerifiedRootProbe.a`。`unixnu/kernel.py:199-220` 的顺序是 bootstrap pass（**故意**在链接处失败，只为留下 compile records）→ prepare-storage-headers → archives → 最终链接，所以从零跑必然卡在 archive-09。
- 破环办法（已写入 workflow）：`audit-storage-interface-static.py` 自己写明「--prelinked 也接受 pinned kernelcache 本身，--slide -0x1000000；直接读 kernelcache 正是让从零构建成为可能的原因」，因为它取的地址是 **module-relative**，与任何同一 kernelcache 的 prelink 完全相同。所以作业现在先 `unixnu ipsw fetch KernelCache`，对 `out/ipsw/<build>/kernelcache.decompressed` 跑一次审计，然后导出：
  - `ENCHILADA_STORAGE_CANDIDATE=<kernelcache.decompressed>`
  - `ENCHILADA_STORAGE_AUDIT=device/build/storage-abi/interface-audit.json`
  这正是 archive-09 读的那一对变量。
- 连带确认：`build-sheng-platform-power.py`（archive-15）用的 `native-owner-ufs-rootauth3-candidate.macho` 就是 archive-09 复制过来的候选，所以 kernelcache 直接当候选也能满足后面的 PMGR 槽位检查。
- 上游仓库 `keyfan/UniXNU-enchilada-bringup` 只有 2 次 Data seed 运行、没有 kernel 运行，作者是在自己的 Mac 上带着旧 `out/enchilada/kernel/kernel.macho` 做的 —— 所以这条从零路径没有先例可抄。
- 下一次运行：run 43646946066（`54f6985`）。

### E46 种子构建打通，卡在上游额度

一次完整的 macOS 运行约 20 分钟（长的时候 25+），为了不在每次改一行就重跑内核，拆成了「种子 + 正式」两段：

- **种子构建**（`Build a seed kernel for the prelink audits`）：把 `judyp_defconfig` 派生一份 `judyp_seed_defconfig`，关掉 `XNU_SHENG_PMGR`、`XNU_NATIVE_LEGACY_DISPLAY`，删掉 8 个 archive（PMGR/显示/touch/cpufreq/dsi/gauge/smmu/adreno），另外 `-force_load` 一个只属于种子的桩库 `build/seed-stubs/libSeedStubs.a`。种子只要能链接出 `kernel.macho` + `kernel.json`，报告就拿去喂正式构建的 archive 09–23。
- **桩的坑**：Mach-O 会给 C 标识符加一个前导下划线，桩名再写成 `_native_legacy_late_colors` 就变成 `__native_...`，ld 照旧报 `"_native_legacy_late_colors", referenced from _compose in libBootProgress.a[7](BootLog.o)`。改成不带下划线的名字 + `-fno-common` + `= 0` 初始化就解析了。另外 `native_mobile_graphics_client_probe` 不能出现在桩里：XNU 的 `IOUserClient.cpo` 自己就定义，会变成 duplicate symbol。
- **报告要放两处**：`build-enchilada-storage.py` 原来只把候选复制到 `build/native-prelink/`，而上游 `audit-amfi-pmgr-contract.py`（archive-15 调）读的是 `build/xnu-prelink/native-owner-ufs-rootauth3-candidate.{macho,json}`。现在两处都放（`build-native-legacy-display.py` 早就是这么做的）。
- **存储 ABI 审计不能审带 slide 的 prelink**：`audit-storage-interface-static.py` 在 `[kernel.prelink] slide = "-0x1000000"` 时会报 `Cannot uniquely identify the original block-storage dispatch (0 candidates)`——它自己的注释就说明这种板子要审 pinned kernelcache。所以候选（给下游读报告用）和审计对象（kernelcache）分开了：新增 `ENCHILADA_STORAGE_AUDIT_CANDIDATE` 指定审计对象，`ENCHILADA_STORAGE_CANDIDATE` 仍是种子。
- **`pmgr=2`**：`scripts/unixnu/payload.py` 在 `native-ufs-root=1` 且开了 `CONFIG_XNU_OWNER_DATA_MOUNT` 时要求启动参数里恰好一个 `pmgr=2`（否则 `No PMGR` panic），而继承来的 kit 读的是 `sheng-pmgr`。两处一起改名成 `pmgr`（`kits/enchilada-pmgr/ShengPlatformPower.cpp` + `board.toml`）。
- **`native_aks_device_id`**：当前 `drivers/AppleKeyStoreState` 子模块要求板子提供这个身份钩子（`size_t (uint8_t*, size_t)`，包成 AES key 用）。补在 `package/KeyStoreProbe.cpp`，返回固定的 `judyp:sdm845`，跨重启稳定。把 `unixnu_ref` 钉到 enchilada 用过的 `8ddccb1e` 也能绕开，但那个 ref 完全没有 UEFI 支持（`build-xnu-4k-baseline.sh` 里搜不到 uefi），所以选择补符号。
- **`gSiliciumEntryArgHobGuid`**：`JudypBootMemoryDxe.inf` 的 `[Guids]` 引用了它，但上游 `SiliciumPkg.dec` 没有声明（enchilada 是靠 `make-enchilada-uefi.py` 打 SEC 补丁时才加进去的），于是 EDK II 直接 `build.py error 4000`。现在 `make-judyp-uefi.py` 只补这一行声明，**不打** SEC entry-arg 补丁：那是历史上把这个系列打进黑屏的改动（见上游文档 line 82）。代价是这个 DXE 运行时找不到 HOB、不发布 ramdisk 卷，payload 只能从真实分区（`payload.img` → `system_a`）加载，不能走 boot.img 里的 ramdisk。
- **进度**：run 43679358255（`d1628815`）已经跑完种子 → 内核 → DarwinBoot → platform seed → Data seed 校验 → payload → staging，只在最后 `Build UniXNU package and firmware volume` 因那个 GUID 失败。修好后 run 43681159374（`cba0eb5b`）**没有启动**：`The job was not started because recent account payments have failed or your spending limit needs to be increased`——私有仓库的 macOS runner 按 10 倍折算，今天的 2000 分钟额度用完了。
- **下一步（二选一）**：给账号加付款/提高 spending limit；或把仓库改成公开（公开仓库的 standard runner 不计量，macOS 也一样）。额度恢复后一条命令就能出全套产物：`dispatch-kernel-seeded.sh 43677790897`。
- **改成公开后一次跑通到第 26 步**：run 43683477666（`b2c13efd`）步骤 1–22 全 success，`Pack the boot images`、`Upload kernel`、`Upload payload` 都拿到了产物，只剩最后一个上传失败。
- **`boot.img` 的 shim 头**：`BootShim.S` 里 Image Size 写的是 `.quad FD_SIZE`，而 `bootimg.py` 会校验 offset 8 那句必须是「shim 长度 + 固件卷大小」，否则 `the ARM64 image header does not describe the shim plus the firmware volume`。`make-judyp-uefi.py` 幂等地把它替换成 `.quad FD_SIZE + (_Payload - _Head)`。
- **`upload-artifact` 不接受 `..`**：`Upload boot image and firmware volume` 直接写 `../Mu-Silicium/Build/judypPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd` 会报 `Invalid pattern ... Relative pathing '.' and '..' is not allowed`（工作区外的路径一律拒绝，哪怕存在）。现在 `Pack the boot images` 末尾先把它 `cp` 到 `out/judyp/boot/SILICIUM_UEFI.fd` 再上传。
- **种子步骤要带 token**：run 43685719694 在种子步骤死在 `prepare-xnu-source.py` → `urllib.error.HTTPError: HTTP Error 403: rate limit exceeded`。原因不是我们的配额，而是匿名访问 `api.github.com` 的共享限额：`build-xnu-4k-baseline.sh` 的 bootstrap pass 会拉 Apple 的 DriverKit 头文件，脚本只在 `GITHUB_TOKEN`/`GH_TOKEN` 存在时才加 `Authorization`。给该步骤补了 `GITHUB_TOKEN: ${{ github.token }}`（`Build kernel` 本来就有，种子步骤漏了）。
- **run 43686484135（`9e52f8d8`）全绿**：1–27 步全部 success，产物：`kernel.macho` 126,144,512 B、`payload.img` 150,994,944 B、`no-ramdisk/boot.img` 1,753,088 B（`ANDROID!`）、`with-ramdisk/boot.img` 152,748,032 B、`SILICIUM_UEFI.fd` 3,145,728 B。payload 的 `kernel_args` 里能看到 `pmgr=2`、`native-ufs-root=1`、`sheng-aks=1`。
- **增量构建**：runner 是干净虚拟机，没有 Docker 层；等价物是 `actions/cache`。已加两层（`e621fe06`）：`out/ipsw`（key = `board.toml` 哈希）和 `out-seed`（key = `configs/kits/package/patches/overlay/scripts` 哈希 + refs + Xcode）。命中时跳过种子构建（约 5 分钟）；XNU 编译本身跨机器没有增量支持，暂不缓存对象目录。
- **下载产物的网络**：WSL 直连 GitHub artifact 存储只有 ~40 KB/s（8 MiB 要 206 s），走 Windows 侧代理 `http://172.20.128.1:111` 是 ~1.2 MB/s（同一 8 MiB 只要 6.8 s），30 倍差距。`dl-resume.sh` 现在支持 `PROXY=` 环境变量 + `curl -C -` 断点续传。

### 11-15 19:10 先开 GIC，再进 IOKit（`1b08564` / `113f52b` / `88a8f91`）

- 动机：面板 `GIC ctl=0 ty=0 isen=0 ...` 说明 IOKit 之前 GIC 从未被编程，任何中断都收不到，怀疑匹配路径被"没有中断"卡住。
- 改动：`pexpert/arm/pe_init.c` 在 IOKit 匹配之前按 GICv3 手工编程（GICD_CTLR 打开 affine 路由、GICR_WAKER 醒来、优先级掩码），并前置声明 `rtclock_intr` 供早期中断处理指向。
- 结果：面板 `GIC ctl=12 ty=0 wk=0 isen=800ff ig1=1 irq=0 oth=0 err=0 st=6` —— GIC 确实被打开了（ctl=12 = EnableGrp1NS|ARE_NS），但 `isen=800ff` 是默认全使能、`irq=0` 从未进过中断，停点不变。
- 结论：不是"没开 GIC"导致的停；但这条改动保留，因为它把 `IRQ=1/mon=0` 的解释变干净了（平台真的一条中断都没收到）。

### 11-15 21:03 给匹配路径加括号打点（`06bb698`）

- 改动：在 `PE_lockdown_iokit`、`startIOServiceMatching`、`zalloc_ext`/`zone_expand_locked` 三处共 9 条 printf/IOLog，用 `native_wl_trace` 门控只在 workLoop 窗口打印。
- 结果：**一条都没出现**。面板 console 最后一行仍是 `Serial requested, consistent debug disabled or debug boot arg not present, confi...`（`kdp_serial_init` 打的）。
- 关键发现（本轮真正有价值的一条）：**printf/IOLog 在 `kdp_serial_init` 之后就不上屏了**，所以"没有输出"不等于"没有执行"。前几轮所有基于 printf 的判读全部无效。
- 静态：`_PE_init_iokit+0x388`（旧内核 0xbf4d144）落在 `PE_init_iokit` 调用 `bl _InitIOKit` 之前的参数/串口处理段；`_PE_lockdown_iokit` 无独立符号（被内联在 `PE_init_iokit` 尾部），所以面板 history 里的 `PE_init_iokit` 不能说明"已经走到 lockdown"。

### 11-15 21:38 kheap root nub + InitIOKit 逐步打点（`bf37dcf`，CI `5d5cb02`）

- 改动：`OSObject_typed_operator_new` 从 `kalloc_type` 改走 `kheap_alloc`（假设类型区首次分配在 ticket spinlock 上自锁）；`InitIOKit` 每一步 `IOLog`；`startIOServiceMatching` 三个窗口标记。**注意：这条 kheap 改动没有上游依据，22:40 那轮已判定应撤。**
- CI 提速：`kernel.yml` 加 `seed_warm` 输入 —— 命中 `restore-keys` 的 seed prelink 时跳过种子构建（省 13 分钟）。
- 结果：run 43720093880 绿（21:39→21:58，19 分钟）；刷 `system_a` 后面板仍停 `PE_init_iokit`，`free=1188562`，无任何 IOLog。
- 成本记录：`Build kernel` 599 s（上一轮约 360 s），`seed_warm` 只省掉 13 分钟种子，净收益约 2 分钟 —— 599 s 才是瓶颈。

### 11-15 22:11 用面板 API 打面包屑（`df373d8`）

- 改动：把 printf 打点换成面板自己的 `boot_progress_stage()`（`weak_import`），22 个 `BCnn` 检查点覆盖 `PE_init_iokit` 入口/`InitIOKit` 十步/`startIOServiceMatching`；`pe_init.c` 顶部先 printf 一条 `NATIVE_CTL` 作对照。
- 结果：照片与 21:38 那轮**完全一致**（`free=1188562`、`wired=56516`、`t=6s`、同样的历史）—— 没有 `NATIVE_CTL`，也没有 `BC01`。
- 由此产生两个互斥解释，屏上无法区分：(a) 新内核根本没有被加载；(b) `weak_import` 的调用被静默跳过（GOT 未绑定，`if (sym)` 直接过）。
- 记一笔操作事故：本轮两次「秒进 BL」是我把 CI 的 `no-ramdisk/boot.img`（hv0、`ramdisk=0`、无 cmdline）刷进 `boot_a` 造成的 —— 正是 E11/E29b 已判死的变体。已刷回 `m4/boot-m4-nobtn.img`（stock 头 + 16,087,010 B stock ramdisk）恢复。**纪律：boot 分区只用 `m4/boot-m4-*.img`。**

### 11-15 22:40 上游源码对照（`keyfan/UniXNU-enchilada-bringup`，仅静态）

- 已 fetch 上游到本地 `upstream`（depth 1，522 文件），同 SoC 的 enchilada 端口 README 状态表写明**已到 SpringBoard** —— 即 sdm845 + 21H461 的 `PE_init_iokit`/IOKit 路径本身不卡。
- 上游 `patches/xnu-device/` **没有**任何 `zalloc`/`OSObject`/`PE_init_iokit` 的改动 → 21:38 那轮的 kheap 改动无依据，应撤。
- 上游的调试通道：
  - `package/BootLog.c`：`sheng-log=1` 每 2 s 把面板文本 + 内核 msgbuf + panic 文本写 userdata 末尾 32 MiB（SHLOG001：块 0 头、1..32 msgbuf、33.. 文本环）。
  - 读取：TWRP/adb 只读 `dd`（porting ROUND 49 原话 "recovered the full msgbuf window via TWRP dd"），或 `package/linux-log` 的 mainline 读取镜像 + USB CDC ACM（需要预编译 mainline boot + busybox + 模块，本地没有）。
  - **但** `native_ufs_log_open` 要求 `gStoreGeometry.valid && gHost.ready`（根卷已挂），也就是 mountroot 之后才可能写 —— 我们卡在它之前，所以本次启动的 msgbuf 从没被写出去。pre-mountroot 阶段上游也只有面板可用。
- 结论：提效不能靠"事后读日志"，只能靠「一轮回答多个确定问题」+ 缩短 CI。下一步必须先解决"内核身份不可判定"这件事（`vm_page_wire_count += 0x100` 这类不依赖日志通道的标记）。

### 11-15 全天执行记录（CST，由 git + CI 重建）

证据边界：当天 GitHub Actions 共 **44 次** run（05:51–22:12 CST；12 成功 / 29 失败 / 3 取消），`m4/` 当天新增 **49 个** boot 镜像，`out/` 新增 **8 个** payload 版本（ci2–ci8）。刷机次数无日志，下表按「可复查的产物 + run」归并，不虚构判读。

| 阶段 | 时间（CST） | 规模 | 内容与结果 |
|---|---|---|---|
| 0 凌晨 boot 头 / UEFI 试验 | 00:00–04:32 | `m4/` 46 个镜像（E20–E43） | 已逐条记在本文 E20–E43：boot 头、shim、DTB 重编、display、按键、reset 时序 |
| 1 CI 流水线磨合 | 05:51–08:54 | 20 次 run：18 失败 + 2 取消 | 全在 Actions 侧：seed/prelink、stub 符号、archive 路径；无设备结论 |
| 2 首次全绿 | 11:27–12:45 | 6 次 run | 12:40 `43677790897` **首个 success**；其余为 keystore/pmgr/UEFI 符号修正 |
| 3 产物链稳固 | 13:02–17:23 | 11 次 run：5 成功 / 1 取消 / 5 失败 | E46 全绿、shim 头尺寸、artifact 路径、IPSW+seed 缓存、Mu-Silicium 钉版、SimpleFbDxe 回退 |
| 4 面板 + GIC | 18:29–19:56 | 4 次 run（3 成功 / 1 失败 `43707692406`） | 面板持续重绘、3x 字号、GICv3 前置打开、`rtclock_intr` 前置声明；照片显示 `GIC ctl=12` 但 `irq=0`，停点不变 |
| 5 IOKit 打点三连 | 21:04–22:12 | 3 次 run，全成功 | `06bb698` 9 条 printf（全无输出）→ `bf37dcf` kheap+ IOLog（全无输出）→ `df373d8` 面板 BC 面包屑（无 BC、无 `NATIVE_CTL`） |

各阶段 run id：
- 阶段 1（全失败）：`43645031480` `43645042016`(取消) `43645409139` `43646946066` `43647595427` `43648115937` `43648639428` `43649595992` `43650943819` `43651947985` `43653018561` `43653496638` `43654047758` `43654967252` `43655871584` `43656896969` `43657831630`(取消) `43657916652` `43659597791` `43660528751`
- 阶段 2：失败 `43672474238` `43673435004` `43674775117` `43676561471` `43678114878`；成功 `43677790897`
  （注：`43676561471`/`43678114878` 位于 12:23/12:45，属阶段 2 尾）
- 阶段 3：失败 `43679358255` `43681159374` `43681538165` `43683477666` `43685719694` `43697038856`；取消 `43694512868`；成功 `43686484135` `43690652485` `43695025337` `43699000521`
- 阶段 4/5（`ci-scale`）：成功 `43704335330` `43709059425` `43711352036` `43717081985` `43720093880` `43723050355`；失败 `43707692406`

产物清单（当天新建）：
- `m4/`：46 个 `boot-e*.img`（E20–E43）+ `boot-m4-ci.img`(15:21) `boot-m4-simplefb.img`(16:15) `boot-m4-nobtn.img`(16:43)
- `out/`：`ci2`(15:14) `ci3`(09:42 payload / 16:15) `ci4`(18:46) `ci5`(19:48、20:27) `ci6`(21:27) `ci7`(22:01) `ci8`(22:33)

| 时间 | commit | CI | 做了什么 | 结果 |
|---|---|---|---|---|
| 05:37 | `9190d11` | — | judyp UniXNU 基线快照（UEFI 菜单 + 音量键） | 起点 |
| 05:46–08:54 | `4ce43b7` `626412d` `54f6985` `bc1f982` `ea7fab8` `92a8c83` `734a764` `ae95368` `481888e` `298c4d1` `5e6f26f` `d157380` `79b8a93` `44acbd3` `9a9af52` `1641bf2` `a460891` `edd912e` `58fa871` | 阶段 1 | 内核构建搬上 Actions；kit 标签保留 enchilada；seed 从 pinned kernelcache 起步；去 PMGR 归档；真 patch series 当种子；stub 用 -fno-common 真定义 | 阶段 1 全失败，属 Actions 侧 |
| 11:27–13:02 | `c209f3d` `0636761` `2550e66` `ecf1f03` `93ed800` `3ea4c84` `d162881` `cba0eb5` | 阶段 2 | 种子 stub 去前导下划线；storage 审计；keystore `native_aks_device_id`；`pmgr=2`；UEFI `gSiliciumEntryArgHobGuid` | 12:40 首次全绿 |
| 13:27–17:23 | `be42a28` `b2c13ef` `7b61172` `b1fe61e` `9ee420b` `9e52f8d` `e621fe0` `5dcdf4f` `30840f7` `da5aa83` `b45acd5` `07cfc66` `2b68826` `ddc45e9` | 阶段 3 | E46 记录；shim 头尺寸；artifact 路径；IPSW/seed 两级缓存；Mu-Silicium 钉 E40 树；去 ButtonsDxe；面板 2x | 产物链稳定，M4 可刷 |
| 18:23–19:56 | `887184d` `1a4a3c0` `1b08564` `113f52b` `88a8f91` | 阶段 4 | 面板持续重绘 + 3x；GICv3 在 IOKit 前打开；`rtclock_intr` 前置声明 | `GIC ctl=12`、`irq=0`，停点不变 |
| 21:03 | `06bb698` | 43717081985 | 匹配路径 9 条 printf 打点 | 一条未出 → printf 在 `kdp_serial_init` 后失效 |
| 21:28–21:38 | `5d5cb02` `bf37dcf` | 43720093880 | `seed_warm` 开关；kheap root nub + `InitIOKit` IOLog | 面板逐字段不变，无输出 |
| 22:11–22:30 | `df373d8` | 43723050355 | 面板 BC 面包屑（weak_import）+ `NATIVE_CTL` | 无 BC、无 `NATIVE_CTL` |
| 22:12 之后 | — | — | 两次把 CI 的 `no-ramdisk/boot.img` 刷进 `boot_a` → 秒进 BL；刷回 `m4/boot-m4-nobtn.img` | 恢复面板（操作事故） |

### 已确认事实（不得再测）

1. `boot` 分区只能用 stock-like 变体（hv0 / `ramdisk=0` / 空 cmdline 会在 2.3 s 复位）—— E11/E29b。
2. printf/IOLog 在 `kdp_serial_init` 之后不上屏；面板 console 最后一行永远是它的 `Serial requested...`。
3. 面板 history 里的 `PE_init_iokit` 不能证明"已进 lockdown"（`PE_lockdown_iokit` 被内联，无独立符号）。
4. 采样 PC 落在 `PE_init_iokit` 调 `bl _InitIOKit` 之前的参数/串口段。
5. GIC 在 IOKit 之前从未被编程；即使手工打开（`ctl=12`）停点也不变。
6. 停机形态：`free4K=1188562`（不缺内存）、`SMP req=0`（无副 CPU）、DAIF 屏蔽（IRQ-off 自锁）、无 panic。
7. SHLOG 日志窗口必须 `gStoreGeometry.valid && gHost.ready`，即 mountroot 之后才能写 → pre-mountroot 无日志通道。
8. 上游 enchilada（同 SoC）跑到 SpringBoard，且未改 `zalloc`/`OSObject`/`PE_init_iokit` → 停点是 judyp 侧差异。
9. `seed_warm` 能省 13 分钟种子构建，但 `Build kernel` 599 s 才是瓶颈。
10. 内核身份至今未证实：`df373d8` 的照片与 `bf37dcf` 逐字段相同，`weak_import` 未绑定可以完全解释"无输出"。

### 流程规则（今天亏在这上面）

- 每轮 dispatch **之前**先在本文写条目：时间、commit、要验证的命题、以及"这条命题尚未被上面 10 条覆盖"。
- 每轮刷机后写：刷了哪个分区、镜像来源、面板判读、是否推翻已有结论。
- 任何"没有输出"的判读，必须先证明观测通道可用，否则不计入结论。





### 轮次 R-CK（vm_page_wire_count 计数打点）—— 11-15 23:4x，dispatch 前
- commit：`b0bae2a`（run 43728585549，已刷 system_a）；patch：zzzzzzz-native-iokit-rootnub.patch（3 文件，88 行，apply-check OK @ pristine）
- 新静态结论（本轮依据，源码可查）：
  1. boot_progress_stage 是 payload 侧函数（package/BootProgress.c:807），内核引用被 CI stub archive 用空桩满足 → df373d8 的 BCxx 在链接期就是空操作，无输出是必然。
  2. PE_init_iokit 第二句是 printf("iBoot version")，面板 console 从未出现 → 停点在第一句 PE_init_printf(TRUE) 内部（console/屏幕接管），IOKit 从未开始。前三轮打点全在停点之后。
- 本轮命题（一次照片全部回答）：
  P1 新内核是否在跑（wired 是否 +256）；
  P2 停点是否在 PE_init_printf(TRUE) 内（N=0 即是）；
  P3 若 N>0，逐 checkpoint 收窄。
- 判读式：wired = 56516 + 256 + 4N；N=26 全过 → 停点在 matching 之后。
- 判读表：N: 0 入口 / 1 PE_init_printf 后 / 2 首 printf 后 / 3 pe_prepare_images 后 / 4 InitIOKit 前 / 5-17 InitIOKit 内部(BC10..BC22) / 18 InitIOKit 后 / 19 ConfigureIOKit 后 / 20 lockdown 进 / 21 zalloc 后 / 22 SM 进 / 23 workLoop / 24 regService 进 / 25 regService 完 / 26 SM 完。
- 回滚项：OSObject_typed_operator_new 的 kheap 改动已撤销（上游同 SoC 未动分配器，且停点在 IOKit 之前）。
- CI：seed_warm=true。结果：**已刷机；面板 stage=PE_lockdown_iokit、采样 PC=`_memmove+0xc4`（8s）、DAIF=200、无 panic；wired 数值照片在旧窗口未回填，待重报后按 N=(wired-56772)/4 判读。**

### 轮次 R-CK2（续接 27..33 检查点）—— 11-16，dispatch 前
- commit：待填；patch：zzzzzzzz-startup-chain-checkpoints.patch（2 文件：osfmk/kern/startup.c + bsd/kern/bsd_init.c；patch --dry-run + git apply --check 双通过 @ pristine）
- 设计：**不动 0..26 任何埋点**，只续接，故一轮照片同时回答 R-CK 的判读（N≤26 时两轮等价）和新链路。
- 新链路埋点（N=56772/4+4N 同式）：
  - 27 PE_lockdown_iokit 返回（= matching 全过）
  - 28 kperf_init_early 返回
  - 29 将进 bsd_init
  - 30 bsd_init 入口
  - 31 IOKitInitializeTime 返回
  - 32 vfs_mountroot 成功
  - 33 set_rootvnode 完成
- 命题：
  - P1 若新固件 wired=56772+4N 且 N≤26 → 与 R-CK 停点一致（0..26 未动），直接按旧表判读；
  - P2 N=27 → IOKit matching 全过，停点在 startup.c 后链（首次把嫌疑从 IOKit 内部移出）；
  - P3 N=28/29/30 → 卡点在 kperf/bsd_init 入口前/bsd_init 内部；
  - P4 N≥31 需警惕自然 wired 增长污染（vfsinit/buffer cache/mountroot 会 wire 页）：判读看值是否精确落在 56772+4N 网格上；值大幅偏离网格 = 已过 IOKit、卡在 bsd 链内。
- 与 ci9 采样的关联假设（待本轮证伪/证实）：PC=`_memmove+0xc4` 若对应 StartIOKitMatching 内部（IOService 匹配的 OSData/OSDictionary 拷贝），本轮应仍停在 N≤26；若对应 bsd 早期（如 bsd_bufferinit），应见 N≥30。
- CI：seed_warm=true。结果：待填。

### 轮次 R-CK3（先计划、后执行）—— 11-21

**重盘点的硬事实（含证据）**

1. **面板 stage history 就是内核的 `kernel_bootstrap_log` 流**。证据：`PE_lockdown_iokit` 这个字符串全树唯一来源是 `startup.c` 的 `kernel_bootstrap_log("PE_lockdown_iokit");`（见 `zzzzzzzz-startup-chain-checkpoints.patch` 的上下文行），payload 不可能知道这个名字。
   → 推论：`df373d8` 用 `weak_import boot_progress_stage` 打 BCxx 是绕远路；那条通道本来就通，只是内核侧直接调是链接期空桩。
2. 因此 ci9 照片里 stage 末行 `PE_lockdown_iokit` = 内核最后一条 bootstrap log。两种可能互斥、当前证据无法区分：
   (a) 卡在 `PE_lockdown_iokit` 函数内部；(b) 已过 lockdown，但其后没有 bootstrap log（日志空洞）。
3. PC=`_memmove+0xc4` 连采 8s + console 末行 `lockdown mode in nvram is off`（`csm_check_lockdown_mode` 打的，位于 lockdown 之前约 50 行）→ **printf 通道比 stage 通道早死**；"没有输出"不能当判据（与"已确认事实"第 2 条一致）。
4. 外部对照（2026-11-21 检索，静态）：
   - unixnu.com 已收录 judyp 设备页（指向本仓）。
   - 同 SoC（SDM845）：enchilada 有 5 个独立端口（keyfan / rou2ter / dragon120820 / wangshaofan82-png），keyfan 的 bringup README 报已到 SpringBoard；OnePlus 6T（fajita）的 HakiOS 0.5 已全功能（Wi-Fi / LTE / GPU / 触控，2026-11-15 发布）。
   - 上游官方调试设施我们一个都没用：`entry_probe_reset_delay / reset_after / reset_in`（过了指定调用点就 PSCI 重启 = 二进制问答，不需要拍照读数）、`panic_screen`、`build-tag=`（面板标题栏显示构建标签）、color bars / green bar、`serial=3`。
   - 我们 `board.toml` 的 `entry_probe_reset_after` 现在指在 `_vfs_mountroot`（远点，等于白配）。
   - 上游调试纪律原文：One question per run + 记录最后一个确认的 checkpoint。

**计划与门禁（先计划、逐步验证、不蛮干）**

Step 0 静态（本地，不碰设备、不碰 CI）
- 0.1 验证 `kernel_bootstrap_log` → `boot_progress_stage` 的转发确实存在于 `patches/xnu/*` 的 boot-progress 补丁里。**不成立则第一节的推论作废，路线整体重排。**
- 0.2 用 `llvm-nm` 在 ci9 的 `kernel.macho` 上找 lockdown 之后**非内联**的符号（`_vm_set_restrictions` / `_kperf_init_early` / `_bsd_init` 等），确定 `entry_probe_reset_in/after` 的可用组合。
- 0.3 核 `kernel_args` 余量（当前 970/1000），新增参数后 ≤1000。

Step 1 补丁（一个，先本地验证再 push）
- 废弃 c81fabe 的 wired 计数版，改写为 `kernel_bootstrap_log("ck27: ...")` 串，首行加 `ci11-ident`。
- 门禁（全真才允许刷机）：`patch --dry-run` + `git apply --check` @ pristine 双通过；diff 只动 `startup.c` / `bsd_init.c`；CI 绿；`llvm-strings kernel.macho | grep ck27` 命中。

Step 2 刷机（只回答一个问题：身份 + 是否过 lockdown）
- 刷 `system_a` → reboot → 只看 stage history 末行。
- 出现 `ci11-ident` = 内核身份确认；末行 `ck27` = 已过 lockdown；末行仍 `PE_lockdown_iokit` 且无 ck27 = 卡在 lockdown 内；**无 `ci11-ident` = 没换成内核，只查 boot 链，不改内核**。

Step 3 二分（仅当 Step 2 判"卡在 lockdown 内"）
- `entry_probe_reset_after` 一次一个点，答案是"是否自动重启"，不拍照、不算数。

Step 4 对齐 enchilada（仅需要时）
- diff judyp 与 keyfan/enchilada 的 `xnu-device` 补丁与 ADT，**只产出 judyp 独有差异清单**，不盲改。

**门禁规则**：任何一步验证不通过即停止，不进入下一步；每步结果回填本节。

Step 0 结果（2026-11-21）
- **0.1 ✅ 证实**：`/root/UniXNU/patches/xnu/zzz-boot-progress.patch` 把 `kernel_bootstrap_log()` 改成同时调用 `boot_progress_stage(message)`（补丁 L35-45）。故"面板 stage history = 内核 bootstrap log 流"成立。
- **0.1 附带发现（直接改计划）**：同一补丁已内置 lockdown 之后的检查点——`bsd_init enter`（L134）、`vfs_mountroot enter`（L161）、`load_init_program enter`（L196）、`SystemOS mount enter/returned`（L204/206）、`Data mount enter/returned`（L210/212）；早期还有 `arm_vm_init enter/returned`（L20/22）与 `original PMGR nub start/returned`（L151/153）。
  → ci9 末行是 `PE_lockdown_iokit` 且**没有** `bsd_init enter`，即停点位于 lockdown 调用与 bsd_init 之间。**这条判读不需要 wired 计数**，R-CK/R-CK2 的计数方案作废。
  → `bsd_init` 内部还有 `bsd_init_kprintf()` 映射到 `boot_progress_stage("bsd_init: " x)`（L143），进入 bsd 后仍有粒度。
- **0.3 取消**：本计划不再新增 boot arg（构建标识改用内核字符串 `ci11-ident`，经同一条通道上屏），1000 字节命令行限制与本轮无关。
- **0.2 ✅ 完成（静态反汇编，ci8z kernel.macho）**，并推翻两条旧结论：
  - `_PE_lockdown_iokit` **有独立符号**（`0xfffffff00bf4d318`），并非内联——旧"已确认事实"里"封闭嵌套无法埋点"不成立。
  - 全部 BCxx 是**真实 `bl _boot_progress_stage`**（目标 `0xfffffff00bfa0688`，字符串在 `__cstring`）——旧结论"BCxx 在链接期是空桩"**错误**。
- **0.2 反汇编得到的完整调用链与检查点地图**（ci8z，即 df373d8）：
  - `PE_lockdown_iokit`：`BC40 enter` → `zalloc_iokit_lockdown` → `BC41 zalloc returned` → `StartIOKitMatching` → `BC42 StartIOKitMatching returned`。其中 `zalloc_iokit_lockdown` 只有 4 条指令（向 `0xc1b5000+0x502` 写 1 后 ret），**不可能阻塞**。
  - `StartIOKitMatching`：`socd_client_trace(0x61f0004,0,0,0,0)` → 取全局槽（`0x71c80f8`）→ 非空则 `IOPlatformExpertDevice::startIOServiceMatching()`，空则走 cold.1/cold.2。
  - `startIOServiceMatching`：`BC30 enter` → `IOWorkLoop::workLoop()` → 写 `self+0x88` → `BC31 workLoop allocated` → 空判 → `BC32 registerService enter` → `vtable[0x2a0](self,0)`（registerService）→ `BC33 registerService done` → 返回 1（空 workLoop 则返回 0）。
- **据此，ci9（b0bae2a）是本轮的观测倒退**：它把 BCxx 换成 `vm_page_wire_count` 计数，stage history 里就只剩纯文本阶段（末行 `PE_lockdown_iokit`），名字全部消失，而数字又没取到 → 白跑一轮。**ci8 的 `out/ci8/payload-df373d8.img` 是 BC 版，本地已存在，重刷不需要 CI。**
- **0.2 判定表（重刷 ci8 后只看 stage 末行）**：
  | 末行 | 结论 |
  |---|---|
  | `BC30 startIOServiceMatching enter` | 卡在 `IOWorkLoop::workLoop()` |
  | `BC32 registerService enter` | 卡在 `registerService`（vtable+0x2a0） |
  | `BC33 registerService done` / `BC42` | 匹配已完成，卡点在 lockdown 之后 |
  | `BC40` / `BC41` | 与静态结论矛盾（zalloc 只有 4 条指令），需查 stage 通道丢行 |
- 下一步静态（Step 3 预置）：把 vtable `+0x2a0` 的目标函数反汇编出来，找 `memmove` 调用，与 `PC=_memmove+0xc4` 对齐。
- **Step 3 预置结果 ✅**：对象 isa 指向 `__ZTV22IOPlatformExpertDevice+0x10`，故实际槽位是 `+0x2b0` = `IOService::registerService(uint32_t)`（`+0x2a0` 是 `IOService::updateReport`，误读）。`registerService` 共 131 条指令，调用链：`IORegistryEntry::getRegistryRoot` → `IOInstallServicePlatformActions` → `IOInstallServiceSleepPlatformActions` → **`IOService::startMatching(unsigned int)`** → `IOMalloc_internal` / `_strchr` / `IOFreeData` / `IOLog`。
  → 真正的匹配引擎是 `IOService::startMatching`。静态定位到此为止（再往下需要运行时数据），下一步必须是刷 ci8 读末行。

### 刷机记录 R-CK3-a（2026-11-21，全量重刷 A 槽）

用户已把手机全量恢复原厂，故本次为全量重刷；**B 槽零操作**（全程未发出任何 `*_b` 命令）。

```
set_active a
flash boot_a   m4/boot-m4-nobtn.img            67,108,864 B   OKAY
flash system_a out/ci8/payload-df373d8.img    150,994,944 B   OKAY
set_active a
reboot
```

- 刷前：`current-slot=a`、`slot-retry-count:a=6`、`slot-unbootable:a=no`
- 刷后：`current-slot=a`、`slot-retry-count:a=7`
- 时间线：t=0.6s 离开 fastboot；120s 内未回 fastboot（无 panic 循环）
- 待填：**stage history 末行** → 按上表判定卡点

### 判读 R-CK3-a（2026-11-21 14:28 照片）

**面板读数**
- `t=6s idle=0s IRQ=1 mon=0 lost=0 root=0 proc=0 free=1188563`
- `last IRQ PC=fffffff00b9f4478` → 符号化为 `_ml_set_interrupts_enabled_with_debug+0x50`（中断入口，非卡点）
- `DAIF=3c0`（D/A/I/F 全屏蔽）；`PROC pass0=0`；`SMP boot=0 req=0`；`HANDOFF calls=0`；`DISPLAY calls=0`；`SWAP calls=0`
- `MEM wired=56560`（**低于旧公式基线 56772 → 该公式基于另一构建，作废**）
- stage 序列：`BC13 IOMachPortInitialize done` → `BC14 symbols done` → `BC15 interruptAccountingInit done` → `BC16 new IOPlatformExpertDevice` → `BC17 root nub allocated` → **`BC18 root nub init`**（重复出现，**无 BC19**）
- console 末行：`NATIVE_CTL: PE_init_iokit entered` / `iBoot version:` / `iBoot Stage 2 version:`

**判读**
1. BC18 打在 `bool ok = gRootNub->init(dtTop);` **之前**（zzzzzzz-native-iokit-rootnub.patch L109-111），BC19 未出现 → **卡在 `IOPlatformExpertDevice::init(dtTop)` 内**。
2. 该函数只有两步（反汇编 `0xfffffff00bee56fc`）：`bl IODeviceTreeAlloc(dtTop)` → 按返回值尾调用。故卡点收窄为 **`IODeviceTreeAlloc`**（`0xfffffff00be93eb4`，623 条指令）。
3. `IODeviceTreeAlloc` 的调用面：`IORegistryEntry::makePlane`、11×`OSSymbol::withCStringNoCopy`、`OSData::withBytesNoCopy`、`OSArray::withCapacity/withObjects`、`zalloc_permanent_tag`、`IOMallocTypeVarImpl`、`IOLockAlloc`、`PE_parse_boot_argn`、`SecureDTInit/LookupEntry/GetProperty/IsLockedDown/InitEntryIterator/IterateEntries/EnterEntry/ExitEntry`、`MakeReferenceTable`、`IORegistryEntry::fromPath`、`OSDictionary::withCapacity`、`IORegistryIterator::iterateOver`、`IODTMapInterruptsSharing`、`strnstr/strlen/strtol`。**无直接 memmove 调用**，但 `withCStringNoCopy`/`withBytesNoCopy` 内部会 memmove —— 与旧照片 `_memmove+0xc4` 相符。
4. **推翻"停在 PE_lockdown_iokit"**：本构建根本没走到 lockdown；旧读数应是 `PE_init_iokit`（console 里就有 `PE_init_iokit entered`）被误记。ci9 把 BC 换成数字后 stage 里只剩 bootstrap 文本，放大了这个误读。

**下一步（按门禁执行）**
- 零成本：解析 `board.dtb`，查异常属性（缺 `name`/`device_type`、长度 0 或超大、重复属性、子节点数异常）。
- 一轮 CI：在 `IODeviceTreeAlloc` 内加 4 个 BC 点——`SecureDTInit` 后、`MakeReferenceTable` 后、DT 迭代循环内（计数）、`IODTMapInterruptsSharing` 前后。

### DTB 静态体检（零成本，`overlay/Mu-Silicium/Resources/DTBs/judyp.dtb`）

- 头：`magic=d00dfeed`，`totalsize=554858`，`version=17`，`last_comp=16`，struct 56+501832，strings 501888（52970 B），rsv 40 —— 结构完整，walker 无 `bad` token。
- 规模：**3266 个节点**，最大深度 7。
- 最大属性：5051 B，`/soc/qcom,mdss_mdp@ae00000/.../timing@0:qcom,mdss-dsi-on-command`（显示时序，正常）。
- 重复属性：0；零长度属性：1428（都是布尔标志，正常）。
- **全部 3266 个节点都没有 `name` 属性**（Linux/Qualcomm 风格；Apple 的 DeviceTree 每个节点都带 `name`）。
- 根节点属性：`#address-cells / #size-cells / model / compatible / qcom,msm-id / interrupt-parent / qcom,board-id`。

结论：结构层面没有畸形，**嫌疑转向语义层**（SecureDT/IODeviceTreeAlloc 依赖 Apple 风格属性，如每节点 `name`）；也可能是某个特定子树触发死循环。

**下一轮（不需要重编内核，只换 DTB 重打 payload）——二分换树**
1. 用只保留 `/cpus` + `/chosen` + 最小 `/soc` 的裁剪 DT 打 payload，刷 A 槽。若 BC19 出现 → 说明卡点由被裁掉的子树触发；若仍无 BC19 → 说明与 DT 内容无关（指向 SecureDT 初始化本身）。
2. 按结果对半裁剪，逐轮收敛到具体节点。
3. 并行验证：从 Mu-Silicium 取 `enchilada.dtb`（同 SoC、已知能过此步）做同项体检，比对 `name` 等 Apple 风格属性差异。

### DTB 对照结果（enchilada vs judyp，2026-11-21）

来源：`Project-Silicium/Mu-Silicium` `main` → `Resources/DTBs/enchilada.dtb`（555,398 B），下载后与本地 `judyp.dtb`（554,858 B）逐项比对。

| 项 | judyp | enchilada |
|---|---|---|
| 版本 / 节点数 / 最深 | 17 / 3266 / 7 | 17 / 3265 / 7 |
| `name` 属性数 | 0 | **0** |
| 最大属性 | 5051 B | 5051 B |
| interrupt-controller 数 | 36 | 36 |
| interrupt-parent 环 | 2（均在 `/soc/qcom,pcie@0x1c00000`、`@0x1c08000`，两侧同） | 2（同） |
| interrupt-parent 断链 | 0 | 0 |

**结论：两棵树是同一套工具生成的孪生体，DT 结构/风格差异不是卡点原因。`name` 假设与 interrupt-parent 环假设均排除。**

→ 剩余解释：卡在 `IODeviceTreeAlloc` 内的某一步与 DT 内容无关（`SecureDTInit` / `zalloc_permanent_tag` / `IORegistryEntry::makePlane` / `IODTMapInterruptsSharing` 的运行时状态），或 DT 并非 judyp.dtb 这一份。**必须靠内核侧检查点定位，静态排查到此为止。**

### R-DT1 预登记（2026-11-21，`IODeviceTreeAlloc` 内部埋点）

**命题**：卡点在 `IODeviceTreeAlloc` 内部，且可由 stage 字符串直接命名到具体步骤。

**变更**
1. 新增 `patches/xnu-device/zzzzzzzzz-native-dt-alloc-checkpoints.patch`：只改 `iokit/Kernel/IODeviceTreeSupport.cpp`（8 hunk / 7 个检查点）。
2. `zzzzzzz-native-iokit-rootnub.patch` 的 `UNI_BC` 宏恢复调用 `boot_progress_stage()`（保留 +4 wire 计数）。理由：`llvm-nm out/ci8z/judyp/kernel/kernel.macho` 显示 `_boot_progress_stage` 为**已定义**符号（`S` @ `0xfffffff00bfa0688`），旧"stub 把调用抹成空"的判断错误；恢复后同一张照片能同时看到 BC13–18 旧链和新点。

| 标识 | 位置 |
|---|---|
| BC50 | 函数入口（全部局部声明之后） |
| BC51 | 14 个 `OSSymbol` + `OSData` + `OSArray` + `IODTResolvers` + assert 之后 |
| BC52 | `MakeReferenceTable(dtTop)` 返回后 |
| BC53 | 遍历循环内，child 计数 = 1 / 1000 / 2000 / 3000 |
| BC54 | do/while 遍历结束 |
| BC55 | `IODTMapInterruptsSharing` 循环结束 |
| BC56 | `return parent` 前 |

**门禁（先过再刷）**
- [x] `git apply --check` @ pristine（xnu `d8b8029`，3 个文件）通过
- [x] `patch -p1 --dry-run` 通过
- [x] diff 仅 `iokit/Kernel/IODeviceTreeSupport.cpp`
- [ ] CI 绿
- [ ] `llvm-strings kernel.macho | grep -c BC50`（并抽查 BC51–BC56）命中
- 任一不过 → 不刷机

**判定表（刷后看 stage 末行）**

| 末行 | 判读 |
|---|---|
| 仍 `BC18`、无 `BC50` | 新内核未运行或补丁未生效 → 先查刷机链，不判读 |
| `BC50` | 卡在 `makePlane` / `OSSymbol::withCStringNoCopy` 段（BC50–BC51） |
| `BC51` | 卡在 `SecureDTLookupEntry("/chosen/memory-map")` / `SecureDTGetProperty` / `SecureDTIsLockedDown` |
| `BC52` | 卡在 `MakeReferenceTable(root)` 或 `SecureDTInitEntryIterator` |
| `BC53 DT child 1/1000/2000/3000` | 卡在遍历区间内：`MakeReferenceTable(child)` / `attachToParent` / `AddPHandle` / `SecureDTEnterEntry` |
| `BC54` | 卡在 `stack->release()` / assert / 根节点改名 / `attachToParent(registryRoot)` / `freeDT` 块 |
| `BC55` | 卡在中断映射循环（`IORegistryIterator` / `IODTMapInterruptsSharing`）或 `allInts->release()` |
| `BC56` | 函数跑完 → 卡点其实在 `init()` 返回路径，或 14:28 读数需重审 |

**照片**：离开 fastboot 后 60–120 s 拍一张（面板 stage history 常驻）。

