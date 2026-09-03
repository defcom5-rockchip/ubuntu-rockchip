# Agent instructions

This is the image BUILD SYSTEM (fork of Joshua-Riek/ubuntu-rockchip) for
Pi Desktop / Pi Studio on the Orange Pi 5B. Hooks in config/hooks/normal/
carry their reasoning in comments — read the comment before changing the code.

## Bake invariants (each one cost a broken build to learn)
1. **fullbuild runs DETACHED only** (`sudo -v`, then `sudo nohup env
   PISTUDIO_VENDOR=... bash ~/rebake/fullbuild.sh > log 2>&1 &`; watch via
   `tail -f`). A foreground pipeline that owns the tty dies at a cosmetic
   apt /dev/pts error. Backgrounded sudo without a fresh ticket waits forever.
2. **The debs/ manifest installs NOTHING.** Every custom .deb needs an
   explicit `apt-get install` line in a hook (see hook 64). A deb staged
   without one silently ships absent (betterbird was a ghost for a full
   release this way).
3. **PISTUDIO_VENDOR must be passed explicitly** for desktop bakes
   (/mnt/build/PI_Studio/vendor-desktop) — the default is the Studio vendor
   and produces a chimera image.
4. **oem-config is NOT to be masked** — it creates the first user. Its single
   failed unit on first boot self-heals by boot two.
5. **Pre-push census:** grep the full diff for personal identifiers and
   secrets before any push (names, emails, LAN IPs, passwords, keys).
   Commit as defcom5-rockchip only; Claude co-author trailer welcome.
6. **Every image is swept before ship:** boot journal diffed against the
   steady-state baseline (BOOT-SWEEP files on the team share), two boots,
   hardware checks per the release's changes. Ship is a human decision.
