# Security Policy

## Scope

This is a personal fork of [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) maintained on a best-effort basis by a single individual. It is offered as-is, with no warranty or guaranteed response time.

If you require a project with a formal security process and SLA, this is not it — please use an officially supported distribution instead.

## How kernel security works in this fork

The kernel package shipped with this fork's images is built from a community kernel tree (`defcom5-rockchip/linux-rockchip-rk3588`) descended from Joshua-Riek's archived `linux-rockchip`. **This kernel is not part of Canonical's noble kernel security pipeline.** It does not receive automatic CVE backports, and `apt update && apt upgrade` will not pull kernel security updates for it. The maintainer is the security pipeline for this fork.

What this means in practice:

- Kernel CVEs are evaluated **case-by-case** as they are disclosed.
- For each relevant CVE, the first step is checking whether the vulnerable code is even built into this kernel's configuration (the Rockchip BSP kernel trims many options). Several CVEs turn out to be **not applicable** because the affected code is not compiled in.
- For CVEs where the code is present, the fix is either a kernel patch (cherry-picked onto `noble-security`) or, where appropriate, a module blacklist / boot-parameter mitigation shipped in the image overlay.
- The [CHANGELOG.md](./CHANGELOG.md) documents the assessment and resolution of each CVE per release, including those determined to be not-applicable.

**There is no claim that every disclosed Linux kernel CVE is evaluated immediately or comprehensively.** Assessment depends on relevance to the supported use case (Orange Pi 5B) and maintainer time. If you need comprehensive kernel CVE coverage, use an image whose kernel pulls from Canonical's main security archive.

## Reporting a vulnerability

Open a [GitHub Issue](../../issues) describing the problem. Include:

- The CVE identifier if one has been assigned
- The affected component (kernel, userspace package, configuration, binary in `/usr/bin/`, etc.)
- The image version or release tag where you observed it
- A description of the impact and, if applicable, reproduction steps

For issues affecting upstream Ubuntu kernels or packages, please **also** report them to the appropriate upstream project — Canonical, Linux kernel security, or the relevant package maintainer — as this fork only redistributes their work.

If a vulnerability is severe and you would prefer not to disclose it publicly via Issues, you may contact the maintainer directly through GitHub. Note that this fork does not operate a formal embargoed-disclosure process.

## What to expect

- Acknowledgment when I have time (typically days, not hours).
- Best-effort assessment of severity and applicability to this fork's scope (Orange Pi 5B, Ubuntu 24.04).
- Case-by-case patching or mitigation of kernel CVEs that materially affect the supported use case.
- No commitment to a release cadence or response time.
- No commitment to evaluate every disclosed kernel CVE immediately.

## Supported versions

Only the **most recent published release** receives security updates. Older releases are unsupported.

| Version | Supported |
|---|---|
| Latest release | ✅ (within scope above) |
| Any older release | ❌ |

## Upstream sources for kernel security fixes

This fork tracks (but does not exhaustively backport from) the following:

- [Ubuntu Security Notices](https://ubuntu.com/security/notices)
- [Linux kernel security mailing list](https://www.kernel.org/category/security-bugs.html)
- [CISA advisories](https://www.cisa.gov/news-events/cybersecurity-advisories)

If you see a CVE affecting the Linux kernel that isn't yet assessed here, feel free to open an Issue to flag it — but whether it gets patched depends on relevance to the supported use case and maintainer time.
