# shellcheck shell=bash
#
# Ubuntu 26.04 LTS "Resolute" — the MAINLINE / STOCK-KERNEL suite.
#
# This suite exists for NNP (Naked Network Pi) and, eventually, for migrating the
# other flavors off the BSP fork. It is fundamentally different from noble.sh:
# noble builds OUR kernel from the fork; resolute uses UBUNTU'S PACKAGED KERNEL
# and we build no kernel at all.
#
# WHY 26.04 IS THE FLOOR, NOT A PREFERENCE
# The rk3588s-orangepi-5b device tree merged upstream around 6.13/6.14 (submitted
# Oct 2024). Ubuntu 24.04 noble ships 6.8 — it does not know this board exists.
# 26.04 ships 7.0.x, which does. So "use Ubuntu's kernel" forces 26.04.
#
# WHAT UBUNTU GIVES US FOR FREE (verified against ports.ubuntu.com, 2026-08-04)
#   * The DTB: /usr/lib/firmware/<ver>/device-tree/rockchip/rk3588s-orangepi-5b.dtb
#     ships in linux-modules-<ver>-generic, which linux-image-generic depends on.
#     No separate linux-*-dtb package exists for generic arm64.
#   * The whole OPi RK3588 family — 5, 5B, 5-Max, 5-Plus, 5-Ultra, CM5. This is
#     the multi-board story already sitting in the archive.
#   * The drivers: brcmfmac (WiFi) + hci_uart/btbcm/bnep (BT), same modules that
#     bound both radios on mainline in the Armbian spike.
#   * CVE maintenance across every subsystem, via apt. That is the entire point:
#     our fork's backports are ALSA/Bluetooth/ptrace only, with nothing in net/
#     or netfilter — the wrong curation for a network-exposed box.
#
# WHAT IT DOES NOT GIVE US
#   * AP6275P firmware. The 43752/4362 family is absent from resolute's
#     linux-firmware, so the blobs ride in our overlay under UPSTREAM names.
#   * A bootable image. Ubuntu publishes nothing that boots this board, which is
#     why the forge has to bake it: our u-boot + an extlinux fdt line.

export RELASE_NAME="Ubuntu 26.04 LTS (Resolute)"
export RELASE_VERSION="26.04"

# STOCK KERNEL. Read by build.sh (skip the kernel build) and config-image.sh
# (skip the BSP deb swap, apt-install from the archive instead). Any suite that
# does not set this defaults to the forge kernel, so noble is untouched.
export KERNEL_SOURCE="stock"

# Ubuntu's arm64 kernel flavour. NOT "rockchip" — that is our fork's flavour and
# no such package exists in the Ubuntu archive.
export KERNEL_FLAVOR="generic"

# Deliberately NO KERNEL_REPO / KERNEL_BRANCH — nothing is built from source.
# Deliberately NO EXTRA_PPAS. The jjriek rockchip PPAs are built for noble and
# have no resolute suite; a headless mainline build wants none of them anyway
# (they exist for the vendor GPU/multimedia stack). Dropping them also removes
# two third-party archives from the supply chain, which is a security win on the
# one product that faces the network.
