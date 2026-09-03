#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip — https://github.com/defcom5-rockchip
# AP6275P Bluetooth bring-up — race-hardened (WiFi/BT combo-chip fix, defcom5-rockchip)
# Fixes: (1) unblock BT only, not "all" (don't wake WiFi during BT firmware load);
#        (2) verify hci0 got a real MAC + one boot-time retry if it wedged (null MAC / -49).
bt=$(cat /proc/device-tree/wireless-bluetooth/status 2>/dev/null)
chip=$(cat /proc/device-tree/wireless-wlan/wifi_chip_type 2>/dev/null)
[[ $chip == "ap6275p" && $bt == "okay" ]] || exit 0

rfkill unblock bluetooth 2>/dev/null          # BT only — do NOT wake WiFi here

patch() {
    pkill -f brcm_patchram_plus 2>/dev/null; sleep 1
    brcm_patchram_plus --enable_hci --no2bytes --use_baudrate_for_download --tosleep 200000 \
        --baudrate 1500000 --patchram /lib/firmware/ap6275p/BCM4362A2.hcd /dev/ttyS9 &
}

ok() {
    local m; m=$(hciconfig hci0 2>/dev/null | awk '/BD Address/{print $3}')
    [[ -n $m && $m != "00:00:00:00:00:00" ]]
}

patch
for i in $(seq 1 12); do sleep 1; ok && break; done

if ! ok; then
    logger -t ap6275p-bt "hci0 wedged (null MAC / -49) — retrying patchram once"
    patch
    for i in $(seq 1 12); do sleep 1; ok && break; done
fi

if ok; then
    hciconfig hci0 up 2>/dev/null
    logger -t ap6275p-bt "hci0 up: $(hciconfig hci0 2>/dev/null | awk '/BD Address/{print $3}')"
else
    logger -t ap6275p-bt "hci0 STILL wedged after retry — needs BT_REG_ON power-cycle (hammer)"
fi
exit 0
