# shellcheck shell=bash

export BOARD_NAME="Orange Pi 5B"
export BOARD_MAKER="Xulong"
export BOARD_SOC="Rockchip RK3588S"
export BOARD_CPU="ARM Cortex A76 / A55"
export UBOOT_PACKAGE="u-boot-radxa-rk3588"
export UBOOT_RULES_TARGET="orangepi-5b-rk3588s"
export COMPATIBLE_SUITES=("jammy" "noble" "oracular" "plucky")
export COMPATIBLE_FLAVORS=("server" "desktop")

function config_image_hook__orangepi-5b() {
    local rootfs="$1"
    local overlay="$2"
    local suite="$3"

    if [ "${suite}" == "jammy" ] || [ "${suite}" == "noble" ]; then
        # Install panfork
        chroot "${rootfs}" add-apt-repository -y ppa:jjriek/panfork-mesa
        chroot "${rootfs}" apt-get update
        chroot "${rootfs}" apt-get -y install mali-g610-firmware
        chroot "${rootfs}" apt-get -y dist-upgrade

        # Install libmali blobs alongside panfork
        chroot "${rootfs}" apt-get -y install libmali-g610-x11

        # Install the rockchip camera engine
        chroot "${rootfs}" apt-get -y install camera-engine-rkaiq-rk3588

        # Enable bluetooth for AP6275P
        mkdir -p "${rootfs}/usr/lib/scripts"
        cp "${overlay}/usr/lib/systemd/system/ap6275p-bluetooth.service" "${rootfs}/usr/lib/systemd/system/ap6275p-bluetooth.service"
        cp "${overlay}/usr/lib/scripts/ap6275p-bluetooth.sh" "${rootfs}/usr/lib/scripts/ap6275p-bluetooth.sh"
        # brcm_patchram_plus: ship the known-good inherited blob. Building from
        # Orange Pi's CURRENT source revision compiles clean but FAILS hardware
        # bring-up (never completes the firmware download / line-discipline step,
        # wedging the BCM4362 until reboot). It's a newer/different revision than
        # the one that produced this blob. See packages/brcm-patchram-plus/VALIDATION-FAILED.md.
        cp "${overlay}/usr/bin/brcm_patchram_plus" "${rootfs}/usr/bin/brcm_patchram_plus"
        chroot "${rootfs}" systemctl enable ap6275p-bluetooth

        # Enable USB 2.0 port
        cp "${overlay}/usr/lib/systemd/system/enable-usb2.service" "${rootfs}/usr/lib/systemd/system/enable-usb2.service"
        chroot "${rootfs}" systemctl --no-reload enable enable-usb2
        # Apply kernel CVE mitigations (v1.0.1)
        # Blacklist modules for CVEs whose code is built but unused on this board.
        # See the file header for per-CVE detail and reversal instructions.
        mkdir -p "${rootfs}/etc/modprobe.d"
        cp "${overlay}/etc/modprobe.d/99-defcom5-cve-mitigations.conf" "${rootfs}/etc/modprobe.d/99-defcom5-cve-mitigations.conf"
        # Install wiring orangepi package
        chroot "${rootfs}" apt-get -y install wiringpi-opi libwiringpi2-opi libwiringpi-opi-dev

        # Pi Studio BT-3 mitigation: BT/WiFi coex TIMING params for the AP6275P.
        # Stock nvram already ships btc_mode=1 (TDM) and still stutters — the fix is
        # the btc_params timing block (ear-validated matrix + 14h soak, 2026-07-18;
        # HANDOFF-btcoex-RESULTS). NB: nvram_ap6275p.txt (lowercase) is a symlink —
        # target the real UPPERCASE file. Idempotent via grep-guard (stock nvram has
        # zero btc_params lines). Loud failure if the firmware layout ever moves.
        NVRAM="${rootfs}/lib/firmware/ap6275p/nvram_AP6275P.txt"
        if [ ! -f "${NVRAM}" ]; then
            echo "E: [pi-studio] ${NVRAM} missing — AP6275P firmware layout changed; coex params NOT applied" >&2
            exit 1
        fi
        if ! grep -q '^btc_params8=' "${NVRAM}"; then
            {
                echo '#BT Coex timing params (Pi Studio BT-3 mitigation)'
                echo 'btc_params8=0x4e20'
                echo 'btc_params1=0x7530'
                echo 'btc_params50=0x972c'
            } >> "${NVRAM}"
            echo "I: [pi-studio] appended BT-coex btc_params to nvram_AP6275P.txt"
        fi

        # Pi Studio: USB-audio-first — disable USB autosuspend globally on the kernel
        # cmdline (belt-and-suspenders vs the per-interface USB-audio udev rule). Keeps
        # class-compliant interfaces from dropping out mid-session.
        if [ -f "${rootfs}/etc/kernel/cmdline" ] && ! grep -q 'usbcore.autosuspend' "${rootfs}/etc/kernel/cmdline"; then
            sed -i 's/[[:space:]]*$/ usbcore.autosuspend=-1/' "${rootfs}/etc/kernel/cmdline"
            echo "I: [pi-studio] appended usbcore.autosuspend=-1 to kernel cmdline"
        fi

        echo "BOARD=orangepi5" > "${rootfs}/etc/orangepi-release"
    fi

    return 0
}
