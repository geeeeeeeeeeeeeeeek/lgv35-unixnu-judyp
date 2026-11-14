# LG V35 ThinQ (judyp) UniXNU 移植工作计划

> 2026-11-14 制定。基于对三个代码库的实读调研，非推测。
> 参考机：OnePlus 6 (enchilada, SDM845) — UniXNU 官方支持、有完整 bringup 仓库。

## 一、已验证事实（有证据）

| 事实 | 证据 |
|---|---|
| judyp 与 enchilada 的 UART(0xA84000)/DRAM 布局(0x180000000)/UFS(0x1d84000)/cont_splash(0x9D400000/24M) 完全一致 | judyp stock boot.img cmdline + LineageOS kernel DTS（已落地 D:\UniXNU-ref\kernel_lge_sdm845） |
| judyp boot.img header 与 enchilada 兼容（v0, kernel_addr 0x8000, pagesize 4096） | 实测解析 D:\UniXNU-ref\boot.img |
| 触控是 FocalTech ftm4（非 Synaptics）、面板是 LG SW43402 1440P cmd-DSC（非 sofef00）、LG 专属 reserved-memory 覆盖 | judyp DTS 实读 |
| Mu-Silicium 上游 LG 平台只有 mh2Pkg/caymanslmPkg（均 SM8150），**无 LG SDM845 先例** | /root/Mu-Silicium/Platforms/LG/ 实读 |
| enchiladaPkg 机型专属量集中在 enchilada.dsc L30-62（DDR 基址/SMBIOS/framebuffer 1080x2280/QCOM 类型）+ Include/DXE.inc 驱动清单 + DeviceBuild.py 路径声明 | enchiladaPkg 实读 |
| 构建驱动：`unixnu -D judyp build ...`；config.py 强制要求 board.toml；tree.py 把 bringup 仓库 `package/` 挂载为构建树 `kits/<kit>`；bootimg.py 组装 BootShim+FD+DTB+ramdisk → boot.img | scripts/unixnu/{cli,config,tree,payload,bootimg}.py 实读 |
| kernel archives（bringup 的 build-*.py）在 `unixnu build kernel` 时按序执行；XNU 本体构建需 macOS runner | docs/guide/build-kernel.md + .github/workflows/macos.yml |

## 二、待验证假设（计划中的关键赌注）

1. **LG ABL 与 OnePlus ABL 对 UEFI handoff 的差异** — enchilada 走 OnePlus ABL 传递的内存 map 假设；LG 的 abl 裁剪了什么未知。验证方式：M2 提取 judyp abl 后比对 + 首次 fastboot boot 实测。
2. **LG vendor DXE（显示驱动）能否在 enchiladaPkg 框架内工作** — SW43402 面板初始化序列需从 LG abl/vendor blob 抠出。若不行，退路是 SimpleFbDxe + ABL 传下来的 cont_splash framebuffer（免初始化，成功率最高，先走这条）。
3. **DRAM 实际大小** — DTS 写 6GB(0x180000000)，但需在真机 `getprop ro.boot.msz` / MemTotal 复核。
4. **XNU 内核 4K 页支持** — enchilada 已验证，同 SoC 可继承。

## 三、里程碑

### M0 环境与构建链打通（进行中，无需手机）
- [x] WSL + 磁盘策略（D 盘主导，C/E 零占用）
- [x] WSL vmIdleTimeout=-1 修复后台构建被杀问题
- [ ] LLVM 工具链编译（WSL 后台进行中，巡检任务盯日志）
- [ ] Mu-Silicium 子模块修复（git submodule update，进行中）
- [ ] 工具链完成后 `./unixnu status` 验证构建驱动可用
- **验证条件**：`./unixnu status` 全绿；enchilada 参考板能完整 `unixnu build firmware`（证明本机工具链能出 UEFI fd）

### M1 judyp 设备仓库成形（本仓库，多数已开工）
- [x] board.toml judyp 化（已改，userdata 标 PLACEHOLDER 禁刷）
- [x] scripts/check-judyp.py（sed 生成，待 M2 后校准）
- [ ] 从 enchiladaPkg 派生 judypPkg（Mu-Silicium 内）：
  - 复制 enchiladaPkg → Platforms/LG/judypPkg，改 dsc（DDR 基址同 0x80000000；framebuffer 先按 SimpleFb 兜底；SMBIOS 改 LG/V35）
  - DeviceBuild.py 路径声明（Platforms/LG + Silicon/Qualcomm + Silicium-ACPI）
  - Resources/Configs/judyp.toml + Resources/DTBs/judyp.dts（基于 enchilada.dts 骨架 + judy_common reserved-memory 覆盖）
- [ ] 参照 check-enchilada.py 校准 check-judyp.py（交叉验证 memory map/DTB）
- **验证条件**：`unixnu build firmware -D judyp` 在 QEMU 冒烟通过（sbsa/qemu 平台跑 UEFI fd 到菜单）

### M2 真机数据采集（需要用户配合 ★）
- [ ] V35 开 USB 调试 + adb root
- [ ] dump 分区：abl（vendor UEFI 驱动提取源）、dtbo、xbl、modemst 备份；GPT 全表（替换 userdata LBA 占位值）；`getprop ro.boot.*` 全量
- [ ] 用 UEFITool 解剖 abl：比对 enchilada 的 vendor DXE 清单，列差异
- **验证条件**：GPT 实测值写入 board.toml；uefiplat.cfg（ABL 内存 map dump）生成 → check-judyp.py 可交叉校验

### M3 首次 fastboot boot：UEFI 亮屏（纯 fastboot boot，零刷机）
- [ ] `unixnu build bootimg -D judyp` 产出 boot.img
- [ ] fastboot boot boot.img，观察：串口 0xA84000 日志（CDock/USB 串口）→ cont_splash framebuffer 转储
- [ ] 熄屏/花屏时的诊断路径：RAM dump + framebuffer 范围扫描
- **验证条件**：UEFI 菜单在 V35 屏幕上点亮（或串口确认 UEFI 启动到 DXE 完毕）
- **风险兜底**：若 LG 面板初始化失败，SimpleFbDxe + cont_splash 继承路径（ABL 已点亮的 framebuffer 直接复用）大概率可显示

### M4 内核上线（macOS runner + fastboot boot）
- [ ] enchilada_defconfig fork 为 judyp_defconfig（DTS/机器 ID 差异）
- [ ] GitHub Actions macOS runner 构建 kernelcache（fork 主仓库或用 enchilada 的 workflow 模式）
- [ ] payload（ADT/trust cache/DarwinBoot）→ fastboot boot → XNU 串口日志
- **验证条件**：XNU 启动日志出现在串口（到 launchd 之前即可算里程碑达成）

### M5 可用性（远期）
- 触控 ftm4 驱动移植（enchilada 的 Rmi4Touch 换 FocalTech 协议）
- SW43402 原生显示驱动（摆脱 cont_splash 依赖）
- rootfs 挂载（ userdata 实测 LBA + UFS 驱动已验证）

## 四、风险与对策

| 风险 | 概率 | 对策 |
|---|---|---|
| LG ABL 与 enchiladaPkg 内存假设冲突 | 中 | M2 uefiplat.cfg 实测先行；check 脚本强制校验 |
| SW43402 无法初始化 | 中 | cont_splash 兜底（ABL 已点屏），牺牲分辨率/刷新率灵活性 |
| LLVM 工具链 OOM（7GB RAM） | 中 | 巡检任务监控；失败则加 swap 重试 |
| GitHub 代理不稳定 | 低 | ghfast.top + freedif 镜像双通道已验证 |
| 刷机风险 | — | 全程 fastboot boot，唯一写操作是 M2 的分区 dump（只读）；userdata 占位值已标警告 |

## 五、磁盘预算（D 盘 316G 可用）
- WSL 虚拟盘（D:\WSL\*.vhdx，动态）：工具链 ~8G + Mu-Silicium 1.3G + 构建树 ~5G
- D:\UniXNU-ref：固件/DTS 资料 ~1G
- D:\UniXNU-judyp-bringup：本仓库 <100M
- 合计 <20G，余量充足
