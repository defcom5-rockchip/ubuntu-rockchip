# Changelog

All notable changes to this fork of `ubuntu-rockchip` are documented in this file.

This project follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where it makes sense for an image-distribution project.

Upstream changes from [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) prior to this fork are not re-documented here — see that project's history.

---

## [Unreleased]

### Planned
- Evaluate and cherry-pick additional upstream kernel CVE fixes onto the `noble-security` branch as time permits. Candidates include CVE-2026-31431 (Copy Fail), CVE-2026-43284 / -43500 (Dirty Frag), and CVE-2026-43494 (PinTheft). See [README → Known limitations](./README.md#known-limitations) for current scope and rationale.
- Rebuild `hcitools` from [Orange Pi's published source](https://github.com/orangepi-xunlong/orangepi-build/tree/next/external/cache/sources/hcitools) to replace the inherited binary blob in `/usr/bin/`.

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

### Known security gaps in v1.0.0

Important: this fork's kernel is **not** comprehensively CVE-patched. The upstream `linux-rockchip` package was never part of Canonical's noble kernel security pipeline (it ships through a PPA, not Ubuntu's main or security archives). With Joshua-Riek's project archived, no upstream pipeline is feeding kernel CVE backports into this tree.

The only CVE explicitly backported in v1.0.0 is CVE-2026-46333 (above). Other notable 2026 kernel CVEs that are **not** explicitly backported in this release:

- **CVE-2026-31431** ("Copy Fail") — algif_aead local privilege escalation, CVSS 7.8, reported as exploited in the wild
- **CVE-2026-43284, CVE-2026-43500** ("Dirty Frag") — local privilege escalation pair
- **CVE-2026-43494** ("PinTheft") — RDS zerocopy double-free, local privilege escalation. RDS is not loaded by default on Ubuntu so practical exposure is gated by whether the user explicitly loads the module.

For the OPi 5B single-user homelab use case for which this fork is maintained, the practical exposure to these LPE-class CVEs is bounded by the fact that no untrusted users have shell access. But this is a *risk assessment*, not a "fully patched" claim. Users with multi-user systems or stricter security postures should evaluate accordingly.

### Inherited from upstream (unchanged)
- All board overlays, device trees, firmware, and userspace overlays from Joshua-Riek's last public release.
- `EXTRA_PPAS=jjriek/rockchip jjriek/rockchip-multimedia` for userspace packages. These PPAs are no longer maintained but the package versions there remain installable.
- Panfork Mesa PPA (`ppa:jjriek/panfork-mesa`) for Mali G610 GPU support — also no longer actively maintained.
- `hcitools` binary blob in `/usr/bin/` for Bluetooth firmware loading on RK3588 combo chips. See [Unreleased] for rebuild plans.

---

## Release tag conventions

- **Major version** (`X.0.0`): substantial rebase against a new upstream Ubuntu release, or a breaking change to the build process.
- **Minor version** (`1.X.0`): kernel ABI bump, new board support, or notable feature additions.
- **Patch version** (`1.0.X`): security backports, bug fixes, configuration tweaks.

[Unreleased]: ../../compare/defcom5-v1.0.0...HEAD
[1.0.0]: ../../releases/tag/defcom5-v1.0.0
