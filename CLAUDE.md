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

## Media stack decisions (2026-09-04) — the reasoning, so it isn't re-litigated
- **mpv 0.38 is the default video player**, not VLC. mpv is the client that
  hardware-decodes through the rockchip VA-API driver (H.264 including B-frame
  streams, HEVC 8-bit and Main10, VP9). VLC 3's VA-API interop is X11-era and
  software-decodes under XWayland here — correct picture, CPU-bound at 4K. VLC
  stays installed as the plays-everything fallback. Set via `mimeapps.list` in
  hook 62.
- **One mpv on the image.** apt's 0.36 is not installed; `defcom5-mpv038`
  provides `/usr/local/bin/mpv`. The deb is installed by an explicit line in
  hook 64 with a version glob — the `debs/` manifest installs nothing by itself.
- **`hwdec=auto-copy`, never plain `auto`.** With `auto`, mpv picks its own
  built-in rkmpp decoder for 10-bit content, bypasses the VA-API driver, and
  hands panfork a surface it cannot sample — solid blue picture.
- **10-bit guard in skel `mpv.conf`.** panfork advertises 16-bit GL textures it
  cannot render; the conditional profile converts 10-bit to 8-bit before upload
  (the panel is 8-bit — no visible loss). Remove it only when the GPU stack
  moves past panfork.
- **Firefox is the default browser and gets `media.hevc.enabled`** in its
  enterprise policies — HEVC hardware decode is gated behind that pref on Linux
  and defaults off. Firefox is both flicker-free and HEVC-capable here; Chrome
  would have to give up its flicker fix to hardware-decode, so it stays scoped
  to DRM streaming.
