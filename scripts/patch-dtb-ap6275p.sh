#!/bin/bash
#
# patch-dtb-ap6275p.sh <input.dtb> [output.dtb]
#
# Splice the AP6275P Bluetooth wiring into a MAINLINE Orange Pi 5B device tree.
#
# WHY THIS EXISTS
# ---------------
# Upstream's rk3588s-orangepi-5b DT (merged ~6.13) does NOT wire this board's
# AP6275P radio. Verified 2026-08-05 against the DTB Ubuntu ships in
# linux-modules-7.0.0-29-generic: 4,960 lines, ZERO matches for
# wireless/brcm/bluetooth/bt-* GPIOs. Armbian's DTB for the same board has all
# of it — so the spike where both radios came up on Armbian's mainline kernel
# proved ARMBIAN'S DEVICE TREE works, not that mainline supports this board.
# That gates every distro-kernel path equally (Ubuntu-via-EFI, Debian-via-booti,
# an Armbian graft).
#
# Bluetooth cannot work without this: it is a serdev device on a UART, so it
# must be declared. (WiFi is PCIe and self-enumerating — a separate question.)
#
# WHY A PATCH AND NOT AN OVERLAY
# ------------------------------
# An overlay was written first and cannot work: **Ubuntu's DTB has no
# __symbols__ node** (compiled without dtc -@), so it exports no labels and an
# overlay has nothing to bind its references to. Armbian's DTB does have
# __symbols__, which is how their overlay system works. We cannot influence how
# Ubuntu compiles their DTB, so we transform the tree directly instead.
#
# That is also just better here: no runtime overlay loading to go wrong, the
# shipped artifact is a plain complete DTB, and it is verifiable by decompiling
# the output and grepping for the node — which is exactly the check that caught
# the missing wiring in the first place.
#
# PROVENANCE
# ----------
# Transcribed from Armbian 7.1.5-edge's rk3588s-orangepi-5b.dtb, PROVEN on this
# hardware: it discovered the real household BLE devices (fridge, LED
# controllers, a Galaxy Watch) during the 2026-08-04 spike. Values are kept as
# raw numbers exactly as decompiled — inventing symbolic names risks silently
# changing them. Decoded meanings are in comments.
#
# Idempotent: re-running on an already-patched DTB is a no-op.

set -euo pipefail

IN="${1:?usage: patch-dtb-ap6275p.sh <input.dtb> [output.dtb]}"
OUT="${2:-$IN}"

command -v dtc >/dev/null || { echo "E: [dtb-patch] dtc not installed (device-tree-compiler)" >&2; exit 1; }
[ -f "$IN" ] || { echo "E: [dtb-patch] input DTB not found: $IN" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

dtc -I dtb -O dts -o "$TMP/base.dts" "$IN" 2>/dev/null \
    || { echo "E: [dtb-patch] failed to decompile $IN" >&2; exit 1; }

# Already wired? (e.g. a future upstream DT, or a re-run) -> nothing to do.
if grep -qE 'brcm,bcm43438-bt|wireless-bluetooth' "$TMP/base.dts"; then
    echo "I: [dtb-patch] DTB already wires the radio — nothing to do"
    [ "$OUT" != "$IN" ] && cp "$IN" "$OUT"
    exit 0
fi

# --- sanity: every node we reference must exist, or the result won't work ----
# These are all present in Ubuntu's tree (verified). Fail loudly rather than
# emit a DTB that compiles but references nothing.
for need in 'serial@febc0000' 'rtc@51' 'dcdc-reg8' 'dcdc-reg10' \
            'gpio@fd8a0000' 'gpio@fec40000' 'pinctrl'; do
    grep -q "$need" "$TMP/base.dts" \
        || { echo "E: [dtb-patch] base DTB lacks '$need' — wrong board or upstream moved it" >&2; exit 1; }
done

python3 - "$TMP/base.dts" "$TMP/patched.dts" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
dts = open(src).read()

# 1. pinctrl groups — the ONLY thing missing upstream; everything else exists.
#    rockchip,pins = <bank pin mux config>
PINCTRL = '''
\t\twireless-bluetooth {
\t\t\tbt-reset-pin {
\t\t\t\trockchip,pins = <0x03 0x06 0x00 0x11b>;
\t\t\t\tphandle = <0xbt1>;
\t\t\t};
\t\t\tbt-wake-pin {
\t\t\t\trockchip,pins = <0x00 0x16 0x00 0x121>;
\t\t\t\tphandle = <0xbt2>;
\t\t\t};
\t\t\tbt-wake-host-irq {
\t\t\t\trockchip,pins = <0x00 0x15 0x00 0x11d>;
\t\t\t\tphandle = <0xbt3>;
\t\t\t};
\t\t};

\t\tuart9-m2 {
\t\t\tuart9m2-xfer {
\t\t\t\trockchip,pins = <0x03 0x1c 0x0a 0x121 0x03 0x1d 0x0a 0x121>;
\t\t\t\tphandle = <0xbt4>;
\t\t\t};
\t\t\tuart9m2-ctsn {
\t\t\t\trockchip,pins = <0x03 0x1b 0x0a 0x11b>;
\t\t\t\tphandle = <0xbt5>;
\t\t\t};
\t\t\tuart9m2-rtsn {
\t\t\t\trockchip,pins = <0x03 0x1a 0x0a 0x11b>;
\t\t\t\tphandle = <0xbt6>;
\t\t\t};
\t\t};
'''

# Allocate real phandles above anything already used, so we can't collide.
used = [int(x, 16) for x in re.findall(r'phandle = <0x([0-9a-fA-F]+)>', dts)]
nxt = max(used) + 1 if used else 1
alloc = {}
for i, key in enumerate(['0xbt1','0xbt2','0xbt3','0xbt4','0xbt5','0xbt6']):
    alloc[key] = nxt + i
for key, val in alloc.items():
    PINCTRL = PINCTRL.replace(f'<{key}>', f'<0x{val:x}>')

# Insert at the END of the pinctrl node, not the start. DTS requires that a
# node's PROPERTIES precede its SUBNODES — inserting straight after the opening
# brace puts our groups ahead of pinctrl's own compatible/ranges/#address-cells
# and dtc rejects it with "Properties must precede subnodes".
m = re.search(r'\n\tpinctrl \{\n', dts) or re.search(r'\n\t[a-z0-9_-]*pinctrl[a-z0-9_@-]* \{\n', dts)
if not m:
    sys.exit("E: [dtb-patch] could not locate the pinctrl node")

# Brace-match to find where the pinctrl node actually closes.
depth, j = 0, m.end() - 1          # start at the opening '{'
while j < len(dts):
    if dts[j] == '{':
        depth += 1
    elif dts[j] == '}':
        depth -= 1
        if depth == 0:
            break
    j += 1
else:
    sys.exit("E: [dtb-patch] unbalanced braces locating the end of pinctrl")

# j is the closing '}' of pinctrl; back up to the start of that line.
line_start = dts.rfind('\n', 0, j) + 1
dts = dts[:line_start] + PINCTRL + dts[line_start:]

# 2. Resolve the phandles of nodes we reference (they already exist upstream).
def phandle_of(node):
    i = dts.find(node + ' {')
    if i < 0: sys.exit(f"E: [dtb-patch] node not found: {node}")
    seg = dts[i:i+4000]
    p = re.search(r'phandle = <0x([0-9a-fA-F]+)>', seg)
    if not p: sys.exit(f"E: [dtb-patch] {node} has no phandle")
    return int(p.group(1), 16)

rtc   = phandle_of('rtc@51')
gpio0 = phandle_of('gpio@fd8a0000')
gpio4 = phandle_of('gpio@fec40000')
reg8  = phandle_of('dcdc-reg8')
reg10 = phandle_of('dcdc-reg10')

# 3. Enable uart9 and add the bluetooth serdev child.
BT = f'''
\t\tbluetooth {{
\t\t\tcompatible = "brcm,bcm43438-bt";
\t\t\tclocks = <0x{rtc:x}>;
\t\t\tclock-names = "lpo";
\t\t\tinterrupt-parent = <0x{gpio0:x}>;
\t\t\tinterrupts = <0x15 0x04>;
\t\t\tinterrupt-names = "host-wakeup";
\t\t\tdevice-wakeup-gpios = <0x{gpio0:x} 0x16 0x00>;
\t\t\tshutdown-gpios = <0x{gpio4:x} 0x06 0x00>;
\t\t\tmax-speed = <0x16e360>;
\t\t\tpinctrl-names = "default";
\t\t\tpinctrl-0 = <0x{alloc['0xbt3']:x} 0x{alloc['0xbt2']:x} 0x{alloc['0xbt1']:x}>;
\t\t\tvbat-supply = <0x{reg8:x}>;
\t\t\tvddio-supply = <0x{reg10:x}>;
\t\t}};
'''

i = dts.find('serial@febc0000 {')
if i < 0: sys.exit("E: [dtb-patch] serial@febc0000 (uart9) not found")
end = dts.find('\n\t};', i)
if end < 0: sys.exit("E: [dtb-patch] could not find the end of the uart9 node")
body = dts[i:end]
body = re.sub(r'status = "disabled";', 'status = "okay";', body)
if 'status = "okay"' not in body:
    body += '\t\tstatus = "okay";\n'

# uart9 ALREADY carries pinctrl-0 / pinctrl-names upstream (referencing only the
# xfer group). Appending our own would be a duplicate property and dtc rejects
# it — so REPLACE the value in place, adding the CTS/RTS groups the Bluetooth
# firmware handshake needs. Do not add pinctrl-names; it is already "default".
pinref = f"<0x{alloc['0xbt4']:x} 0x{alloc['0xbt5']:x} 0x{alloc['0xbt6']:x}>"
if re.search(r'pinctrl-0 = <[^>]*>;', body):
    body = re.sub(r'pinctrl-0 = <[^>]*>;', f'pinctrl-0 = {pinref};', body, count=1)
else:
    body += f'\t\tpinctrl-0 = {pinref};\n\t\tpinctrl-names = "default";\n'

dts = dts[:i] + body + BT + dts[end:]

# 4. WiFi. Unlike BT this is PCIe and self-enumerating, so it needs no device
#    node of its own — but upstream leaves the controller DISABLED and defines
#    no 3v3 rail for it. Armbian enables pcie@fe190000, gives it a reset GPIO
#    and a fixed regulator, and adds a wifi@0,0 child purely to hand brcmfmac
#    the 32kHz LPO clock off the RTC.
if 'pcie@fe190000' in dts:
    # 4a. The rail. Fixed 3v3, always-on, no enable GPIO; vin is dcdc-reg8,
    #     which already exists upstream (same rail BT's vbat uses).
    if 'vcc3v3_pcie20' not in dts:
        nxt2 = max([int(x, 16) for x in re.findall(r'phandle = <0x([0-9a-fA-F]+)>', dts)]) + 1
        REG = (
            '\n\tregulator-vcc3v3-pcie20 {\n'
            '\t\tcompatible = "regulator-fixed";\n'
            '\t\tregulator-name = "vcc3v3_pcie20";\n'
            '\t\tregulator-boot-on;\n'
            '\t\tregulator-always-on;\n'
            '\t\tregulator-min-microvolt = <0x325aa0>;\n'   # 3,300,000 uV
            '\t\tregulator-max-microvolt = <0x325aa0>;\n'
            '\t\tstartup-delay-us = <0xc350>;\n'            # 50,000 us
            f'\t\tvin-supply = <0x{reg8:x}>;\n'
            f'\t\tphandle = <0x{nxt2:x}>;\n'
            '\t};\n'
        )
        k = dts.find('\n\tpcie@fe190000 {')
        if k < 0:
            sys.exit("E: [dtb-patch] could not place the pcie regulator")
        dts = dts[:k] + REG + dts[k:]
        pcie_reg = nxt2
    else:
        pcie_reg = None

    # 4b. Enable the controller and give it reset + supply.
    k = dts.find('pcie@fe190000 {')
    kend = dts.find('\n\t};', k)
    pbody = dts[k:kend]
    pbody = re.sub(r'status = "disabled";', 'status = "okay";', pbody)
    if 'status = "okay"' not in pbody:
        pbody = pbody.rstrip() + '\n\t\tstatus = "okay";\n'

    # pcie@fe190000 ALREADY contains a subnode (legacy-interrupt-controller), so
    # new PROPERTIES cannot be appended at the end — same "Properties must
    # precede subnodes" rule that bit the pinctrl insertion. Splice them in
    # immediately after the status line, which is safely in the property block.
    newprops = ''
    if 'reset-gpios' not in pbody:
        newprops += f'\t\treset-gpios = <0x{gpio4:x} 0x19 0x00>;\n'   # gpio4 pin 25
    if pcie_reg and 'vpcie3v3-supply' not in pbody:
        newprops += f'\t\tvpcie3v3-supply = <0x{pcie_reg:x}>;\n'
    if newprops:
        sm = re.search(r'\n\t\tstatus = "okay";\n', pbody)
        if not sm:
            sys.exit("E: [dtb-patch] no status line in pcie node to anchor properties to")
        pbody = pbody[:sm.end()] + newprops + pbody[sm.end():]
    # 4c. The LPO clock hand-off to brcmfmac.
    if 'wifi@0,0' not in pbody:
        pbody += (
            '\n\t\tpcie@0,0 {\n'
            '\t\t\treg = <0x400000 0x00 0x00 0x00 0x00>;\n'
            '\t\t\t#address-cells = <0x03>;\n'
            '\t\t\t#size-cells = <0x02>;\n'
            '\t\t\tranges;\n'
            '\t\t\tdevice_type = "pci";\n'
            '\t\t\tbus-range = <0x40 0x4f>;\n'
            '\n\t\t\twifi@0,0 {\n'
            '\t\t\t\tcompatible = "pci14e4,449d";\n'
            '\t\t\t\treg = <0x410000 0x00 0x00 0x00 0x00>;\n'
            f'\t\t\t\tclocks = <0x{rtc:x}>;\n'
            '\t\t\t\tclock-names = "lpo";\n'
            '\t\t\t};\n'
            '\t\t};\n'
        )
    dts = dts[:k] + pbody + dts[kend:]

open(dst, 'w').write(dts)
print("I: [dtb-patch] spliced uart9 + bluetooth + pcie/wifi nodes")
PY

dtc -I dts -O dtb -o "$TMP/patched.dtb" "$TMP/patched.dts" 2>/dev/null \
    || { echo "E: [dtb-patch] patched DTS failed to compile" >&2; exit 1; }

# --- GATE: verify the OUTPUT, not the intent ---------------------------------
# Same check that found the problem: decompile the result and look for the node.
dtc -I dtb -O dts "$TMP/patched.dtb" 2>/dev/null > "$TMP/verify.dts"
grep -q 'brcm,bcm43438-bt' "$TMP/verify.dts" \
    || { echo "E: [dtb-patch] bluetooth node missing from the compiled output" >&2; exit 1; }
grep -qE "bt-reset-pin|bt-wake-pin" "$TMP/verify.dts" \
    || { echo "E: [dtb-patch] bt pinctrl groups missing from the compiled output" >&2; exit 1; }

cp "$TMP/patched.dtb" "$OUT"
echo "I: [dtb-patch] wired AP6275P BT into $(basename "$OUT") ($(stat -c%s "$OUT") bytes) — verified in the output"
