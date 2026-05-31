# Security Policy

## Scope

This is a personal fork of [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) maintained on a best-effort basis by a single individual. It is offered as-is, with no warranty or guaranteed response time.

If you require a project with a formal security process and SLA, this is not it — please use an officially supported distribution instead.

## Important: kernel CVE coverage is not comprehensive

The kernel package shipped with this fork's images is built from a community kernel tree (`defcom5-rockchip/linux-rockchip-rk3588`) descended from Joshua-Riek's archived `linux-rockchip`. **This kernel is not part of Canonical's noble kernel security pipeline.** It does not receive automatic CVE backports from Canonical's kernel team, and `apt update && apt upgrade` will not pull kernel security updates for it.

The maintainer of this fork backports kernel CVEs case-by-case, focused on issues that are likely to affect the supported use case (Orange Pi 5B single-user homelab). **There is no claim that every disclosed Linux kernel CVE has been evaluated or backported.**

The [CHANGELOG.md](./CHANGELOG.md) lists explicitly what has been backported in each release and, where notable CVEs have *not* been backported, calls that out as well. Before deploying this image in a context where kernel-level security matters, read the "Known security gaps" section of the latest release's changelog entry.

If you need a comprehensively CVE-patched kernel on the Orange Pi 5B, this fork is the wrong choice. Use an image whose kernel pulls from Canonical's main security archive, or accept the burden of cherry-picking kernel CVEs yourself.

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
- Case-by-case backporting of upstream Linux kernel security fixes that materially affect the supported use case.
- No commitment to a release cadence or response time.
- No commitment to back-port every disclosed kernel CVE.

## Supported versions

Only the **most recent published release** receives security updates. Older releases are unsupported.

| Version | Supported |
|---|---|
| Latest release | ✅ (within scope above) |
| Any older release | ❌ |

## Upstream sources for kernel security fixes

This fork tracks (but does not exhaustively backport from) the following sources:

- [Ubuntu Security Notices](https://ubuntu.com/security/notices)
- [Linux kernel security mailing list](https://www.kernel.org/category/security-bugs.html)
- [CISA advisories](https://www.cisa.gov/news-events/cybersecurity-advisories)

If you see a CVE listed there that affects the Linux kernel and isn't yet backported here, feel free to open an Issue to flag it — but understand that whether it gets backported depends on relevance to the supported use case and maintainer time.
