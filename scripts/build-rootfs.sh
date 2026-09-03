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

if [[ -z ${FLAVOR} ]]; then
    echo "Error: FLAVOR is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/flavors/${FLAVOR}.sh"

if [[ -f ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz ]]; then
    exit 0
fi

pushd .

tmp_dir=$(mktemp -d)
cd "${tmp_dir}" || exit 1

# Clone the livecd rootfs fork
git clone https://github.com/Joshua-Riek/livecd-rootfs
cd livecd-rootfs || exit 1

# Install build deps
apt-get update
apt-get build-dep . -y

# Build the package
dpkg-buildpackage -us -uc

# Install the custom livecd rootfs package
apt-get install ../livecd-rootfs_*.deb --assume-yes --allow-downgrades --allow-change-held-packages
dpkg -i ../livecd-rootfs_*.deb
apt-mark hold livecd-rootfs

rm -rf "${tmp_dir}"

popd

mkdir -p live-build && cd live-build

# Query the system to locate livecd-rootfs auto script installation path
cp -r "$(dpkg -L livecd-rootfs | grep "auto$")" auto

set +e

export ARCH=arm64
export IMAGEFORMAT=none
export IMAGE_TARGETS=none

# Populate the configuration directory for live build
lb config \
    --architecture arm64 \
    --bootstrap-qemu-arch arm64 \
    --bootstrap-qemu-static /usr/bin/qemu-aarch64-static \
    --archive-areas "main restricted universe multiverse" \
    --parent-archive-areas "main restricted universe multiverse" \
    --mirror-bootstrap "https://ports.ubuntu.com" \
    --parent-mirror-bootstrap "https://ports.ubuntu.com" \
    --mirror-chroot-security "https://ports.ubuntu.com" \
    --parent-mirror-chroot-security "https://ports.ubuntu.com" \
    --mirror-binary-security "https://ports.ubuntu.com" \
    --parent-mirror-binary-security "https://ports.ubuntu.com" \
    --mirror-binary "https://ports.ubuntu.com" \
    --parent-mirror-binary "https://ports.ubuntu.com" \
    --keyring-packages ubuntu-keyring \
    --linux-flavours "${KERNEL_FLAVOR}"

if [ "${SUITE}" == "noble" ] || [ "${SUITE}" == "jammy" ]; then
    # Pin rockchip package archives
    (
        echo "Package: *"
        echo "Pin: release o=LP-PPA-jjriek-rockchip"
        echo "Pin-Priority: 1001"
        echo ""
        echo "Package: *"
        echo "Pin: release o=LP-PPA-jjriek-rockchip-multimedia"
        echo "Pin-Priority: 1001"
    ) > config/archives/extra-ppas.pref.chroot
fi

if [ "${SUITE}" == "noble" ]; then
    # Ignore custom ubiquity package (mistake i made, uploaded to wrong ppa)
    (
        echo "Package: oem-*"
        echo "Pin: release o=LP-PPA-jjriek-rockchip-multimedia"
        echo "Pin-Priority: -1"
        echo ""
        echo "Package: ubiquity*"
        echo "Pin: release o=LP-PPA-jjriek-rockchip-multimedia"
        echo "Pin-Priority: -1"

    ) > config/archives/extra-ppas-ignore.pref.chroot
fi

# Snap packages to install — defcom5: Pi Studio is SNAP-FREE, seed NONE.
# Empty list = no snap downloads (avoids the lxd "killed snap" failure at the
# lb build step) AND no preseeded snaps in the image. snapd still arrives as a
# desktop-seed dependency, but 62-pi-studio-browser.hook.chroot purges it.
# (To restore stock snaps, re-add snapd/core22/lxd lines below.)
: > config/seeded-snaps

# Generic packages to install
echo "software-properties-common" > config/package-lists/my.list.chroot

if [ "${PROJECT}" == "ubuntu" ]; then
    # Specific packages to install for ubuntu desktop
    (
        echo "ubuntu-desktop-rockchip"
        echo "oem-config-gtk"
        echo "ubiquity-frontend-gtk"
        echo "ubiquity-slideshow-ubuntu"
        echo "localechooser-data"
    ) >> config/package-lists/my.list.chroot
else
    # Specific packages to install for ubuntu server.
    # ubuntu-server-rockchip is a jjriek PPA metapackage — it exists only for the
    # BSP suites that add those PPAs. A stock/mainline suite (resolute) has no
    # jjriek archive, so asking for it fails the build with "Unable to locate
    # package". Use Ubuntu's own metapackage there.
    if [ "${KERNEL_SOURCE:-forge}" == "stock" ]; then
        (
            echo "ubuntu-server"
            echo "linux-firmware"        # base blobs; the AP6275P set rides in our overlay
            echo "network-manager"       # NNP needs WiFi config without a desktop
            # mtd-utils is a hard Depends of our u-boot deb. On the BSP suites it
            # arrived via the jjriek ubuntu-server-rockchip metapackage; plain
            # ubuntu-server doesn't pull it, so dpkg -i left u-boot unconfigured
            # and killed the bake at the u-boot install.
            echo "mtd-utils"
            echo "u-boot-menu"           # provides u-boot-update -> extlinux.conf
            # NO initramfs-tools. Ubuntu 26.04 has moved to dracut as the default
            # initramfs generator, and initramfs-tools Conflicts linux-initramfs-tool
            # (which dracut provides) — requesting it makes apt unsatisfiable:
            #   "initramfs-tools is selected for removal because dracut is selected
            #    for install". Let the distro pick its own tool; config-image.sh
            #    handles either generator.
            echo "openssh-server"        # NNP is an SSH-first box; don't leave it to a metapackage
            echo "file"                  # network-manager.postinst shells out to it (line 130)
            # cloud-init is NOT optional on the ubuntu-cpc project: 11 references
            # across the upstream livecd-rootfs hooks, and 012-cpc-fixes does a
            # `dpkg-reconfigure cloud-init` that hard-fails without it. The forge
            # already ships its config (overlay/boot/firmware/{user-data,
            # network-config,meta-data}), so it was always assumed present — the
            # jjriek server metapackage just used to pull it in silently.
            echo "cloud-init"
        ) >> config/package-lists/my.list.chroot
    else
        echo "ubuntu-server-rockchip" >> config/package-lists/my.list.chroot
    fi
fi

# defcom5: build & install WiiM Play from source (desktop only). The hook source
# lives in the repo at config/hooks/normal/; copy it into the live-build config
# so `lb build` runs it inside the arm64 chroot. See the hook header for details.
if [ "${PROJECT}" == "ubuntu" ]; then
    # defcom5: Ubuntu 26.04's live-build (livecd-rootfs fork, lb 3.0~a57) runs
    # config/hooks/*.chroot — NOT the Debian config/hooks/normal/*.hook.chroot
    # layout, which it silently ignores. (This bit us: wiimplay + all pi-studio
    # hooks were dropped into normal/ and never ran.) Copy ours into config/hooks/
    # with a .chroot extension, prefixed 2xx so they run AFTER the base 020/100
    # hooks. Source files keep their repo names under config/hooks/normal/.
    mkdir -p config/hooks
    # Copy ALL custom hooks in normal/ (glob-all) — narrow patterns
    # (50-wiimplay + 6*-pi-studio-*) silently orphaned ungated hooks whose names
    # lacked "pi-studio-": 58-snap-free (snapd purge) and 68-first-boot-hygiene
    # shipped disabled. normal/ holds ONLY our custom *.hook.chroot, so glob-all
    # is safe and future-proof.
    for h in ../../config/hooks/normal/*.hook.chroot; do
        [ -f "$h" ] || continue
        dest="config/hooks/2$(basename "$h" .hook.chroot).chroot"
        cp "$h" "$dest"; chmod +x "$dest"
        echo "defcom5: installed chroot hook $(basename "$dest")"
    done
    # defcom5: vendored big files (sonic-pi tarball, chromium.png, betterbird) ->
    # chroot /tmp/pi-studio via live-build includes.chroot, so the hooks can read
    # them. Kept OUT of git (large); lives at $PISTUDIO_VENDOR on the build host.
    PISTUDIO_VENDOR="${PISTUDIO_VENDOR:-/mnt/build/PI_Studio/vendor}"
    if [ -d "${PISTUDIO_VENDOR}" ]; then
        mkdir -p config/includes.chroot/tmp/pi-studio
        # /tmp MUST stay 1777 — includes.chroot would otherwise apply 0755 to it,
        # breaking apt-key (_apt can't write /tmp) -> apt update fails for all repos.
        chmod 1777 config/includes.chroot/tmp
        cp -a "${PISTUDIO_VENDOR}"/. config/includes.chroot/tmp/pi-studio/
        echo "defcom5: vendored $(ls -1 "${PISTUDIO_VENDOR}" | wc -l) Pi Studio file(s) into the chroot"
    else
        echo "defcom5: WARN no ${PISTUDIO_VENDOR} — Sonic Pi/betterbird/icon will be skipped by hooks"
    fi
fi

# defcom5 (2026-08-04): FORCE live-build to re-read the package list every run.
#
# live-build stamps completed stages in .build/ and skips them on re-run. That
# cost four bakes today: the package list on disk was correct and current, but
# `lb build` printed "W: skipping chroot_package-lists.install, already done" and
# installed from a SEVEN-ENTRY snapshot queued during an earlier attempt — so
# openssh-server, file and cloud-init were silently never installed while the
# generated list plainly listed them. Every fix looked right and none of them ran.
#
# The stamps are cheap to redo and the package list changes often, so clear them
# unconditionally. This is the same class of failure as the rootfs tarball cache
# above: silent reuse that returns success-shaped output.
if [ -d .build ]; then
    rm -f .build/chroot_package-lists.* .build/chroot_install-packages.* 2>/dev/null || true
    echo "defcom5: cleared live-build package-list stamps (forces the list to be re-read)"
fi

# defcom5 (2026-08-04): make upstream's ssh hook survive a minimal resolute chroot.
# livecd-rootfs ships config/hooks/007-ssh_authentication.chroot, which does a bare
#   cat >> /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
# with no mkdir. On the noble/cpc images that directory already exists by the time
# the hook runs; in a minimal 26.04 server chroot it does NOT, so the redirect fails
# with "No such file or directory", the hook exits non-zero, and our partial-chroot
# gate correctly refuses to tar the result.
#
# Fixed by pre-creating the directory via includes.chroot (applied before hooks run)
# rather than by patching upstream's hook — the hook is regenerated by `lb config`
# on every build, so a patch there would silently evaporate. Belt-and-braces: also
# harden the hook in place if it's present.
mkdir -p config/includes.chroot/etc/ssh/sshd_config.d
_sshhook=config/hooks/007-ssh_authentication.chroot
if [ -f "${_sshhook}" ] && ! grep -q 'mkdir -p /etc/ssh/sshd_config.d' "${_sshhook}"; then
    sed -i '1a mkdir -p /etc/ssh/sshd_config.d' "${_sshhook}"
    echo "defcom5: hardened ${_sshhook} with mkdir -p"
fi

# Build the rootfs.
# ⚠️ CLASS BUG FIXED 2026-07-28: `set -e` is OFF here, so lb build's exit code was
# never checked — a FAILED HOOK (267-muse died on a missing patchelf) still fell
# through to the tar below, producing a 5.4 GB image from a PARTIAL chroot that then
# passed 31 verify-clean gates. A failed hook must NEVER become a shipped artifact.
lb build || true   # ⚠️ NON-ZERO IS NORMAL: lb config sets no --binary-images, so the
                   # ISO binary stage always fails on arm64. Upstream keeps `set -e` off
                   # here for exactly that reason. DO NOT gate on this exit code (tried
                   # 2026-07-28: it hard-stops every healthy bake).
# Gate on the failure that actually matters: a HOOK that died. Before this check, a
# failed hook was indistinguishable from the benign binary-stage failure, so a PARTIAL
# chroot got tarred and shipped (v1.4 lost half of Muse yet passed 31 verify gates).
if grep -qE 'config/hooks/.* failed \(exit non-zero\)' ./*.log 2>/dev/null; then
    echo "FATAL: a chroot hook failed — refusing to tar a partial chroot:" >&2
    grep -hE 'config/hooks/.* failed \(exit non-zero\)' ./*.log 2>/dev/null | tail -3 >&2
    grep -hE '^E: (Unable to locate|Package)|: not found' ./*.log 2>/dev/null | tail -3 >&2
    exit 1
fi
[ -d chroot/usr/bin ] || { echo "FATAL: chroot looks unbuilt — refusing to tar." >&2; exit 1; }

# 2026-08-04: the gate above only catches HOOK failures. A failed PACKAGE INSTALL
# walked straight past it and produced a 967 MB image missing openssh-server,
# cloud-init and file — i.e. an image nobody could even log into. apt aborts the
# WHOLE transaction on an unsatisfiable dependency, so one conflict silently drops
# every package after it. Treat that exactly like a failed hook.
if grep -qE '^E: (Unable to satisfy dependencies|Unable to locate package|Unable to correct problems)' ./*.log 2>/dev/null; then
    echo "FATAL: a package install failed — refusing to tar an incomplete chroot:" >&2
    grep -hE '^E: (Unable to satisfy|Unable to locate|Unable to correct)' ./*.log 2>/dev/null | tail -3 >&2
    grep -hB6 '^E: Unable to satisfy dependencies' ./*.log 2>/dev/null | grep -E 'Conflicts|Depends' | tail -4 >&2
    exit 1
fi

# And assert the packages we explicitly asked for actually arrived. The list is the
# contract; "apt exited 0" is not the same as "the contract was met".
if [ "${KERNEL_SOURCE:-forge}" == "stock" ]; then
    for _p in ubuntu-server openssh-server network-manager cloud-init; do
        grep -A2 "^Package: ${_p}$" chroot/var/lib/dpkg/status 2>/dev/null \
            | grep -qm1 'install ok installed' \
            || { echo "FATAL: requested package '${_p}' is NOT installed in the chroot — refusing to tar." >&2; exit 1; }
    done
    echo "defcom5: package contract verified (ubuntu-server, openssh-server, network-manager, cloud-init)"
fi

set -eE

# Tar the entire rootfs
(cd chroot/ &&  tar -p -c --sort=name --xattrs ./*) | xz -3 -T0 > "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz"
mv "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz" ../
