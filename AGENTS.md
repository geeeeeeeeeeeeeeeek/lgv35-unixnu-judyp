# AGENTS.md — judyp（LG V35 ThinQ）XNU 上手工作手册

> 本文件是**操作规程**；实验数据与判读在 `EXPERIMENTS.md`。冲突时以 `EXPERIMENTS.md` 的实测记录为准。

## 0. 铁律（违反即作废）

1. **文档为重、留痕**：计划、推理结论、外部调研、验证门禁、刷机结果，一律当场写进 `EXPERIMENTS.md` 或本文件，不允许只留在对话里。
2. **一轮只回答一个问题**。答案优先级：**二进制（重启/不重启）> 字符串（stage 一行）> 数字**。数字是最后手段。
3. **先计划、设门禁、逐步验证**：任何验证不过，不进入下一步；禁止"先刷了再说"。
4. **只用 A 槽**：`boot_a` + `system_a` + `set_active a`。**任何 `*_b` 操作一律禁止**（B 槽从未成功启动过）。
5. **刷机只用脚本**（`m4/autoflash.ps1` / 本项目脚本），不手敲 fastboot 命令。
6. **fastboot 独占**：任何时刻只允许一个 fastboot 进程；连续调用间隔 ≥1.5s，否则 `Too many links` / `no link`。
7. **刷前 `set_active a`**：复位 retry=7、unbootable=no。
8. **`boot_a` 只允许 `m4/boot-m4-*.img`**；**严禁**把 CI 的 `no-ramdisk/boot.img` 刷进 boot 分区（会秒进 BL）。
9. **失败判定窗口 12~14 秒**（实测离开 fastboot 最慢 10.5s）。
10. 结果一出立刻回写 `EXPERIMENTS.md`，不允许攒着写。
11. **拉包必须走代理**：Windows 侧 `curl.exe --proxy http://127.0.0.1:111`，WSL 侧 `https_proxy=http://172.20.128.1:111`。直连 GitHub / artifact 会 404 或卡死；artifact zip 必须带 `Accept: application/vnd.github+json`。WSL 无 `unzip`，解压用 `python3 -m zipfile`。

## 1. 环境与路径

| 项 | 值 |
|---|---|
| 构建/解包 | WSL `Ubuntu-24.04`，工作区 `/mnt/d/UniXNU-judyp-bringup` |
| WSL 代理 | `http://172.20.128.1:111` |
| Windows curl 代理 | `http://127.0.0.1:111` |
| GitHub token | `/mnt/c/Users/Administrator/AppData/Local/Temp/.ghtok` |
| fastboot | `D:\AndroidSDK\platform-tools\fastboot.exe` |
| 设备 serial | `LMV350NAWMc386b0d5` |
| CI 仓库 | `geeeeeeeeeeeeeeeek/lgv35-unixnu-judyp`，分支 `ci-scale`，workflow `kernel.yml` |
| CI inputs | `defconfig=judyp_defconfig, xcode=26.6, seed_warm=true` |
| 临时脚本目录 | `C:\Users\Administrator\AppData\Local\Temp\ck\`（复杂命令写成 .sh 再 `wsl bash` 执行，避开 PowerShell 转义） |

## 2. 启动链与观测通道

- **面板 stage history = 内核 `kernel_bootstrap_log()` 流**（UniXNU `patches/xnu/zzz-boot-progress.patch` 把该函数转发到 `boot_progress_stage()`）。
- 上游已内置检查点：`arm_vm_init enter/returned`、`PE_init_iokit`、`machine_lockdown`、`PE_lockdown_iokit`、`original PMGR nub`、`bsd_init enter`、`vfs_mountroot enter`、`load_init_program`、`SystemOS/Data mount`。
- 本仓自加的 BC 检查点：`BC10..BC22`（InitIOKit）、`BC30/31/32/33`（startIOServiceMatching）、`BC40/41/42`（PE_lockdown_iokit）、`BC50..BC56`（IODeviceTreeAlloc，R-DT1 新增）。R-DT1 起 `UNI_BC` 宏同时调用 `boot_progress_stage()`（`_boot_progress_stage` 在 kernel.macho 中已定义，不会被链接期抹掉）。
- **`vm_page_wire_count` 计数法已废弃**（ci9 白跑一轮：名字全丢、数字未取到）。
- boot args 在 `board.toml`（`kernel_args` 拼串 ≤1000 字节）。

## 3. 标准一轮流程

1. `EXPERIMENTS.md` 写命题 + 判定表（先写，后做）。
2. 一个补丁；本地 `patch --dry-run` + `git apply --check` 双通过。
3. **dispatch 门禁**：`bash scripts/check-xnu-patch-replay.sh` 必须输出 `TOTAL_FAILURES=0`（该工具按 `unixnu.lock` 的 xnu rev 拉 pristine tarball，复刻 CI 三遍：正向逐个 apply、撤 5 个 LATE 后逐个 reverse-check、倒序全反向再正向）。门禁不过 **禁止 dispatch**。
4. commit → push GitHub `ci-scale` → dispatch（`seed_warm=true`）。
5. CI 绿 → 取 artifact `kernel.macho` → `llvm-strings | grep <标识串>` 确认。
6. 打 payload（或直接用 `out/` 里已有 payload；`payload.py` 超过 95% 会拒绝）。
7. **刷 A 槽**：`set_active a` → `flash boot_a m4/boot-m4-nobtn.img` → `flash system_a <payload.img>` → `set_active a` → `reboot`。
8. 看屏/拍照 → 按判定表回填 `EXPERIMENTS.md`。

## 4. 当前状态（2026-11-21）

- 手机已**全量恢复原厂**，需全量重刷 A 槽。
- 待刷：`boot_a = m4/boot-m4-nobtn.img`，`system_a = out/ci8/payload-df373d8.img`（BC 版，含 BC30–33 / BC40–42，**不需要 CI**）。
- 目标：读 stage 末行 → 判定卡在 `IOWorkLoop::workLoop()` / `registerService` / 已过匹配。
- **已判读（2026-11-21 14:28）**：stage 末行 = `BC18 root nub init` → 卡在 `IOPlatformExpertDevice::init` → `IODeviceTreeAlloc`（ADT→IORegistry 转换）。**不是 lockdown**；旧"PE_lockdown_iokit"为 `PE_init_iokit` 误读。
- 已静态定位的链路：
  `PE_lockdown_iokit → zalloc_iokit_lockdown(4 条指令，不可能卡) → StartIOKitMatching → IOPlatformExpertDevice::startIOServiceMatching → IOWorkLoop::workLoop → IOService::registerService(0) → IOService::startMatching`

- **R-DT1（进行中，2026-11-21）**：新增 `BC50..BC56`（`IODeviceTreeAlloc`）+ 恢复 `UNI_BC` 文本输出；已删除 startup patch 中 bsd_init.c 段（破坏 `zzz-boot-progress` 反向上下文）→ 本地 70 补丁三遍重放 `TOTAL_FAILURES=0`。待 commit/push → 第四次 CI → 取 `kernel.macho` → `llvm-strings` 验 BC50–56 → mcopy 打 payload → 刷 A 槽。

## 5. 明确禁止

- 动 B 槽（`boot_b` / `system_b` / `set_active b`）。
- 把 CI 的 `no-ramdisk/boot.img` 刷进 `boot_a`。
- 并发 fastboot 进程。
- 未在文档里写命题与判定表就刷机。
- 用 wired 计数替代 stage 字符串做判读。
