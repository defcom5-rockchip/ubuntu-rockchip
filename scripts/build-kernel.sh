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

# Clone the kernel repo
if ! git -C linux-rockchip pull; then
    git clone --progress -b "${KERNEL_BRANCH}" "${KERNEL_REPO}" linux-rockchip --depth=2
fi

cd linux-rockchip
git checkout "${KERNEL_BRANCH}"

# shellcheck disable=SC2046
export $(dpkg-architecture -aarm64)
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=aarch64-linux-gnu-gcc
export LANG=C

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

# Compile the kernel into a deb package
fakeroot debian/rules clean binary-headers binary-rockchip do_mainline_build=true
