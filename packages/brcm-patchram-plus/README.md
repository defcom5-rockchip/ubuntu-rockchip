# brcm_patchram_plus (vendored source)

> ⚠️ **NOT SHIPPED — failed hardware validation.** This source is kept for
> reference only. The 5B currently ships the known-good **inherited blob** from
> `overlay/usr/bin/brcm_patchram_plus`. See **[VALIDATION-FAILED.md](VALIDATION-FAILED.md)**
> for what was tried and why it doesn't work.

Broadcom utility that downloads the Bluetooth firmware patchram (`.hcd`) to
Broadcom combo chips over a serial line. On the Orange Pi 5B it loads
`BCM4362A2.hcd` for the AP6275P, driven by `ap6275p-bluetooth.service`.

The intent was to replace the inherited binary blob with a build from published
source (reproducible/auditable). It didn't pan out: this revision compiles but
fails hardware bring-up — see VALIDATION-FAILED.md. The notes below describe the
*intended* build, retained for a future attempt with the correct upstream revision.

## Provenance
- Source: `orangepi-xunlong/orangepi-build`, path
  `external/cache/sources/brcm_patchram_plus/brcm_patchram_plus.c` (branch `next`).
- Vendored from upstream commit `7f776a209b72b92e8c6a06abc83b1e7597eef5af`.
- Upstream file license: **Apache License 2.0** (see the header in
  `brcm_patchram_plus.c`). Compatible with this project's GPLv3 distribution.

## How it would be built (intended design — currently disabled)
The plan was to compile **natively inside the Noble arm64 rootfs** during the
image build, so it links the *target's* glibc. It must NOT be cross-compiled on
the build host — a host cross-build on a newer toolchain pulls in glibc symbols
(e.g. `GLIBC_2.42`) too new for Noble's glibc 2.39, and the binary fails to run
on the Pi. (This part held up; the failure was at hardware bring-up, not the build.)

Build command that was used:
```sh
gcc -std=gnu17 -O2 \
    -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion \
    -o brcm_patchram_plus brcm_patchram_plus.c
strip brcm_patchram_plus
```
- `-std=gnu17` is required: the code uses a K&R-style `int (*)()` function-pointer
  table that breaks under GCC's newer C23 default (`()` == `(void)`).
- The `-Wno-*` flags quiet legacy-C diagnostics that newer GCC promotes to errors.

## Current behaviour
The 5B board hook does **not** build this — it ships the known-good inherited
blob from `overlay/usr/bin/brcm_patchram_plus`. The from-source path is parked
until the correct upstream revision is found. See
[VALIDATION-FAILED.md](VALIDATION-FAILED.md).
