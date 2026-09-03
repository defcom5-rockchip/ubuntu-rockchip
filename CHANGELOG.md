# Changelog

All notable changes to this fork of `ubuntu-rockchip` are documented in this file.

This project follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where it makes sense for an image-distribution project.

Upstream changes from [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) prior to this fork are not re-documented here — see that project's history.

---

## [Unreleased]

### Added
- **WiiM Play** ships by default on the **desktop** flavor — a GTK3 UPnP/DLNA control point for [WiiM music streamers](https://www.wiimhome.com/). Built from source (pinned to upstream [`shumatech/wiimplay`](https://github.com/shumatech/wiimplay) `v0.2`, GPLv3) inside the live-build chroot via `config/hooks/normal/50-wiimplay.hook.chroot`; installs `/usr/bin/wiimplay` + a system launcher, then purges the build toolchain so it doesn't bloat the image. Not included on the server flavor (no GUI).
- Audio HDMI⇄Bluetooth switching notes at `/usr/share/doc/wiim-play/audio-output.md` (PipeWire output switching + the Bluetooth 24-bit/96 kHz LDAC ceiling vs. full-resolution HDMI).

### Planned
- Rebuild `brcm_patchram_plus` from source to replace the inherited blob (overlay → `/usr/bin/`) used for AP6275P / BCM4362A2 Bluetooth firmware loading. **First attempt failed hardware validation:** Orange Pi's *current* source revision (vendored at `packages/brcm-patchram-plus/`, Apache-2.0) compiles cleanly on Noble arm64 but the resulting binary never completes the firmware download / line-discipline step, wedging the chip until reboot — it's a newer/different revision than the one that built the working blob. Needs the matching upstream revision before this is viable. See `packages/brcm-patchram-plus/VALIDATION-FAILED.md`. (Supersedes the earlier mis-scoped "rebuild hcitools" item: Orange Pi's `hcitools` source builds `hciattach`/`hcitool`/`hciconfig`, none of which the 5B uses.)
- Evaluate RK3588 4K@120Hz support (VOP2 dclk limits) from upstream PR #1326, pending hardware verification on Orange Pi 5B.

---

## [1.0.1] — 2026-06-01

Security assessment and mitigation release. Addresses the notable Linux kernel
local-privilege-escalation CVEs disclosed in spring 2026, by auditing which
vulnerable code is actually present in this kernel's build configuration and
mitigating the exploitable attack surface.

### Security

A full assessment of the spring-2026 kernel LPE CVEs against this image's kernel
configuration (verified via `/proc/config.gz`):

| CVE | Name | Subsystem | Kernel config | Status |
|---|---|---|---|---|
| CVE-2026-31431 | Copy Fail | algif_aead (AF_ALG) | `CONFIG_CRYPTO_USER_API_AEAD` not set | **Not affected** — code not built |
| CVE-2026-43500 | Dirty Frag (rxrpc) | RxRPC / AFS | `CONFIG_AF_RXRPC` not set | **Not affected** — code not built |
| CVE-2026-43284 | Dirty Frag (ESP) | IPsec ESP | `esp4`/`esp6` built as modules | **Mitigated** — modules blacklisted |
| CVE-2026-43494 | PinTheft | RDS | `rds`/`rds_tcp` built as modules | **Mitigated** — modules blacklisted |
| CVE-2026-46333 | ssh-keysign-pwn | ptrace | built-in | **Patched** in v1.0.0 (kernel) |

### Added
- `overlay/etc/modprobe.d/99-defcom5-cve-mitigations.conf` — blacklists the
  `esp4`, `esp6`, `rds`, and `rds_tcp` modules to neutralize the exploitable
  attack surface for CVE-2026-43284 (Dirty Frag, IPsec ESP) and CVE-2026-43494
  (PinTheft, RDS). These modules are built in the Rockchip BSP kernel but are
  not loaded by default and are not needed for normal Orange Pi 5B operation.
  The file is self-documenting and includes reversal instructions for users who
  need IPsec or RDS. **Note: WireGuard and Tailscale do not use IPsec ESP and
  are unaffected by this blacklist.**
- Copy instruction in the `orangepi-5b` board hook to deploy the mitigation file
  into built images.

### Notes
- This release does **not** rebuild the kernel. Two of the relevant CVEs are not
  exploitable because the vulnerable code is not compiled in; the other two are
  neutralized by preventing the affected (unused) modules from loading. This is
  a deliberate, lower-risk approach than cherry-picking patches onto the
  divergent vendor BSP tree (which is at 6.1.75, ~99 stable point releases
  behind upstream 6.1.y).
- Practical exposure on a single-user homelab Orange Pi 5B was already low (all
  of these are local-privilege-escalation CVEs requiring an existing
  unprivileged shell). The mitigations harden the image for all users regardless.

---

## [1.0.0] — 2026-05-31

Initial public release of the defcom5-rockchip fork. Continuation of Joshua-Riek/ubuntu-rockchip, which was archived by its original maintainer.

### Added
- Public repository for community visibility and use.
- `README.md`, `CHANGELOG.md`, `SECURITY.md`, and `NOTICE` documenting scope, history, security policy, and attribution.
- `scripts/install-wiimplay.sh` — optional post-install helper to build and install the [wiimplay](https://github.com/shumatech/wiimplay) UPnP controller. Not part of the base image.

### Changed
- Kernel source now pulled from [defcom5-rockchip/linux-rockchip-rk3588](https://github.com/defcom5-rockchip/linux-rockchip-rk3588) (branch `noble-security`) instead of the archived upstream kernel repository.
- Kernel package bumped to `linux-rockchip` ABI `6.1.0-1027.27`.
- `scripts/build-kernel.sh` patched for GCC 14+ host compatibility (sets `KCFLAGS="-Wno-error"` for the kernel proper and strips hardcoded `-Werror` from libbpf, libsubcmd, objtool, and libperf tool Makefiles). Without this, the 6.1 vendor tree fails to compile on Ubuntu 24.04+ / Debian Trixie+ hosts.
- Build tested and validated on Orange Pi 5B hardware running Ubuntu 24.04 (Noble Numbat).

### Removed
- Suite configurations for `jammy.sh`, `oracular.sh`, and `plucky.sh`. This fork's supported scope is Ubuntu 24.04 (Noble) on Orange Pi 5B only.

### Security
- Backported fix for **CVE-2026-46333** (`ssh-keysign-pwn`), a local information-disclosure vulnerability in the Linux kernel's `__ptrace_may_access()` logic. The fix is the upstream commit `31e62c2ebbfd` ("ptrace: slightly saner `get_dumpable()` logic"), cherry-picked onto the `noble-security` branch.
  - Severity: CVSS 5.5 (Medium)
  - Disclosed: 2026-05-14 by Qualys Threat Research Unit
  - Mitigation alternative without the patch: set `kernel.yama.ptrace_scope=2` via sysctl.

### Inherited from upstream (unchanged)
- All board overlays, device trees, firmware, and userspace overlays from Joshua-Riek's last public release.
- `EXTRA_PPAS=jjriek/rockchip jjriek/rockchip-multimedia` for userspace packages. These PPAs are no longer maintained but the package versions there remain installable.
- Panfork Mesa PPA (`ppa:jjriek/panfork-mesa`) for Mali G610 GPU support — also no longer actively maintained.
- `brcm_patchram_plus` binary blob (overlay → `/usr/bin/`) for AP6275P / BCM4362A2 Bluetooth firmware loading on the Orange Pi 5B.

---

## Release tag conventions

- **Major version** (`X.0.0`): substantial rebase against a new upstream Ubuntu release, or a breaking change to the build process.
- **Minor version** (`1.X.0`): kernel ABI bump, new board support, or notable feature additions.
- **Patch version** (`1.0.X`): security backports, bug fixes, configuration tweaks.

[Unreleased]: ../../compare/defcom5-v1.0.1...HEAD
[1.0.1]: ../../releases/tag/defcom5-v1.0.1
[1.0.0]: ../../releases/tag/defcom5-v1.0.0
