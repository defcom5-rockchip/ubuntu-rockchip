# shellcheck shell=bash

export RELASE_NAME="Ubuntu 24.04 LTS (Noble Nombat)"
export RELASE_VERSION="24.04"

# TEST BUILD: source the patched VOP2 4K@120Hz branch from the local 5TB clone.
# Revert these two lines (restore the GitHub origin + noble-security) for release.
#export KERNEL_REPO="https://github.com/defcom5-rockchip/linux-rockchip-rk3588.git"
#export KERNEL_BRANCH="noble-security"
# PI STUDIO LOW-LATENCY TEST (2026-06): pi-studio-lowlatency branch = PREEMPT +
# HZ_1000 stacked on vop2-4k120hz, from the ext4 build-drive clone. To revert,
# re-enable the vop2-4k120hz lines below (or the release lines above).
export KERNEL_REPO="file:///mnt/build/PI_Studio/linux-rockchip-fork"
# v1.2: low-latency+4K@120 stack + cherry-picked BT/USB-audio CVE fixes (BSP is EOL — see LAST-SECOND-HANDOFF §3).
# The known-good pre-CVE branch stays as pi-studio-lowlatency-noafbc.
# FLAVOR OVERRIDE (Pi Desktop): set PISTUDIO_KERNEL_BRANCH=pi-desktop-4k120-cve for the
# throughput kernel (same stack, LL-config commit reverted -> PREEMPT_VOLUNTARY / HZ=300).
# Unset = Pi Studio's low-latency kernel, so Studio bakes are 100% unchanged.
export KERNEL_BRANCH="${PISTUDIO_KERNEL_BRANCH:-pi-studio-ll-noafbc-cve-v1.2}"
#export KERNEL_BRANCH="vop2-4k120hz"
export KERNEL_FLAVOR="rockchip"

export EXTRA_PPAS="jjriek/rockchip jjriek/rockchip-multimedia"
