# BL Vela SDK

芯片原厂（Bouffalo Lab）维护的、基于 openvela 的长期演进 SDK。

> **一句话定位**：本仓库 = **集成清单 + CI + 发版入口**，不放驱动源码。
> 它用 repo manifest 把「openvela 基座 + BL 驱动适配层 + 复用驱动仓」三者钉版冻结，
> 让任何人都能 100% 复现某个 SDK 版本。

---

## 1. 三层治理模型

| 层 | 内容 | Owner | 载体 |
|---|---|---|---|
| OS 基座 | openvela | 小米 Vela | github/open-vela（**trunk-5.5 tag 为同步点**） |
| **BL Vela SDK** | 基座 + BL 芯片移植/驱动/板级 + 复用驱动 | **Bouffalo Lab（本仓）** | 本仓 + vendor/bl 系列仓 |
| 产品 | SDK + 业务代码 | 下游产品团队 | 产品内部仓（拉分支作为产品 commit 原点） |

**职责边界（已与各方约定）**
- **基线来源**：以 github/open-vela 的 `trunk-5.5` tag 为准。小米 Vela 保证该 tag 与其内部基线等价。
- **集成清单归属**：最终产品 manifest 由**下游产品团队拥有**，引用本 SDK 的 vendor tag。本仓的 manifest 仅用于 BL 自家 CI / 发版 / 验证基准。
- **Review 门禁**：BL **自管主线**（vela-vendor-bouffalolab 等仓）；下游产品团队仅在采纳某个 SDK tag 进产品时做准入 review。
- **源与分发分离**：源码 + review 在 BL 内部 gerrit；github 是**对外分发镜像**，下游消费方永不接触内部仓。

---

## 2. 仓库拓扑

```
github/open-vela/*                         OS 基座（小米 Vela，trunk-5.5 tag）
github/bouffalolab/vela-manifest            ← 本仓：manifest + CI + 发版入口
github/bouffalolab/vela-nuttx               OpenVela NuttX 的 public SDK 集成 fork
github/bouffalolab/vela-nuttx-apps          OpenVela apps 的 public SDK 集成 fork
github/bouffalolab/vela-external-zblue      OpenVela zblue（BLE host）的 public SDK 集成 fork
github/bouffalolab/vela-vendor-bouffalolab  BL 适配层：芯片/板级/驱动/中间件/示例/工具（源码镜像）
github/bouffalolab/bl_lhal                 寄存器级 HAL（源码，复用自 bouffalo_sdk）
github/bouffalolab/bl_wireless             无线协议栈（★预编译库 .a，方案 A）
github/bouffalolab/bl_phyrf                PHY/RF 校准（★预编译库 .a，方案 A）
```

> **方案 A**：wireless / phyrf 不公开源码——在 BL 内部用 openvela 同款工具链编成 `.a`，
> 只把库 + 公开头文件推到 github。详见 §5。

> **当前状态**：`manifests/bl-vela-sdk.xml` 以 openvela trunk 全量基座为默认来源，
> `nuttx`/`apps`/`external/zblue/zblue` 跟随已合入补丁的 Bouffalo Lab public fork `trunk`；BL616CL chip、
> Ai-M64L-32S-Kit board、LHAL wrapper 和只读 drivers project 已接入并完成标准构建与
> 实板回归。无线预编译库仍按具体 SDK 版本独立冻结；收敛路径见 §7。
> 两个 remote 用的是**相对路径**（`../open-vela/`、`../bouffalolab/`），
> 即 open-vela 与 bouffalolab 必须与本清单仓位于同一 Git host 的同级命名空间下。

### vela-vendor-bouffalolab 内部结构

```
vela-vendor-bouffalolab/
├── chips/          芯片移植（custom chip；按 defconfig CONFIG_ARCH_CHIP_CUSTOM_DIR 纳入）
├── boards/         板级（custom board；按 CONFIG_ARCH_BOARD_CUSTOM_DIR 纳入）
├── drivers/        驱动 —— 各自独立 .a（顶层 nuttx_add_subdirectory 自动发现）
├── components/     中间件/可复用组件 —— 各自独立 .a（含"外层包装"导入独立仓，如 lhal）
├── examples/       示例 app（nuttx_add_application）
├── tools/          宿主侧脚本/烧录（★无 CMakeLists，不编入固件）
├── CMakeLists.txt  顶层接入：nuttx_add_subdirectory + Kconfig 菜单 "Bouffalo Lab"
└── LICENSE         Apache-2.0
```

> chips/boards 由 kernel/arch 侧按 custom-dir 纳入；components/examples 由顶层一层
> glob 自动发现；drivers 由显式 CMake wrapper 选择，tools 不编入固件。构建走
> CMake+Ninja，细节见仓内 `README.md`。

---

## 3. 版本号语义

格式：`bl-vela-sdk-<openvela基线>.<SDK迭代号>`，例：`bl-vela-sdk-trunk-5.5.1`

- `<openvela基线>`：本版本绑定的 openvela tag（如 `trunk-5.5`）。
- `<SDK迭代号>`：在该基线上的驱动功能/bugfix 累积号（`.0 .1 .2 …`）。
- 分支：`release/trunk-5.5` 持续出 `5.5.0 / 5.5.1 / …`。
- openvela 升到 5.6 → 拉 `release/trunk-5.6` 出 `5.6.0`，**同时 5.5.x 继续维护一段时间**（双线并行）。

**预编译库的版本绑定（硬约束）**：`bl_wireless` / `bl_phyrf` 的 ABI 必须与 openvela 基线工具链一致。
基线换工具链（如 5.5→5.6）→ 这两个库**必须重编重发**，tag 随基线走（`wireless-trunk-5.5.1`）。

---

## 4. 使用方式

### 4.1 开发 / 跟最新（开发清单）
```bash
repo init -u git@github.com:bouffalolab/vela-manifest.git \
          -b release/trunk-5.5 \
          -m manifests/bl-vela-sdk.xml
repo sync -j8
# repo checkout 会跳过 LFS smudge，构建前显式拉取 vendor 工具二进制
git -C vendor/bouffalolab lfs pull bouffalo
# BL616CL 标准构建入口（CMake + Ninja）
vendor/bouffalolab/vela build \
  bl616cl/ai-m64l-32s-kit/configs/nsh -j14
```
> 开发清单仍以 openvela `trunk` 作为普通 project 的默认基线；`apps` 和 `nuttx` 例外，
> 跟随 public 的 `bouffalolab/vela-nuttx-apps:trunk`、`bouffalolab/vela-nuttx:trunk`。组织主线 PR
> 合并前必须绑定 fresh sync、BL616CL 构建和受影响能力回归证据，并由非作者 review
> 核对；required CI checks 建立后再将这些门禁自动化。发布清单才固定精确 SHA。
>
> `repo` 为 project checkout 配置 `filter.lfs.*=--skip`，所以 `repo sync` 成功不代表
> `vendor/bouffalolab` 的 LFS 文件已展开。缺少上述 `git lfs pull` 时，固件后处理工具仍是
> LFS pointer，后处理阶段会失败；这不应记录成源码编译失败。
>
> 清单改了某个 project 的 `name`（如 `external/zblue/zblue` 改为 `vela-external-zblue`）后，
> 已有工作区要用 `repo sync --force-sync <path>`，它会删掉并重建该 project 的工作目录。
> 若报 `hooks is different`，先删除 `.repo/projects/<path>.git` 和
> `.repo/project-objects/<新 name>.git` 再重试。被重建的 project 里嵌套的其他 project
> （如 `nuttx`、`apps` 下的第三方库）会被一起删掉，之后用 `repo sync -l` 从本地对象恢复。

### 4.2 复现某个发版（冻结快照）
```bash
repo init -u git@github.com:bouffalolab/vela-manifest.git \
          -b bl-vela-sdk-trunk-5.5.1 \
          -m manifests/tags/bl-vela-sdk-trunk-5.5.1.xml
repo sync -j8
```

> `5.5.1` 是历史清单：它仍使用 `refs/tags/trunk-5.5`，且没有纳入当前
> `vendor/bouffalolab`，不满足现行“逐 project 精确 SHA + 完整 BL project 集合”的
> 冻结合同，不能据此声称当前 BL616CL SDK bit-for-bit 可复现。后续发版必须新建由
> `repo manifest -r` 生成并完成 fresh sync/build 回归的 tag manifest；历史文件不修改。

### 4.3 下游产品消费（产品侧）
产品侧在自己的 product manifest 中引用本 SDK 的 vendor tag，叠加业务码后发版。
本 SDK 的冻结快照可作为产品 manifest 的 `<include>` 基底。

---

## 5. 发版流程

由 `scripts/release.sh` 自动化，串起：

```
内部 gerrit 源（review 通过）
  │
  ├─ vela-vendor-bouffalolab / lhal ── 镜像 push ──▶ github 源码仓 + 打 tag
  │
  ├─ wireless / phyrf ── 内部编 .a（openvela 同款工具链）──▶ github 库仓 + 打 tag
  │
  ├─ 同步出完整树 → repo manifest -r → 冻结快照 tags/bl-vela-sdk-X.Y.Z.xml ──▶ 本仓
  │
  └─ gh release create（附冻结清单 + Release Notes）
```

执行：`scripts/release.sh trunk-5.5.1`（脚本内 TODO 项需按内部实际地址/工具链填充）。

---

## 6. ⚠️ 主线纪律（治理关键）

**任何为某个产品做的驱动改动，必须同步进 `vela-vendor-bouffalolab` 主线。**

否则会出现「产品分支领先、SDK 主线腐烂」——这正是本 SDK 要消除的风险。
建议在 CI 卡：产品分支的驱动 commit 若无对应主线 cherry-pick，标红告警。

---

## 7. manifest 收敛流程（全量基座 → 最小闭包）

`manifests/bl-vela-sdk.xml` 当前以 **openvela trunk 全量基座**为默认来源（约 170 个
project），但 `apps`/`nuttx` 跟随 Bouffalo Lab public fork 的受保护 `trunk`；
`vendor/bouffalolab` 和独立只读的 `vendor/bouffalolab/drivers` 已接入。先保证清单可以
fresh sync、完成 BL616CL 标准构建和运行回归，再逐步收敛。

```
1. 接入 BL 适配层：已接入 vendor/bouffalolab 与只读 drivers project
2. 维护 BL616CL Ai-M64L-32S-Kit 的可复现 defconfig
3. repo sync 全量 → LFS pull → BL616CL 编译和运行回归，记录实际被引用的 project
4. 反向裁剪：删掉编译用不到的子系统
5. 回到 3，迭代到能干净编出固件 → 剩下的就是真实最小闭包
```

**当前仍保留、待裁剪确认**：vendor/xiaomi 系列、全部 benchmarks、
未用的 graphics/interpreters、四平台（linux/darwin/windows）工具链
（gcc/build-tools/cmake，由 `groups="notdefault,platform-*"` 控制按平台拉取）。
> 早期构想里这份清单是"起步最小集再往上加"，现已反转为"全量基座再往下裁"——
> 大方向（钉版冻结、可复现、BL 自管主线）不变，只是收敛起点换了。

---

## 8. CI

`.github/workflows/ci-build.yml`：仅 BL616/BL618 编译冒烟。
public 仓 + github 标准 runner = 免费。重型全量编译/测试仍在内部 CI。

---

## 目录

```
manifests/
  bl-vela-sdk.xml                   开发清单（openvela 基座 + BL OS fork trunk）
  tags/
    bl-vela-sdk-trunk-5.5.1.xml     冻结快照样例（发版时脚本生成，钉 refs/tags/trunk-5.5）
scripts/
  release.sh                        发版自动化（内部→github）
```
> repo init 入口由 `.repo/manifest.xml` 经 `<include name="manifests/bl-vela-sdk.xml"/>`
> 选定，已无独立的 `default.xml`。
