# ubuntu-rockchip (defcom5-rockchip fork)

A personal fork of [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip), continuing this image-builder project for Orange Pi 5B after the original was archived.

> **Scope:** Orange Pi 5B only — the only hardware I own and test on.
> **Support:** Best-effort. No release schedule, no SLA, no guarantees. Use at your own risk.
> **Security scope:** Limited and case-by-case. See [Known limitations](#known-limitations) and [SECURITY.md](./SECURITY.md) before assuming this fork's kernel is comprehensively CVE-patched.
> **Not affiliated** with Orange Pi, Canonical, Ubuntu, or the original Joshua-Riek project.

---

## Why this fork exists

Joshua Riek's `ubuntu-rockchip` was the de-facto Ubuntu image for RK3588-class Orange Pi boards for years. After it was archived, I needed a working build pipeline for my own homelab Orange Pi 5B, so I forked it, fixed what needed fixing to keep the build working on a modern host, and backported one upstream CVE that mattered to me. I'm publishing the result in case it's useful to anyone else in a similar position.

This is **not** a replacement for the original project, and it is **not** a comprehensively security-maintained fork. It's one person keeping one board's build working, with the source open so others can use it, audit it, or fork it further.

## Credits

All of the heavy lifting in this image came from [Joshua Riek](https://github.com/Joshua-Riek) and contributors to the original `ubuntu-rockchip` project. This fork inherits their work. If you find this useful, please remember whose shoulders it's standing on.

## What's different from upstream

See [CHANGELOG.md](./CHANGELOG.md) for the full history. Headline items in v1.0.0:

- Kernel sourced from [defcom5-rockchip/linux-rockchip-rk3588](https://github.com/defcom5-rockchip/linux-rockchip-rk3588) (branch: `noble-security`)
- Kernel package built at ABI `6.1.0-1027.27`
- One upstream CVE explicitly backported: **CVE-2026-46333** (`ssh-keysign-pwn`). See [Known limitations](#known-limitations) for what is *not* backported.
- `scripts/build-kernel.sh` patched for GCC 14+ host compatibility — without this, the 6.1 vendor tree fails to build on Ubuntu 24.04+ / Debian Trixie+ hosts
- Built and tested on Orange Pi 5B with Ubuntu 24.04 (Noble Numbat)

Everything else is intentionally preserved from upstream.

## Supported hardware

| Board | Status |
|---|---|
| Orange Pi 5B | ✅ Tested, used as daily driver |
| Other RK3588 boards (5 / 5 Plus / 5 Max / CM5 / etc.) | ❌ Not supported by this fork. Suite configs for other releases have been removed. |

If you want support for other boards or Ubuntu releases, please fork this repository — the original `ubuntu-rockchip` project supported a wider range and the build system is still capable of it.

## Installation

Download the latest `.img.xz` from the [Releases page](../../releases), then flash it like any Ubuntu SBC image:

```bash
# Decompress
xz -d ubuntu-24.04-preinstalled-desktop-arm64-orangepi-5b-defcom5-v1.0.0.img.xz

# Flash to SD card or eMMC (replace /dev/sdX with your actual device — get this WRONG and you wipe a disk)
sudo dd if=ubuntu-24.04-preinstalled-desktop-arm64-orangepi-5b-defcom5-v1.0.0.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Or use a GUI tool like [balenaEtcher](https://etcher.balena.io/) or `rpi-imager`.

First boot completes the cloud-init setup; default credentials and first-boot behavior are unchanged from upstream — see Joshua-Riek's original documentation for details.

## Known limitations

### Kernel CVE coverage is NOT comprehensive

This is the most important thing to understand before relying on this image for anything beyond a single-user homelab.

The upstream `linux-rockchip` kernel package (which this fork builds from) was **never part of Canonical's noble kernel security pipeline**. It is a PPA-only package, not in Ubuntu's main or security repos, and therefore does not receive automatic CVE backports from Canonical's kernel team. Joshua-Riek's repo periodically merged from upstream Linux, but since the project was archived, that pipeline has stopped.

What this means in practice:

- The only CVE explicitly backported in this fork's v1.0.0 kernel is **CVE-2026-46333** (`ssh-keysign-pwn`).
- Other kernel CVEs disclosed in 2026 (including **CVE-2026-31431** "Copy Fail", **CVE-2026-43284 / -43500** "Dirty Frag", **CVE-2026-43494** "PinTheft", and others) are **not** explicitly backported here. They may or may not be present in the underlying 6.1.x stable base depending on when that base was last refreshed.
- `apt update && apt upgrade` will NOT install kernel security updates for this kernel, because the kernel package does not come from Canonical's security pipeline.

For most kernel CVEs, the practical exploitation prerequisite is local shell access as an unprivileged user. On a single-user homelab Orange Pi where you are the only one with credentials, your exposure to most of these is limited — but you should make that risk assessment deliberately rather than assuming "v1.0.0 is fully patched."

If you need a comprehensively CVE-patched kernel for the Orange Pi 5B, consider using a different image whose kernel pulls from Canonical's main security pipeline, or accept the maintenance burden of cherry-picking kernel CVEs yourself.

### Other inherited limitations

- **`hcitools` is currently a binary blob** inherited from upstream in `/usr/bin/`. Orange Pi has since [published the source](https://github.com/orangepi-xunlong/orangepi-build/tree/next/external/cache/sources/hcitools); rebuilding from source is on the roadmap.
- **PPAs inherited from upstream are no longer maintained.** The build pulls userspace packages from `ppa:jjriek/rockchip` and `ppa:jjriek/rockchip-multimedia`. These PPAs have not been updated since the original project was archived, so package versions there are effectively frozen.
- **GPU acceleration** depends on the Panfork Mesa PPA (`ppa:jjriek/panfork-mesa`), also no longer actively maintained.
- **No automated CI builds.** Releases are built manually on my workstation when I cut them.
- **Only Ubuntu 24.04 (Noble) is supported.** Suite configs for `jammy`, `oracular`, and `plucky` have been removed.

## Reporting issues

Open a [GitHub Issue](../../issues). Include:

- Board model (only Orange Pi 5B is supported — reports for other boards are unlikely to get a fix)
- Image version (from the release tag)
- `uname -r` output
- A clear description of the problem and how to reproduce it

Response is best-effort.

## Building from source

The build process inherits from Joshua-Riek's original tooling. In short:

```bash
git clone https://github.com/defcom5-rockchip/ubuntu-rockchip
cd ubuntu-rockchip
sudo ./build.sh
```

You'll need a reasonably beefy Linux build host with plenty of disk space (~50 GB) and time. The build script will clone the kernel source from [defcom5-rockchip/linux-rockchip-rk3588](https://github.com/defcom5-rockchip/linux-rockchip-rk3588) automatically.

## Optional post-install scripts

The `scripts/` directory contains optional helpers I use on my own installs. They are **not** baked into the base image, so users who don't want them aren't affected.

- **`scripts/install-wiimplay.sh`** — builds and installs [wiimplay](https://github.com/shumatech/wiimplay) (a GTK3 UPnP control point for WiiM music streamers) on your user account, including a launcher entry.

## License

This project inherits the upstream project's licenses. The kernel and most userspace components are under GPL-2.0 or GPL-3.0; individual files and submodules retain their own licenses. See [LICENSE](./LICENSE) for the umbrella license text and [NOTICE](./NOTICE) for attribution.

## Security

See [SECURITY.md](./SECURITY.md) for the reporting policy, supported-versions table, and an honest statement of this fork's security scope.

---

*Maintained by [defcom5-rockchip](https://github.com/defcom5-rockchip). Continuing the work of [Joshua-Riek](https://github.com/Joshua-Riek) with gratitude.*
