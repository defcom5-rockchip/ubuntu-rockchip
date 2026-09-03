# brcm_patchram_plus from-source build — FAILED hardware validation

**Status: the vendored `brcm_patchram_plus.c` is NOT shipped.** The 5B board
hook ships the known-good inherited blob from `overlay/usr/bin/`. This source is
kept only as a reference / starting point for a future attempt.

## What was tried (2026-06-10)
Compiled Orange Pi's current `brcm_patchram_plus.c` (vendored here, from
`orangepi-build` branch `next`, commit `7f776a2`) **natively on the Pi's Noble
arm64** (so it links the target glibc 2.39 — a host cross-build needed
`GLIBC_2.42`, too new for Noble), with the intended image-hook flags:

```sh
gcc -std=gnu17 -O2 -Wno-incompatible-pointer-types \
    -Wno-implicit-function-declaration -Wno-int-conversion \
    -o brcm_patchram_plus brcm_patchram_plus.c
strip brcm_patchram_plus
```

It **compiled cleanly and linked only libc.** Then on hardware:

## Result: fails bring-up, wedges the chip
- The resulting binary (~68 KB, **~3× the 23,712-byte known-good blob**) runs and
  stays resident but **never completes the firmware download / line-discipline
  step**, so `hci0` is never created.
- Knock-on: bluez loses its controller → PipeWire's WiiM BT sink disappears →
  audio silently falls back to HDMI.
- **The chip wedges.** Once the bad binary half-inits the BCM4362, a software
  restart of `ap6275p-bluetooth.service` cannot recover it — even reinstalling
  the *good* binary stalls at the same spot (patchram runs, but no `hci0`;
  `fuser /dev/ttyS9` shows nothing held). **A reboot is required** to hard-reset
  the chip/UART; then the good binary brings `hci0` up normally at boot.

## Root cause (most likely)
The size delta (~3×) says this is a **meaningfully different/newer source
revision** than the one that built the working blob. patchram does a stateful,
cold-state-dependent firmware handshake; this revision's sequence doesn't suit
the 5B's BCM4362A2 wiring. A clean compile of the *wrong revision* is still the
wrong program.

## What a future attempt needs
- Identify the **exact upstream revision** that produced the 23,712-byte working
  blob (md5 `8553eae65a627c31cb0152e0eeb9dd56`), not just "OPi's source." Check
  older `orangepi-build` history / per-family blob sources
  (`external/packages/blobs/bt/brcm_patchram_plus/`).
- Validate the same way: build natively on the Pi, back up the good binary,
  `install -m755` the new one (NOT `cp` — live binary gives ETXTBSY), restart the
  service, confirm `hci0` UP + a real pair/stream, and **keep a reboot handy**.

## Known-good binary (what currently ships)
`/usr/bin/brcm_patchram_plus`, 23,712 bytes, md5 `8553eae65a627c31cb0152e0eeb9dd56`,
not dpkg-owned (dropped in by the board hook from `overlay/usr/bin/`).
