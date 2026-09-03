#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p build && cd build

if [[ -z ${SUITE} ]]; then
    echo "Error: SUITE is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/suites/${SUITE}.sh"

# Clone/refresh the kernel repo.
# ⚠️ FLAVOR LESSON (2026-07-27): the working clone is shallow + single-branch, so a
# plain `pull` only refreshes whatever flavor built LAST — switching Studio<->Desktop
# then died at checkout ("pathspec did not match"). Always fetch the REQUESTED branch
# from origin and hard-point the local branch at it.
if [ -d linux-rockchip/.git ]; then
    git -C linux-rockchip fetch --depth=2 origin "${KERNEL_BRANCH}" \
        || { echo "Error: branch ${KERNEL_BRANCH} not found in ${KERNEL_REPO}"; exit 1; }
    cd linux-rockchip
    git checkout -B "${KERNEL_BRANCH}" FETCH_HEAD
else
    git clone --progress -b "${KERNEL_BRANCH}" "${KERNEL_REPO}" linux-rockchip --depth=2
    cd linux-rockchip
    git checkout "${KERNEL_BRANCH}"
fi

# shellcheck disable=SC2046
export $(dpkg-architecture -aarm64)
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=aarch64-linux-gnu-gcc
export LANG=C

# Scrub build-host identity from the kernel version banner (/proc/version, uname -a).
# Left unset, mkcompile_h falls back to whoami@hostname = root@<real-build-host>,
# baking the builder's real name into every shipped image. Pin to project identity
# so Pi Studio ships clean. (Nothing in debian/rules overrides these — the current
# debs leak the real hostname precisely because these are unset.)
export KBUILD_BUILD_USER=defcom5-rockchip
export KBUILD_BUILD_HOST=pi-studio-builder

# Host is GCC 15 / Ubuntu 26.04; the 6.1 vendor tree predates GCC 14+ promoting
# warnings (e.g. discarded-qualifiers) to hard errors.
#
# Kernel proper: 6.1 sets CONFIG_WERROR=y, so relax it via KCFLAGS (honoured by
# the main Kbuild and the rockchip debian/rules).
export KCFLAGS="-Wno-error"
#
# Host tools: resolve_btfids builds bundled libbpf + libsubcmd, whose Makefiles
# do `override CFLAGS += -Werror` *after* EXTRA_CFLAGS, so HOSTCFLAGS/-Wno-error
# can't win — the later -Werror always overrides it. Strip the hardcoded -Werror
# token directly from the freshly-checked-out tools Makefiles (objtool + perf
# too, to pre-empt the next GCC 15 site). cwd is the kernel root here; this is
# idempotent across re-runs since `git checkout` above restores -Werror first.
for mk in tools/lib/bpf/Makefile tools/lib/subcmd/Makefile \
          tools/objtool/Makefile tools/lib/perf/Makefile; do
    [ -f "$mk" ] && sed -i -E 's/(^|[[:space:]])-Werror([[:space:]]|$)/\1\2/g' "$mk"
done

# Compile the kernel into a deb package.
# Backend = fakeroot-SYSV (the distro default). fakeroot-TCP was tried to dodge a
# SysV "payload not recognized" error -- but that only bites under CONCURRENT bakes
# corrupting the shared msg-queue; a single clean build is fine on SysV (proven
# 2026-06-30 = KERNEL DONE). Meanwhile fakeroot-TCP repeatedly died here with
# "libfakeroot: connect: Permission denied" (this host's firewall stack blocks the
# faked-tcp socket even with ufw down) -> tar broken pipe on kheaders_data.tar.xz.
# SysV uses IPC msg-queues, no network -> firewall is a non-issue. Keep it SysV;
# just don't run two bakes at once, and clear stale msg-queues if payload errors recur.
# NB: call fakeroot-sysv by its EXPLICIT path, not the `fakeroot` alias -- the
# update-alternatives link on this host was flipped to fakeroot-tcp (which fails
# with "connect: Permission denied" behind the firewall). Explicit = immune to that.
fakeroot-sysv debian/rules clean binary-headers binary-rockchip do_mainline_build=true
