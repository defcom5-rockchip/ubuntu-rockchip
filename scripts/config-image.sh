#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p build && cd build

if [[ -z ${BOARD} ]]; then
    echo "Error: BOARD is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/boards/${BOARD}.sh"

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

if [[ ${LAUNCHPAD} != "Y" ]]; then
    uboot_package="$(basename "$(find u-boot-"${BOARD}"_*.deb | sort | tail -n1)")"
    if [ ! -e "$uboot_package" ]; then
        echo 'Error: could not find the u-boot package'
        exit 1
    fi
fi

# The forge kernel debs are only required when we're actually installing them.
# On a stock/mainline suite there are none in build/ by design — the kernel comes
# from the Ubuntu archive later in this script. This block used to run
# unconditionally and killed the first resolute bake with "could not find the
# linux image package" AFTER the rootfs had already built.
if [[ ${LAUNCHPAD} != "Y" && "${KERNEL_SOURCE:-forge}" != "stock" ]]; then
    linux_image_package="$(basename "$(find linux-image-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_image_package" ]; then
        echo "Error: could not find the linux image package"
        exit 1
    fi

    linux_headers_package="$(basename "$(find linux-headers-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_headers_package" ]; then
        echo "Error: could not find the linux headers package"
        exit 1
    fi

    linux_modules_package="$(basename "$(find linux-modules-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_modules_package" ]; then
        echo "Error: could not find the linux modules package"
        exit 1
    fi

    linux_buildinfo_package="$(basename "$(find linux-buildinfo-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_buildinfo_package" ]; then
        echo "Error: could not find the linux buildinfo package"
        exit 1
    fi

    linux_rockchip_headers_package="$(basename "$(find linux-rockchip-headers-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_rockchip_headers_package" ]; then
        echo "Error: could not find the linux rockchip headers package"
        exit 1
    fi
fi

setup_mountpoint() {
    local mountpoint="$1"

    if [ ! -c /dev/mem ]; then
        mknod -m 660 /dev/mem c 1 1
        chown root:kmem /dev/mem
    fi

    mount dev-live -t devtmpfs "$mountpoint/dev"
    mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
    mount proc-live -t proc "$mountpoint/proc"
    mount sysfs-live -t sysfs "$mountpoint/sys"
    mount securityfs -t securityfs "$mountpoint/sys/kernel/security"
    # Provide more up to date apparmor features, matching target kernel
    # cgroup2 mount for LP: 1944004
    mount -t cgroup2 none "$mountpoint/sys/fs/cgroup"
    mount -t tmpfs none "$mountpoint/tmp"
    mount -t tmpfs none "$mountpoint/var/lib/apt/lists"
    mount -t tmpfs none "$mountpoint/var/cache/apt"
    mv "$mountpoint/etc/resolv.conf" resolv.conf.tmp
    cp /etc/resolv.conf "$mountpoint/etc/resolv.conf"
    mv "$mountpoint/etc/nsswitch.conf" nsswitch.conf.tmp
    sed 's/systemd//g' nsswitch.conf.tmp > "$mountpoint/etc/nsswitch.conf"
}

teardown_mountpoint() {
    # Reverse the operations from setup_mountpoint
    local mountpoint
    mountpoint=$(realpath "$1")

    # ensure we have exactly one trailing slash, and escape all slashes for awk
    mountpoint_match=$(echo "$mountpoint" | sed -e's,/$,,; s,/,\\/,g;')'\/'
    # sort -r ensures that deeper mountpoints are unmounted first
    awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
        # host kernel 7.0 / util-linux 2.41 can reject `mount --make-private` on these
        # build-only submounts with "Unknown error 5005"; that must NOT abort teardown
        # (set -e). Tolerate it and fall back to a lazy umount. Safe: these are the
        # image's own dev/proc/sys/tmpfs mounts, never the host's real filesystems.
        mount --make-private "$submount" 2>/dev/null || true
        umount "$submount" 2>/dev/null || umount -l "$submount" 2>/dev/null || true
    done
    mv resolv.conf.tmp "$mountpoint/etc/resolv.conf"
    mv nsswitch.conf.tmp "$mountpoint/etc/nsswitch.conf"
}

# Prevent dpkg interactive dialogues
export DEBIAN_FRONTEND=noninteractive

# Override localisation settings to address a perl warning
export LC_ALL=C

# Debootstrap options
chroot_dir=rootfs
overlay_dir=../overlay

# Extract the compressed root filesystem.
# ⚠️ SAFETY (2026-07-22, learned the hard way): if a previous crashed run left
# rootfs/dev (devtmpfs) mounted, `rm -rf rootfs` walks into the HOST'S REAL /dev
# (devtmpfs is shared, not a copy) and deletes real device nodes (this ate every
# /dev/loop* + loop-control and broke build-image). Unmount any submounts first,
# and refuse to rm while anything under rootfs is still mounted.
_rfs_abs=$(readlink -f ${chroot_dir} 2>/dev/null || echo "$PWD/${chroot_dir}")
awk -v p="$_rfs_abs/" 'index($2, p)==1 {print $2}' /proc/self/mounts | LC_ALL=C sort -r | while IFS= read -r m; do
    umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
done
if awk -v p="$_rfs_abs/" 'index($2, p)==1 {found=1} END {exit !found}' /proc/self/mounts; then
    echo "FATAL: refusing rm -rf ${chroot_dir} — submounts still active (would eat host /dev):"
    awk -v p="$_rfs_abs/" 'index($2, p)==1 {print "  "$2}' /proc/self/mounts
    exit 1
fi
rm -rf ${chroot_dir} && mkdir -p ${chroot_dir}
tar -xpJf "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz" -C ${chroot_dir}

# Pi Desktop: protect the defcom5 libv4l-rkmpp fork from the 1001 PPA pins below
# (idempotent; hook 62 writes the same file for fresh rootfs builds — this covers a
# tarball built before that hook carried it). See hook 62 for the story.
if [ -f "${chroot_dir}/usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-rkmpp.so" ] && \
   [ ! -s "${chroot_dir}/etc/apt/preferences.d/20-libv4l-rkmpp-defcom5.pref" ]; then
    mkdir -p "${chroot_dir}/etc/apt/preferences.d"
    printf 'Package: libv4l-rkmpp\nPin: release o=LP-PPA-jjriek-rockchip-multimedia\nPin-Priority: 100\n\nPackage: libv4l-rkmpp\nPin: release o=LP-PPA-liujianfeng1994-rockchip-multimedia\nPin-Priority: 100\n' \
        > "${chroot_dir}/etc/apt/preferences.d/20-libv4l-rkmpp-defcom5.pref"
    echo "I: config-image: libv4l-rkmpp pin written (keeps the defcom5 fork over the PPA snapshots)"
fi

# Mount the root filesystem
setup_mountpoint $chroot_dir

# Update packages. apt-get update is wrapped in a retry: ports.ubuntu.com mirrors
# frequently serve a half-synced index ("File has unexpected size ... Mirror sync
# in progress?"), which otherwise aborts the whole image stage (no retry loop here,
# unlike fullbuild). Idempotent, so retrying is always safe; hard-fails after 6 tries.
_n=0
until chroot $chroot_dir apt-get update; do
    _n=$((_n+1))
    if [ "$_n" -ge 6 ]; then
        # Mirror still wedged after ~5 min. A PARTIAL index (e.g. only noble-security
        # mid-sync) is survivable: the tarball was fully upgraded at build-rootfs time,
        # and any real dependency problem will fail loudly at its own install step.
        # Only bail if the PRIMARY suite index is absent (i.e. update failed wholesale).
        if ls ${chroot_dir}/var/lib/apt/lists/*_dists_${RELEASE}*_main_binary-arm64_Packages* >/dev/null 2>&1 \
           || ls ${chroot_dir}/var/lib/apt/lists/*noble_main_binary-arm64_Packages* >/dev/null 2>&1; then
            echo "W: config-image: apt-get update still partial after $_n tries (mirror mid-sync) — PROCEEDING with fetched indices"
            break
        fi
        echo "FATAL: apt-get update failed wholesale after $_n tries (no primary index — network/mirror down)"
        exit 1
    fi
    echo "config-image: apt-get update flaked (mirror sync?) — retry $_n/6 in 45s"
    sleep 45
done
# Upgrade is BEST-EFFORT freshness polish, not correctness: the tarball is fully
# upgraded at build-rootfs time. During mirror outages the index/pool can skew
# (index lists versions whose pool files 404) — --fix-missing installs what did
# fetch, and a nonzero exit must not veto the image. (2026-07-22 Canonical outage:
# four gphoto/perl 404s killed an otherwise-perfect run at this line.)
chroot $chroot_dir apt-get -y --fix-missing upgrade \
    || echo "W: config-image: upgrade partial (mirror skew) — proceeding; first-boot apt will catch up"
    
# Run config hook to handle board specific changes
if [[ $(type -t config_image_hook__"${BOARD}") == function ]]; then
    config_image_hook__"${BOARD}" "${chroot_dir}" "${overlay_dir}" "${SUITE}"
fi

# --- FLAVOR: GUI flavors get the Mesa work; headless ones must not ----------
# Read the same FLAVOR value the chroot hooks use. A headless build (NNP) has no
# GL stack at all, so both the panfork restore and the gate below are wrong for
# it — the gate would find no panfork packages and FATAL a perfectly good image.
_flavor=$(tr -d '[:space:]' < "${chroot_dir}/tmp/pi-studio/FLAVOR" 2>/dev/null || true)
[ -n "${_flavor}" ] || _flavor=studio
case "${_flavor}" in
    studio|desktop) _want_mesa=Y ;;
    *)              _want_mesa=N ;;
esac

# KERNEL_SOURCE OVERRIDES FLAVOR — and this is not belt-and-braces, it is the
# actual condition. panfork exists only in the BSP world: a mainline/stock suite
# never adds the jjriek PPA, so there is no panfork to restore and no gallium
# chimera to prevent. Mainline uses Panthor + stock Mesa, which is the point.
#
# Why this is written as an override rather than folded into the case above:
# a bake with no vendor bundle has no FLAVOR file, so _flavor falls back to
# "studio" — which is right for a Pi Studio bake and WRONG for a bare mainline
# test image. That default sent the first resolute bake into the panfork restore,
# where `libglapi-mesa` has no candidate in resolute (it's a virtual package
# there, provided by mesa-libgallium 26.0.3), the restore failed, and the gate
# below correctly refused to ship it.
if [ "${KERNEL_SOURCE:-forge}" = "stock" ]; then
    _want_mesa=N
fi
echo "I: config-image: flavor=${_flavor} kernel=${KERNEL_SOURCE:-forge} (panfork mesa: ${_want_mesa})"

if [ "${_want_mesa}" = Y ]; then
# --- Restore the panfork Mesa stack (2026-08-01) ----------------------------
# MUST run here: AFTER the board hook, because that hook is what adds the
# panfork PPA. Hook 62 writes the pin early (so nothing re-adds gallium later),
# but it CANNOT do the removal — at hook time panfork isn't a repo yet, so apt
# has no version to fall back to and the purge dies on unmet Qt/GLES deps.
#
# The trailing dash on `mesa-libgallium-` tells apt to REMOVE it as part of the
# SAME transaction as the panfork installs. That's the whole trick: a standalone
# `apt purge mesa-libgallium` asks apt to break the stack and then fix it, which
# it refuses; this asks for one consistent end state, which it can solve.
# --allow-downgrades because panfork is 1:23.0.5 and stock is 25.2.8 — going
# back is a downgrade even though panfork's epoch makes it the preferred pin.
echo "I: config-image: restoring panfork Mesa stack (drops stock mesa-libgallium)"
chroot ${chroot_dir} apt-get install -y --allow-downgrades \
    libegl-mesa0 libgl1-mesa-dri libglapi-mesa libglx-mesa0 \
    mesa-va-drivers mesa-vdpau-drivers mesa-vulkan-drivers \
    mesa-libgallium- \
    || echo "W: config-image: panfork restore returned nonzero — the gate below decides"

# --- GATE: stock mesa-libgallium must NOT be in the image (2026-07-31) ------
# Browser HW video decode depends on this. Mesa 25.x split the gallium drivers
# into a new binary package that panfork does not publish, so apt pins cannot
# shadow it — it arrives via the upgrade steps above AND via the board hook's
# own `apt-get -y dist-upgrade` (which is why this gate sits AFTER the hook,
# not before it). Stock gallium layered under panfork's rockchip_dri.so is the
# chimera that breaks Chromium 132 decode. Hook 62 writes the -1 pin + purges;
# this proves it actually stuck all the way to the end of the build.
#
# Second time this class of bug has shipped past us (libv4l was the first),
# hence a hard FATAL rather than a warning. A silently-wrong graphics stack is
# worse than a failed bake.
if chroot ${chroot_dir} dpkg-query -W -f='${Status}' mesa-libgallium 2>/dev/null | grep -q "install ok installed"; then
    echo "FATAL: config-image: mesa-libgallium is INSTALLED in the image."
    echo "       It re-entered after hook 62's pin+purge — something ran a"
    echo "       dist-upgrade that outranked /etc/apt/preferences.d/10-no-mesa-libgallium.pref."
    echo "       Shipping it silently disables Chromium hardware video decode."
    exit 1
fi
if [ ! -s "${chroot_dir}/etc/apt/preferences.d/10-no-mesa-libgallium.pref" ]; then
    echo "FATAL: config-image: the mesa-libgallium pin is missing from the image."
    echo "       hook 62 did not run, or its preferences.d write was lost —"
    echo "       first-boot 'apt upgrade' would then pull stock gallium back in."
    exit 1
fi
# The pin file existing proves nothing about the RESULT — verify the stack we
# actually shipped is panfork. This is what catches a wrong PPA origin string,
# a renamed package, or any future upstream trick that defeats the pin: we
# assert the observable end state, not the config that was supposed to produce
# it. Matches the hardware-verified .158 configuration exactly.
_mesa_bad=""
for _p in libegl-mesa0 libgl1-mesa-dri libglx-mesa0 mesa-va-drivers mesa-vulkan-drivers; do
    _v=$(chroot ${chroot_dir} dpkg-query -W -f='${Version}' "${_p}" 2>/dev/null || true)
    case "${_v}" in
        *panfork*) ;;
        "")        _mesa_bad="${_mesa_bad} ${_p}(absent)" ;;
        *)         _mesa_bad="${_mesa_bad} ${_p}=${_v}" ;;
    esac
done
if [ -n "${_mesa_bad}" ]; then
    echo "FATAL: config-image: the image is NOT on the panfork Mesa stack."
    echo "       Non-panfork:${_mesa_bad}"
    echo "       Chromium hardware video decode requires panfork (1:23.0.5~panfork~)."
    echo "       Stock Mesa wins here only when mesa-libgallium is present to anchor"
    echo "       it, so if this fires, check what re-introduced that package."
    exit 1
fi

# --- Pi Desktop late fix-ups (2026-09-07) — after EVERY apt step in this stage ------
# Two things the image stage undid in the 2.0.2 bake, caught by verify-202.sh:
#  1. base-files got upgraded by the board hook's dist-upgrade and rewrote
#     /usr/lib/os-release, erasing the PRETTY_NAME hook 64 had set (and verified).
#  2. the PPA's mpv 0.36 rode back in beside defcom5-mpv038 (a stale manifest line;
#     removed there too) — the image must ship ONE mpv.
# Re-apply from the hook's own text so the version string has a single source.
# The /tmp marker does not survive live-build's cleanup into the tarball (flavor
# reads "studio" here even for Pi Desktop builds), so detect Pi Desktop by what
# hook 64 leaves in /etc: its release file (new) or its udev rule (2.0.1+).
_is_pidesktop=no
if [ "${_flavor}" = desktop ] || [ -f "${chroot_dir}/etc/pi-desktop-release" ] \
   || [ -f "${chroot_dir}/etc/udev/rules.d/99-pi-desktop-hide-altroot.rules" ]; then _is_pidesktop=yes; fi
echo "I: config-image: pi-desktop=${_is_pidesktop} (marker flavor=${_flavor})"
if [ "${_is_pidesktop}" = yes ]; then
    _pn=$(grep -ohE 'PRETTY_NAME="Pi-Desktop [^"]*"' ../config/hooks/normal/64-*.hook.chroot 2>/dev/null | head -1)
    if [ -n "${_pn}" ]; then
        sed -i "s|^PRETTY_NAME=.*|${_pn}|" "${chroot_dir}/usr/lib/os-release"
        grep -q 'Pi-Desktop' "${chroot_dir}/usr/lib/os-release" \
            && echo "I: config-image: PRETTY_NAME re-applied (${_pn})" \
            || { echo "FATAL: config-image: PRETTY_NAME re-apply failed"; exit 1; }
    else
        echo "W: config-image: no Pi-Desktop PRETTY_NAME found in hook 64 — left as is"
    fi
    if chroot ${chroot_dir} dpkg-query -W -f='${Status}' defcom5-mpv038 2>/dev/null | grep -q "install ok installed" \
       && chroot ${chroot_dir} dpkg-query -W -f='${Status}' mpv 2>/dev/null | grep -q "install ok installed"; then
        chroot ${chroot_dir} apt-get purge -y mpv \
            && echo "I: config-image: stray mpv 0.36 purged (defcom5-mpv038 is the only mpv)" \
            || echo "W: config-image: could not purge stray mpv"
    fi
fi
echo "I: config-image: mesa gate OK — panfork stack intact, no stock mesa-libgallium"
else
    echo "I: config-image: headless flavor (${_flavor}) — skipping panfork restore and mesa gate"
fi

# --- Pi Studio SELF-HEAL (v4): moved BEFORE the kernel swap (2026-07-22) ---
# v3 sat AFTER the kernel install — so the new kernel's postinst ran update-initramfs
# while it was still livecd-rootfs's 172-byte stub -> silently no-opped -> the image
# shipped with NO initrd for its kernel -> extlinux got no initrd line -> the kernel
# hung forever resolving root=UUID (only the initramfs can do that). The binary must
# be healed BEFORE any kernel package runs its postinst.
_uir="${chroot_dir}/usr/sbin/update-initramfs"
if chroot ${chroot_dir} dpkg-divert --list /usr/sbin/update-initramfs 2>/dev/null | grep -q update-initramfs; then
    chroot ${chroot_dir} dpkg-divert --remove /usr/sbin/update-initramfs 2>/dev/null || true
fi
if [ -f "${_uir}.REAL" ] && [ "$(stat -c%s "${_uir}.REAL" 2>/dev/null || echo 0)" -ge 1000 ]; then
    mv -f "${_uir}.REAL" "${_uir}"; chmod 0755 "${_uir}"
fi
if [ ! -x "${_uir}" ] || [ "$(stat -c%s "${_uir}" 2>/dev/null || echo 0)" -lt 1000 ]; then
    echo "config-image: update-initramfs missing/stub -> reinstalling initramfs-tools"
    rm -f "${_uir}"
    chroot ${chroot_dir} apt-get install --reinstall -y initramfs-tools
fi
if [ ! -x "${_uir}" ] || [ "$(stat -c%s "${_uir}" 2>/dev/null || echo 0)" -lt 1000 ]; then
    _deb=$(ls -1 ${chroot_dir}/var/cache/apt/archives/initramfs-tools_*.deb 2>/dev/null | tail -1) || true
    if [ -n "${_deb:-}" ]; then
        echo "config-image: extracting update-initramfs directly from $(basename "$_deb")"
        dpkg-deb --fsys-tarfile "$_deb" | tar -C "${chroot_dir}" -xf - ./usr/sbin/update-initramfs 2>/dev/null || true
        chmod 0755 "${_uir}" 2>/dev/null || true
    fi
fi
[ -x "${_uir}" ] && [ "$(stat -c%s "${_uir}")" -ge 1000 ] || { echo "FATAL: could not restore real update-initramfs (size=$(stat -c%s "${_uir}" 2>/dev/null || echo absent))"; exit 1; }
# --- end self-heal v4 ---

# Download and install U-Boot
if [[ ${LAUNCHPAD} == "Y" ]]; then
    chroot ${chroot_dir} apt-get -y install "u-boot-${BOARD}"
else
    cp "${uboot_package}" ${chroot_dir}/tmp/
    chroot ${chroot_dir} dpkg -i "/tmp/${uboot_package}"
    chroot ${chroot_dir} apt-mark hold "$(echo "${uboot_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"

    if [ "${KERNEL_SOURCE:-forge}" = "stock" ]; then
        # --- UBUNTU'S PACKAGED KERNEL (resolute / NNP) ------------------------
        # The whole point: no forge kernel, no purge-and-swap, no apt-mark hold.
        # We WANT apt to keep this updated — that is the CVE coverage we came for.
        # linux-image-generic is a metapackage; it pulls linux-image-<ver>-generic
        # AND linux-modules-<ver>-generic, and the board DTB rides in the modules
        # package at /usr/lib/firmware/<ver>/device-tree/rockchip/.
        echo "I: config-image: KERNEL_SOURCE=stock — installing Ubuntu's linux-image-generic"
        chroot ${chroot_dir} apt-get -y install linux-image-generic linux-firmware
        # Derive the kernel version from /usr/lib/modules, NOT from package names.
        # Ubuntu ships BOTH linux-image-7.0.0-14-generic and
        # linux-image-UNSIGNED-7.0.0-14-generic; a glob over package names matches
        # the unsigned one too and yields "unsigned-7.0.0-14-generic", which then
        # points the DTB lookup at a path that cannot exist. (Caught by the gate
        # below on the 2026-08-04 bake — the gate did its job, the parser didn't.)
        # /usr/lib/modules contains exactly one directory per installed kernel and
        # is the canonical answer.
        _kver=$(ls "${chroot_dir}/usr/lib/modules" 2>/dev/null | sort -V | tail -n1)
        [ -n "${_kver}" ] || { echo "FATAL: config-image: no kernel in /usr/lib/modules — linux-image-generic did not install"; exit 1; }
        echo "I: config-image: stock kernel = ${_kver}"

        # The DTB must exist where Ubuntu puts it, or there is nothing to boot.
        _dtb="/usr/lib/firmware/${_kver}/device-tree/rockchip/rk3588s-${BOARD}.dtb"
        [ -f "${chroot_dir}${_dtb}" ] \
            || { echo "FATAL: config-image: ${_dtb} not found in the image — wrong kernel or wrong board name"; exit 1; }
        echo "I: config-image: board DTB present at ${_dtb}"

        # WIRE THE RADIO. Upstream's 5B device tree does not connect the AP6275P
        # (verified: 0 matches for wireless/brcm/bluetooth in Ubuntu's DTB).
        # Bluetooth is a serdev device, so without this it cannot exist at all —
        # and BT is the whole pitch for NNP. An overlay was tried first and can't
        # work: Ubuntu's DTB carries no __symbols__, so there are no labels for
        # an overlay to bind against. We transform the tree directly instead.
        if [ -x ../scripts/patch-dtb-ap6275p.sh ]; then
            ../scripts/patch-dtb-ap6275p.sh "${chroot_dir}${_dtb}" \
                || { echo "FATAL: config-image: AP6275P DTB patch failed — image would ship with no Bluetooth"; exit 1; }
        else
            echo "FATAL: config-image: scripts/patch-dtb-ap6275p.sh missing"; exit 1
        fi
    else
        cp "${linux_image_package}" "${linux_headers_package}" "${linux_modules_package}" "${linux_buildinfo_package}" "${linux_rockchip_headers_package}" ${chroot_dir}/tmp/
        chroot ${chroot_dir} /bin/bash -c "apt-get -y purge \$(dpkg --list | grep -Ei 'linux-image|linux-headers|linux-modules|linux-rockchip' | awk '{ print \$2 }')"
        chroot ${chroot_dir} /bin/bash -c "dpkg -i /tmp/{${linux_image_package},${linux_modules_package},${linux_buildinfo_package},${linux_rockchip_headers_package}}"
        chroot ${chroot_dir} apt-mark hold "$(echo "${linux_image_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
        chroot ${chroot_dir} apt-mark hold "$(echo "${linux_modules_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
        chroot ${chroot_dir} apt-mark hold "$(echo "${linux_buildinfo_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
        chroot ${chroot_dir} apt-mark hold "$(echo "${linux_rockchip_headers_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
    fi
fi

# Update the initramfs, then GATE ON THE ARTIFACT — not just the binary.
# (2026-07-22 beta shipped with NO initrd: every earlier gate checked that
# update-initramfs EXISTED, none checked that the initrd WAS BUILT. A bare kernel
# cannot resolve root=UUID= — no initrd = guaranteed hang at root mount.)
# Ubuntu 26.04 replaced initramfs-tools with DRACUT as the default generator, so
# update-initramfs may not exist at all. Use whichever tool the image actually has
# rather than assuming — and don't let a missing tool die silently, because a
# kernel with no initrd cannot resolve root=UUID= and hangs with no message.
if [ -x "${chroot_dir}/usr/sbin/update-initramfs" ]; then
    chroot ${chroot_dir} update-initramfs -u
elif [ -x "${chroot_dir}/usr/bin/dracut" ] || [ -x "${chroot_dir}/usr/sbin/dracut" ]; then
    echo "I: config-image: dracut detected (26.04 default) — regenerating initrd"
    _dk=$(ls "${chroot_dir}/usr/lib/modules" 2>/dev/null | sort -V | tail -n1)
    chroot ${chroot_dir} dracut --force --kver "${_dk}" "/boot/initrd.img-${_dk}"
else
    echo "FATAL: config-image: no initramfs generator in the image (neither update-initramfs nor dracut)"
    exit 1
fi
if [[ ${LAUNCHPAD} != "Y" ]]; then
    # On a stock build _kver was already resolved from the installed package above.
    # On a forge build derive it from the deb filename as before.
    if [ "${KERNEL_SOURCE:-forge}" != "stock" ]; then
        _kver=$(echo "${linux_image_package}" | sed -rn 's/^linux-image-([^_]+)_.*/\1/p')
    fi
    _initrd="${chroot_dir}/boot/initrd.img-${_kver}"
    if [ ! -s "${_initrd}" ]; then
        echo "config-image: initrd for ${_kver} MISSING -> forcing a rebuild"
        if [ -x "${chroot_dir}/usr/sbin/update-initramfs" ]; then
            chroot ${chroot_dir} update-initramfs -c -k "${_kver}"
        else
            chroot ${chroot_dir} dracut --force --kver "${_kver}" "/boot/initrd.img-${_kver}"
        fi
    fi
    [ -s "${_initrd}" ] && [ "$(stat -c%s "${_initrd}")" -ge 10000000 ] \
        || { echo "FATAL: initrd.img-${_kver} absent/tiny ($(stat -c%s "${_initrd}" 2>/dev/null || echo 0) bytes) — image would hang at root=UUID"; exit 1; }
    # stale initrds from the pre-swap kernel confuse u-boot-update — remove them
    for _old in "${chroot_dir}"/boot/initrd.img-*; do
        case "$_old" in *"${_kver}"*) ;; *) echo "config-image: removing stale $(basename "$_old")"; rm -f "$_old";; esac
    done
    # --- STOCK KERNEL: put the DTB where u-boot will actually look ------------
    # THIS IS THE HINGE THE WHOLE MAINLINE PLAN TURNS ON.
    # Ubuntu ships the board DTB at /usr/lib/firmware/<ver>/device-tree/rockchip/
    # — its own layout, NOT the /boot/dtb path u-boot's distro_bootcmd and
    # u-boot-menu expect. Rather than fight u-boot-menu's fdtdir logic (which
    # derives a filename from the board compatible and is fragile), copy the one
    # DTB we need to /boot/dtb-<ver>.dtb and name it EXPLICITLY in extlinux.conf.
    # Explicit beats clever here: one file, one line, both verifiable.
    if [ "${KERNEL_SOURCE:-forge}" = "stock" ]; then
        _src="${chroot_dir}/usr/lib/firmware/${_kver}/device-tree/rockchip/rk3588s-${BOARD}.dtb"
        cp "${_src}" "${chroot_dir}/boot/dtb-${_kver}.dtb" \
            || { echo "FATAL: could not stage DTB from ${_src}"; exit 1; }
        chroot ${chroot_dir} ln -sf "dtb-${_kver}.dtb" /boot/dtb
    fi

    # regenerate extlinux.conf now that the initrd exists, then PROVE it references it
    chroot ${chroot_dir} u-boot-update >/dev/null 2>&1 || true
    grep -q "initrd /boot/initrd.img-${_kver}" "${chroot_dir}/boot/extlinux/extlinux.conf" \
        || { echo "FATAL: extlinux.conf has no initrd line for ${_kver} — unbootable image"; exit 1; }
    echo "config-image: initrd gate PASSED — initrd.img-${_kver} ($(stat -c%s "${_initrd}") bytes) + extlinux initrd line present"

    # --- STOCK KERNEL: ensure extlinux actually NAMES an fdt ------------------
    # u-boot-update may emit no fdt/fdtdir at all (it has no idea about Ubuntu's
    # firmware path). Without one the kernel boots with no device tree and dies
    # before it can tell you why. Inject it if absent, then gate on the result —
    # and gate on the TARGET EXISTING, not just the line being present, which is
    # the mistake that shipped three bad images last week.
    if [ "${KERNEL_SOURCE:-forge}" = "stock" ]; then
        # PERSIST the fdt across regeneration. build-image.sh runs `u-boot-update`
        # AGAIN on the mounted image (line ~195), which rebuilds extlinux.conf from
        # scratch and WIPES anything we sed in here — so the 2026-08-04 image gated
        # green with an explicit fdt and shipped without one. Setting U_BOOT_FDT in
        # /etc/default/u-boot makes u-boot-update emit the line itself, so it
        # survives every regeneration instead of being repainted over.
        printf 'U_BOOT_FDT="/boot/dtb-%s.dtb"\n' "${_kver}" >> "${chroot_dir}/etc/default/u-boot"
        chroot ${chroot_dir} u-boot-update >/dev/null 2>&1 || true
        echo "I: config-image: U_BOOT_FDT pinned to /boot/dtb-${_kver}.dtb (survives u-boot-update)"

        _ext="${chroot_dir}/boot/extlinux/extlinux.conf"
        # NOTE the condition tests for a BARE "fdt", not "fdt(dir)?".
        # u-boot-update does emit an fdtdir line pointing at Ubuntu's real DTB
        # directory (/lib/firmware/<ver>/device-tree/), which is likely fine on its
        # own — but fdtdir makes u-boot derive the filename from its ${fdtfile}
        # env var, and if that isn't set for this board it silently finds nothing.
        # An explicit fdt is unambiguous and verifiable, and per the extlinux spec
        # it takes precedence over fdtdir, so leaving both in place is safe.
        # (The first version tested fdt(dir)? here and then required a bare fdt
        # below — so it skipped injection on the fdtdir line and then failed its
        # own gate. Same word, two meanings.)
        if ! grep -qE '^[[:space:]]*fdt[[:space:]]' "${_ext}"; then
            echo "I: config-image: extlinux has fdtdir but no explicit fdt — injecting /boot/dtb-${_kver}.dtb"
            sed -i "/^[[:space:]]*initrd /a\\\tfdt /boot/dtb-${_kver}.dtb" "${_ext}"
        fi
        _fdt=$(grep -m1 -E '^\s*fdt\s' "${_ext}" | awk '{print $2}')
        [ -n "${_fdt}" ] || { echo "FATAL: extlinux.conf still has no fdt line — kernel would boot with no device tree"; exit 1; }
        [ -s "${chroot_dir}${_fdt}" ] \
            || { echo "FATAL: extlinux fdt points at ${_fdt} which does not exist in the image"; exit 1; }
        echo "config-image: fdt gate PASSED — ${_fdt} ($(stat -c%s "${chroot_dir}${_fdt}") bytes) referenced and present"
    fi
fi

# Remove packages
chroot ${chroot_dir} apt-get -y clean
chroot ${chroot_dir} apt-get -y autoclean
chroot ${chroot_dir} apt-get -y autoremove

# Umount the root filesystem
teardown_mountpoint $chroot_dir

# Compress the root filesystem and then build a disk image
cd ${chroot_dir} && tar -cpf "../ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar" . && cd .. && rm -rf ${chroot_dir}
../scripts/build-image.sh "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar"
rm -f "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar"
