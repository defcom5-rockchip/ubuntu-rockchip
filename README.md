# ubuntu-rockchip (defcom5-rockchip fork)

A personal fork of [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip), continuing this image-builder project for Orange Pi 5B after the original was archived.

> **Scope:** Orange Pi 5B only — the only hardware I own and test on.
> **Support:** Best-effort. No release schedule, no SLA, no guarantees. Use at your own risk.
> **Security scope:** Case-by-case, but actively assessed. See [Kernel security](#kernel-security) and [SECURITY.md](./SECURITY.md).
> **Not affiliated** with Orange Pi, Canonical, Ubuntu, or the original Joshua-Riek project.

---

## Why this fork exists

Joshua Riek's `ubuntu-rockchip` was the de-facto Ubuntu image for RK3588-class Orange Pi boards for years. After it was archived, I needed a working build pipeline for my own homelab Orange Pi 5B, so I forked it, fixed what needed fixing to keep the build working on a modern host, and have been keeping it patched against relevant kernel CVEs. I'm publishing the result in case it's useful to anyone else in a similar position.

This is **not** a replacement for the original project. It's one person keeping one board's build working and reasonably current on security, with the source open so others can use it, audit it, or fork it further.

## Credits

All of the heavy lifting in this image came from [Joshua Riek](https://github.com/Joshua-Riek) and contributors to the original `ubuntu-rockchip` project. This fork inherits their work. If you find this useful, please remember whose shoulders it's standing on.

## What's different from upstream

See [CHANGELOG.md](./CHANGELOG.md) for the full history. Headline items:

- Kernel sourced from [defcom5-rockchip/linux-rockchip-rk3588](https://github.com/defcom5-rockchip/linux-rockchip-rk3588) (branch: `noble-security`)
- Kernel package built at ABI `6.1.0-1027.27`
- Upstream CVE-2026-46333 (`ssh-keysign-pwn`) backported into the kernel (v1.0.0)
- Spring-2026 kernel LPE CVEs (Copy Fail, Dirty Frag, PinTheft) assessed and, where applicable, mitigated (v1.0.1) — see [Kernel security](#kernel-security)
- `scripts/build-kernel.sh` patched for GCC 14+ host compatibility
- Built and tested on Orange Pi 5B with Ubuntu 24.04 (Noble Numbat)

Everything else is intentionally preserved from upstream.

## Supported hardware

| Board | Status |
|---|---|
| Orange Pi 5B | ✅ Tested, used as daily driver |
| Other RK3588 boards (5 / 5 Plus / 5 Max / CM5 / etc.) | ❌ Not supported by this fork. Suite configs for other releases have been removed. |

*Orange Pi 5 Pro users:* an unmerged upstream PR ([#1343](https://github.com/Joshua-Riek/ubuntu-rockchip/pull/1343)) addresses known AP6256 Wi-Fi instability. It is not included in this fork (5B scope only); if you fork further, consider applying it.

If you want support for other boards or Ubuntu releases, please fork this repository — the original `ubuntu-rockchip` project supported a wider range and the build system is still capable of it.

## Installation

Download the latest `.img.xz` from the [Releases page](../../releases), then flash it like any Ubuntu SBC image:

```bash
# Decompress
xz -d ubuntu-24.04-preinstalled-desktop-arm64-orangepi-5b-defcom5-v1.0.1.img.xz

# Flash to SD card or eMMC (replace /dev/sdX with your actual device — get this WRONG and you wipe a disk)
sudo dd if=ubuntu-24.04-preinstalled-desktop-arm64-orangepi-5b-defcom5-v1.0.1.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Or use a GUI tool like [balenaEtcher](https://etcher.balena.io/) or `rpi-imager`.

## Kernel security

This fork takes kernel security seriously but is **not** a substitute for a kernel that pulls from Canonical's official security pipeline. Here's the honest picture:

The `linux-rockchip` kernel package was never part of Canonical's noble kernel security pipeline — it ships through a community PPA, not Ubuntu's main or security archives. With Joshua-Riek's project archived, no upstream pipeline automatically feeds kernel CVE backports into this tree, and `apt upgrade` will not update this kernel. **The maintainer is the security pipeline for this fork.**

What that means in practice, and what has actually been done:

- **CVE-2026-46333** (`ssh-keysign-pwn`) — patched in the kernel (v1.0.0).
- **Spring-2026 LPE CVEs** — each was assessed against this kernel's actual build configuration (v1.0.1):
  - **CVE-2026-31431** (Copy Fail) and **CVE-2026-43500** (Dirty Frag / rxrpc): **not affected** — the vulnerable code (`CONFIG_CRYPTO_USER_API_AEAD`, `CONFIG_AF_RXRPC`) is not built into this kernel.
  - **CVE-2026-43284** (Dirty Frag / IPsec ESP) and **CVE-2026-43494** (PinTheft / RDS): the modules are built but unused; they are **blacklisted** via `/etc/modprobe.d/99-defcom5-cve-mitigations.conf` to neutralize the attack surface.

See the [CHANGELOG](./CHANGELOG.md) for the full assessment table.

**Important caveats:**
- These are *mitigations and targeted patches*, not a comprehensive guarantee. New kernel CVEs are evaluated case-by-case as time permits; not every disclosed CVE will be assessed immediately.
- All of the above are *local* privilege-escalation / info-disclosure issues — they require an attacker to already have an unprivileged shell. On a single-user homelab device, practical exposure is limited regardless.
- If you need a comprehensively CVE-patched kernel, use an image whose kernel pulls from Canonical's main security pipeline, or accept the maintenance burden of tracking kernel CVEs yourself.

## Other known limitations

- **`brcm_patchram_plus` is an inherited binary blob** (shipped via the overlay to `/usr/bin/`) that loads the Bluetooth firmware (`BCM4362A2.hcd`) for the Orange Pi 5B's AP6275P combo chip, via `ap6275p-bluetooth.service`. Rebuilding it from source to drop the inherited binary is on the roadmap, but a first attempt with Orange Pi's *current* source revision failed hardware bring-up (see `packages/brcm-patchram-plus/VALIDATION-FAILED.md`) — the working blob came from an older revision that still needs to be identified. (Note: the only `hcitool` on the image is bluez's standard, package-owned tool — not a blob; there is no `hcitools`.)
- **PPAs inherited from upstream are no longer maintained** (`ppa:jjriek/rockchip`, `ppa:jjriek/rockchip-multimedia`, `ppa:jjriek/panfork-mesa`). Package versions there are effectively frozen.
- **No automated CI builds.** Releases are built manually.
- **Only Ubuntu 24.04 (Noble) is supported.**

## Reporting issues

Open a [GitHub Issue](../../issues). Include board model (5B only), image version, `uname -r`, and clear reproduction steps. Response is best-effort.

## Building from source

```bash
git clone https://github.com/defcom5-rockchip/ubuntu-rockchip
cd ubuntu-rockchip
sudo ./build.sh
```

You'll need a Linux build host with ~50 GB free and time. The build clones the kernel from [defcom5-rockchip/linux-rockchip-rk3588](https://github.com/defcom5-rockchip/linux-rockchip-rk3588) automatically.

## Optional post-install scripts

The `scripts/` directory contains optional helpers, not baked into the base image:

- **`scripts/install-wiimplay.sh`** — builds and installs [wiimplay](https://github.com/shumatech/wiimplay), a GTK3 UPnP control point for WiiM music streamers.

## License

Inherits the upstream project's licenses (GPL-2.0 / GPL-3.0; individual files retain their own). See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).

## Security

See [SECURITY.md](./SECURITY.md) for the reporting policy and supported-versions table.

---

*Maintained by [defcom5-rockchip](https://github.com/defcom5-rockchip). Continuing the work of [Joshua-Riek](https://github.com/Joshua-Riek) with gratitude.*
