#!/usr/bin/env bash
#
# release.sh — 从内部 gerrit 源发布一个 BL Vela SDK 版本到 github
#
# 方案 A：wireless / phyrf 在内部编成 .a，github 上只放预编译库。
# 整个流程：内部源 → (编库) → 推 github 各仓 → 打 tag → 生成冻结快照 → 建 release
#
# 设计为“可重复、可中断重跑”。每步独立，失败不污染已成功的步骤。
# 这是骨架：标 TODO 的地方需按内部仓实际地址 / 工具链路径填充。
#
set -euo pipefail

# ============================================================================
# 配置（按内部实际情况填）
# ============================================================================
VERSION="${1:?用法: release.sh <version>  例如 release.sh trunk-5.5.1}"   # 如 trunk-5.5.1
OPENVELA_BASELINE="trunk-5.5"                          # 绑定的 openvela 基线 tag

# 内部 gerrit 源仓（TODO: 换成真实地址）
INT_GERRIT="ssh://gerrit.internal.bouffalolab.com:29418"
INT_VENDOR="${INT_GERRIT}/vela/vendor_bouffalolab"
INT_LHAL="${INT_GERRIT}/bouffalo_sdk/lhal"
INT_WIRELESS="${INT_GERRIT}/bouffalo_sdk/wireless"
INT_PHYRF="${INT_GERRIT}/bouffalo_sdk/phyrf"

# github 目标仓
GH_ORG="git@github.com:bouffalolab"
GH_VENDOR="${GH_ORG}/vela-vendor-bouffalolab.git"
GH_LHAL="${GH_ORG}/bl_lhal.git"
GH_WIRELESS="${GH_ORG}/bl_wireless.git"          # 预编译库仓
GH_PHYRF="${GH_ORG}/bl_phyrf.git"                # 预编译库仓
GH_SDK="${GH_ORG}/vela-manifest.git"            # manifest / 发版入口仓

# RISC-V 工具链（编 wireless/phyrf 用，必须与 openvela trunk-5.5 一致）
# TODO: 指向 openvela prebuilts 里的 riscv-none-elf，保证 ABI 一致
RISCV_TOOLCHAIN="${RISCV_TOOLCHAIN:-/opt/openvela/prebuilts/gcc/linux-x86_64/riscv-none-elf/bin}"

WORK="$(mktemp -d)/bl-vela-release-${VERSION}"
mkdir -p "${WORK}"
echo ">>> 工作目录: ${WORK}"

# ============================================================================
# 步骤 1：镜像源码仓（vela-vendor-bouffalolab / lhal）—— 直接 push 镜像
# ============================================================================
mirror_src() {
  local int_url="$1" gh_url="$2" tag="$3"
  echo ">>> [mirror-src] ${int_url} -> ${gh_url} @ ${tag}"
  local d="${WORK}/$(basename "${gh_url}" .git)"
  git clone --mirror "${int_url}" "${d}"
  git -C "${d}" tag -f "${tag}"                        # 在当前 HEAD 打发版 tag
  # 只推 master/main 分支与本次 tag，不泄露内部所有分支
  git -C "${d}" push "${gh_url}" "+refs/heads/master:refs/heads/release/${OPENVELA_BASELINE}" || true
  git -C "${d}" push "${gh_url}" "refs/tags/${tag}"
}

# ============================================================================
# 步骤 2：编库并发布（wireless / phyrf）—— 源码不上 github，只推 .a
# ============================================================================
build_and_publish_lib() {
  local int_url="$1" gh_url="$2" tag="$3" name="$4"
  echo ">>> [build-lib] ${name} @ ${tag}"
  local src="${WORK}/${name}-src"
  git clone "${int_url}" "${src}"

  # --- 编译（TODO: 换成各库真实的构建命令）---
  export PATH="${RISCV_TOOLCHAIN}:${PATH}"
  pushd "${src}" >/dev/null
    # 同时产出 BL616 / BL618 两套库
    for chip in bl616 bl618; do
      make CHIP="${chip}" CROSS=riscv-none-elf- lib    # TODO: 真实 target
    done
  popd >/dev/null

  # --- 组装预编译库仓：只含 .a + 公开头文件 + 链接片段 ---
  local pub="${WORK}/${name}-pub"
  git clone "${gh_url}" "${pub}" 2>/dev/null || { mkdir -p "${pub}"; git -C "${pub}" init; }
  rm -rf "${pub}/lib" "${pub}/include"
  mkdir -p "${pub}/lib/bl616" "${pub}/lib/bl618" "${pub}/include"
  cp "${src}"/build/bl616/*.a "${pub}/lib/bl616/"      # TODO: 真实产物路径
  cp "${src}"/build/bl618/*.a "${pub}/lib/bl618/"
  cp -r "${src}"/include/*    "${pub}/include/"        # 只拷公开头文件
  # The prebuilt library repository must carry its own NuttX link fragments
  # such as Make.defs/CMakeLists.txt. This SDK repository only owns manifests
  # and release automation, not vendor source or template skeletons.

  cat > "${pub}/VERSION" <<EOF
name: ${name}
version: ${tag}
openvela_baseline: ${OPENVELA_BASELINE}
note: prebuilt library, ABI bound to openvela ${OPENVELA_BASELINE} toolchain
EOF

  git -C "${pub}" add -A
  git -C "${pub}" commit -m "release ${name} ${tag} (baseline ${OPENVELA_BASELINE})"
  git -C "${pub}" tag -f "${tag}"
  git -C "${pub}" push "${gh_url}" "+HEAD:refs/heads/release/${OPENVELA_BASELINE}"
  git -C "${pub}" push "${gh_url}" "refs/tags/${tag}"
}

# ============================================================================
# 步骤 3：生成冻结快照 manifest 并推到 SDK 仓
# ============================================================================
freeze_manifest() {
  echo ">>> [freeze] 生成 tags/bl-vela-sdk-${VERSION}.xml"
  local sdk="${WORK}/vela-manifest"
  git clone "${GH_SDK}" "${sdk}"
  local tree="${WORK}/tree"
  mkdir -p "${tree}"
  pushd "${tree}" >/dev/null
    # 用刚发布的开发清单同步出完整树
    repo init -u "${GH_SDK}" -b "release/${OPENVELA_BASELINE}" -m manifests/bl-vela-sdk.xml
    repo sync -j8 --no-clone-bundle
    # -r 把每个 project 的 HEAD 锁成具体 commit，得到可复现快照
    repo manifest -r -o "${sdk}/manifests/tags/bl-vela-sdk-${VERSION}.xml"
  popd >/dev/null

  git -C "${sdk}" add "manifests/tags/bl-vela-sdk-${VERSION}.xml"
  git -C "${sdk}" commit -m "freeze: bl-vela-sdk-${VERSION} (openvela ${OPENVELA_BASELINE})"
  git -C "${sdk}" tag -f "bl-vela-sdk-${VERSION}"
  git -C "${sdk}" push "${GH_SDK}" "HEAD:refs/heads/release/${OPENVELA_BASELINE}"
  git -C "${sdk}" push "${GH_SDK}" "refs/tags/bl-vela-sdk-${VERSION}"
}

# ============================================================================
# 步骤 4：建 github release（产物 + Release Notes）
# ============================================================================
make_github_release() {
  echo ">>> [release] gh release create bl-vela-sdk-${VERSION}"
  # TODO: 用 gh CLI；附上冻结 manifest 与 SBOM
  gh release create "bl-vela-sdk-${VERSION}" \
    --repo bouffalolab/vela-manifest \
    --title "BL Vela SDK ${VERSION}" \
    --notes-file "${WORK}/RELEASE_NOTES.md" \
    "${WORK}/vela-manifest/manifests/tags/bl-vela-sdk-${VERSION}.xml"
}

# ============================================================================
# 主流程
# ============================================================================
main() {
  mirror_src       "${INT_VENDOR}"   "${GH_VENDOR}"   "bl-vela-sdk-${VERSION}"
  mirror_src       "${INT_LHAL}"     "${GH_LHAL}"     "lhal-${VERSION}"
  build_and_publish_lib "${INT_WIRELESS}" "${GH_WIRELESS}" "wireless-${VERSION}" "wireless"
  build_and_publish_lib "${INT_PHYRF}"    "${GH_PHYRF}"    "phyrf-${VERSION}"    "phyrf"
  freeze_manifest
  make_github_release
  echo ">>> 完成。冻结快照: tags/bl-vela-sdk-${VERSION}.xml"
  echo ">>> 验证复现: repo init -u ${GH_SDK} -b bl-vela-sdk-${VERSION} -m tags/bl-vela-sdk-${VERSION}.xml && repo sync"
}

main "$@"
