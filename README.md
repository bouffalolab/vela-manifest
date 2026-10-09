# BL Vela SDK

芯片原厂（Bouffalo Lab）维护的、基于 openvela 的长期演进 SDK。

> **一句话定位**：本仓库 = **集成清单 + 发版入口**，不放驱动源码。
> 它用 repo manifest 组合「openvela 基座 + BL 驱动适配层 + 复用驱动仓」。设计目标是按版本
> 钉版冻结、让任何人都能复现某个 SDK 版本；**当前仍在开发期**，两份清单都跟踪各仓分支，
> 还没有发版快照（见 §3、§4.2）。

---

## 1. 三层治理模型

| 层 | 内容 | Owner | 载体 |
|---|---|---|---|
| OS 基座 | openvela | 小米 Vela | github/open-vela（开发期跟 `trunk`；发版同步点按设计为 `trunk-5.5` tag） |
| **BL Vela SDK** | 基座 + BL 芯片移植/驱动/板级 + 复用驱动 | **Bouffalo Lab（本仓）** | 本仓 + vendor/bl 系列仓 |
| 产品 | SDK + 业务代码 | 下游产品团队 | 产品内部仓（拉分支作为产品 commit 原点） |

**职责边界（已与各方约定）**
- **基线来源**：发版以 github/open-vela 的 `trunk-5.5` tag 为准，小米 Vela 保证该 tag 与其内部基线等价；开发期清单跟踪 openvela `trunk`。
- **集成清单归属**：最终产品 manifest 由**下游产品团队拥有**，引用本 SDK 的发版 tag（发版流程建立后）。本仓的 manifest 用于 BL 自家开发、发版和验证基准。
- **Review 门禁**：BL **自管主线**（vela-vendor-bouffalolab 等仓）；下游产品团队仅在采纳某个 SDK 版本进产品时做准入 review。
- **源与分发**：vela-vendor-bouffalolab 和三个 openvela fork 直接在 GitHub 开发；drivers、supplicant 是 Bouffalo SDK 对应目录的只读镜像；macsw、wl80211 源码只在内部仓，对外以预编译包形式放在 vela-vendor-bouffalolab。使用对外清单的用户不接触内部仓。

---

## 2. 仓库拓扑

```
github/open-vela/*                                OS 基座（默认 revision trunk）
github/bouffalolab/vela-manifest                  ← 本仓：manifest（main 分支）
github/bouffalolab/vela-nuttx                     OpenVela NuttX 的 public SDK 集成 fork（trunk）
github/bouffalolab/vela-nuttx-apps                OpenVela apps 的 public SDK 集成 fork（trunk）
github/bouffalolab/vela-external-zblue            OpenVela zblue（BLE host）的 public SDK 集成 fork（trunk）
github/bouffalolab/vela-vendor-bouffalolab        BL 适配层 → vendor/bouffalolab（trunk）
github/bouffalolab/bouffalo_sdk-drivers           Bouffalo SDK drivers/ 只读镜像（lhal、soc、rfparam、
                                                  预编译 phyrf）→ vendor/bouffalolab/drivers（master）
github/bouffalolab/bouffalo_sdk-bl_wpa_supplicant Bouffalo SDK supplicant 只读镜像（master）
内部仓 macsw、wl80211 public/private             仅开发清单引用（remote blgerrit）
```

> **无线库**：macsw、wl80211 不公开源码。对外清单使用 vela-vendor-bouffalolab 中用 openvela
> 工具链编出的预编译包（`components/wireless/wifi/{macsw,wl80211}/prebuilt/`），BLE controller
> 预编译库也提交在 vela-vendor-bouffalolab，phyrf 预编译库随 drivers 镜像发布。
>
> **当前状态**：两份清单都以 openvela trunk 全量基座为默认来源，`nuttx`/`apps`/`external/zblue/zblue`
> 跟随 Bouffalo Lab public fork `trunk`。BL616CL chip、Ai-M64L-32S-Kit board、驱动 wrapper、
> Wi-Fi STA 和 BLE 已接入并完成构建与实板回归；收敛路径见 §7。
> `openvela`、`bouffalo` 两个 remote 用的是**相对路径**（`../open-vela/`、`../bouffalolab/`），
> 即 open-vela 与 bouffalolab 必须与本清单仓位于同一 Git host 的同级命名空间下；
> 开发清单另有指向内部仓的 `blgerrit` remote。

### vela-vendor-bouffalolab 内部结构

```
vela-vendor-bouffalolab/
├── chips/          芯片移植（custom chip；按 defconfig CONFIG_ARCH_CHIP_CUSTOM_DIR 纳入）
├── boards/         板级（custom board；按 CONFIG_ARCH_BOARD_CUSTOM_DIR 纳入）
├── drivers/        独立 project（drivers 只读镜像），由 cmake/ 下的 wrapper 显式选择源码
├── components/     中间件（wireless/：wifi、ble、rfparam），顶层自动发现
├── apps/           测试与示例 app（nuttx_add_application），顶层自动发现
├── cmake/          构建辅助（驱动 wrapper、组件 helper、Wi-Fi 源码/预编译选择）
├── docs/           BL616CL 功能文档
├── tools/          宿主侧工具（固件后处理、FlashCube、性能工具；无 CMakeLists，不编入固件）
├── vela            构建/烧录入口（manifest 链接到 SDK 根目录）
├── CMakeLists.txt  顶层接入：nuttx_add_subdirectory + Kconfig 菜单 "Bouffalo Lab"
└── LICENSE         Apache-2.0
```

> chips/boards 由 kernel/arch 侧按 custom-dir 纳入；components/apps 由顶层逐层 glob
> 自动发现；drivers 由显式 CMake wrapper 选择，tools 不编入固件。构建走
> CMake+Ninja，细节见该仓 `README.md`。

---

## 3. 版本号语义（设计，尚未实施）

当前没有 release 分支和发版 tag，本节是后续自动化发版的约定。

格式：`bl-vela-sdk-<openvela基线>.<SDK迭代号>`，例：`bl-vela-sdk-trunk-5.5.1`

- `<openvela基线>`：本版本绑定的 openvela tag（如 `trunk-5.5`）。
- `<SDK迭代号>`：在该基线上的驱动功能/bugfix 累积号（`.0 .1 .2 …`）。
- 分支：`release/trunk-5.5` 持续出 `5.5.0 / 5.5.1 / …`。
- openvela 升到 5.6 → 拉 `release/trunk-5.6` 出 `5.6.0`，**同时 5.5.x 继续维护一段时间**（双线并行）。

**预编译库的版本绑定（硬约束）**：macsw/wl80211 预编译包、phyrf 和 BLE controller 库的 ABI
必须与 openvela 基线工具链一致。macsw/wl80211 预编译包是 fat LTO 对象，只能配编出它的
GCC 版本；基线换工具链（如 5.5→5.6）时必须重新导出，其余预编译库须重新验证或重编。

---

## 4. 使用方式

### 4.0 对外使用（对外清单）

`manifests/bl-vela-sdk-release.xml` 与开发清单相同，只是不含内部源码仓；Wi-Fi 的
macsw/wl80211 使用 `vendor/bouffalolab` 中的预编译包。它跟踪各 project 的分支，不固定版本。

先安装 `repo` 和 `git-lfs`，并执行一次 `git lfs install`（开发清单同样需要）。`repo sync`
不下载 LFS 对象，必须再执行下面的 `lfs pull`，原因见 4.1 的说明。

```bash
repo init -u https://github.com/bouffalolab/vela-manifest.git \
          -b main -m manifests/bl-vela-sdk-release.xml
repo sync -j8
git -C vendor/bouffalolab lfs pull bouffalo
./vela build ai-m64l-32s-kit/wifi
```

### 4.1 开发 / 跟最新（开发清单）
```bash
repo init -u git@github.com:bouffalolab/vela-manifest.git \
          -b main \
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

暂无可复现的发版：本仓远端只有 `main` 分支，没有发版 tag。

`manifests/tags/bl-vela-sdk-trunk-5.5.1.xml` 是早期样例：它把 openvela 钉在
`refs/tags/trunk-5.5`，且没有纳入 `vendor/bouffalolab`，不能复现当前 BL616CL SDK。
需要查看时从 `main` 初始化：

```bash
repo init -u https://github.com/bouffalolab/vela-manifest.git \
          -b main -m manifests/tags/bl-vela-sdk-trunk-5.5.1.xml
```

> 后续发版必须新建由 `repo manifest -r` 生成、逐 project 精确 SHA、包含完整 BL project
> 集合并完成 fresh sync/build 回归的 tag manifest；历史样例不修改。

### 4.3 下游产品消费（产品侧）
发版流程建立后，产品侧在自己的 product manifest 中引用本 SDK 的发版 tag，叠加业务码后发版；
本 SDK 的冻结快照可作为产品 manifest 的 `<include>` 基底。在此之前只能基于跟踪分支的清单
自行记录 SHA。

---

## 5. 发版流程（待建立）

自动化发版流程尚未建立，计划包含：

```
内部仓 macsw/wl80211 更新 ── 用 openvela 工具链重新导出预编译包 ──▶ vela-vendor-bouffalolab
  │
  ├─ 各仓打 tag（vendor、openvela fork、drivers/supplicant 镜像对应版本）
  │
  ├─ 同步出完整树 → repo manifest -r → 冻结快照 tags/bl-vela-sdk-X.Y.Z.xml ──▶ 本仓
  │
  └─ gh release create（附冻结清单 + Release Notes）
```

目前 macsw/wl80211 预编译包由 vela-vendor-bouffalolab 的 `tools/bl616cl/export_wifi_prebuilt.sh`
手动导出。`scripts/release.sh` 是早期占位脚本，内容已过时，不要使用。

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

暂无自动 CI：本仓没有 workflow。合入前按 §4.1 的要求手动完成 fresh sync、构建和回归。

---

## 目录

```
manifests/
  bl-vela-sdk.xml                   开发清单（openvela 基座 + BL fork trunk + 内部无线源码仓）
  bl-vela-sdk-release.xml           对外清单（不含内部源码仓，Wi-Fi 用预编译包）
  tags/
    bl-vela-sdk-trunk-5.5.1.xml     早期冻结快照样例（钉 refs/tags/trunk-5.5，不含 vendor）
scripts/
  release.sh                        早期发版占位脚本（已过时，不要使用）
```
> repo init 入口由 `.repo/manifest.xml` 经 `<include name="manifests/bl-vela-sdk.xml"/>`
> 选定，已无独立的 `default.xml`。
