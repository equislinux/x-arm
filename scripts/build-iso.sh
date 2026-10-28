#!/usr/bin/env bash
# build-iso.sh — build the aarch64 live ISO with archiso.
#
# Prerequisites:
#   scripts/fetch-x.sh && scripts/fetch-archiso.sh && scripts/apply-overlay.sh
#   scripts/build-repo.sh         (unless --no-repo)
#
# Usage:
#   sudo scripts/build-iso.sh [--repo DIR | --no-repo] [--no-clean] [--allow-cross]
#
# Options:
#   --repo DIR      local [x] repository (default: out/repo/aarch64)
#   --no-repo       use the published https [x]/aarch64 instead
#   --no-clean      keep work/ for debugging
#   --allow-cross   try anyway on a non-aarch64 host (unsupported)
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

REPO="$OUT/repo/$ARCH"
NO_REPO=0
NO_CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)        REPO="${2:?--repo needs a path}"; shift 2 ;;
        --no-repo)     NO_REPO=1; shift ;;
        --no-clean)    NO_CLEAN=1; shift ;;
        --allow-cross) export X_ARM_ALLOW_CROSS=1; shift ;;
        -h|--help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_root
require_aarch64
require_cmds_iso

[[ -f "$X_DIR/profiledef.sh" ]] || die "vendor/x is missing; run fetch-x.sh and apply-overlay.sh"
grep -q '^arch="aarch64"' "$X_DIR/profiledef.sh" \
    || die "vendor/x is not overlaid for aarch64; run scripts/apply-overlay.sh"

if [[ "$NO_REPO" -eq 1 ]]; then
    REPO_URL="$(x_repo_url)"
    log "[x] source: $REPO_URL"
else
    [[ -f "$REPO/x.db.tar.gz" ]] || die "no [x] repo at $REPO; run scripts/build-repo.sh first"
    REPO_URL="file://$(cd -- "$REPO" && pwd)"
    log "[x] source: $REPO_URL"
fi

MKARCHISO="$(command -v mkarchiso || true)"
if [[ -z "$MKARCHISO" ]]; then
    MKARCHISO="$ARCHISO_DIR/archiso/mkarchiso"
    [[ -x "$MKARCHISO" ]] || die "mkarchiso not found (install archiso or run scripts/fetch-archiso.sh)"
fi

MIRRORLIST="$ROOT/overlay/airootfs/etc/pacman.d/mirrorlist"
[[ -f "$MIRRORLIST" ]] || die "missing $MIRRORLIST"

log "rendering $X_DIR/pacman.aarch64.conf"
sed -e "s|@X_REPO@|$REPO_URL|g" -e "s|@MIRRORLIST@|$MIRRORLIST|g" \
    "$ROOT/overlay/pacman.aarch64.conf.in" >"$X_DIR/pacman.aarch64.conf"

command -v ukify >/dev/null 2>&1 \
    || warn "systemd-ukify is missing; archiso will skip merging device trees"
if ! grep -qx stubble "$X_DIR/packages.aarch64"; then
    warn "stubble is not in packages.aarch64 (not packaged in ALARM); DTBs will not be merged"
fi

WORK="$ROOT/work"
ISO_OUT="$OUT/iso"

# Leftover mounts from a previous interrupted run.
for mp in "$WORK/$ARCH/airootfs/proc" "$WORK/$ARCH/airootfs/sys" \
          "$WORK/$ARCH/airootfs/dev" "$WORK/$ARCH/airootfs/run"; do
    if mountpoint -q "$mp"; then umount -l "$mp" || true; fi
done
if mountpoint -q "$WORK/$ARCH/airootfs"; then umount -Rl "$WORK/$ARCH/airootfs" || true; fi

if [[ "$NO_CLEAN" -eq 0 ]]; then
    log "cleaning work/ and out/iso/"
    rm -rf -- "$WORK" "$ISO_OUT"
fi
mkdir -p "$ISO_OUT" "$OUT"

LOG="$OUT/build-$(date +%Y%m%d-%H%M).log"
log "building ISO (log: $LOG)"
set +e
"$MKARCHISO" -C "$X_DIR/pacman.aarch64.conf" -v -w "$WORK" -o "$ISO_OUT" "$X_DIR" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
[[ "$rc" -eq 0 ]] || die "mkarchiso failed (see $LOG)"

ISO="$(find "$ISO_OUT" -maxdepth 1 -type f -name "x-*-$ARCH.iso" \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
[[ -n "$ISO" && -f "$ISO" ]] || die "no ISO produced (see $LOG)"

log "verifying boot files"
listing="$(bsdtar -tf "$ISO" 2>/dev/null || true)"
if [[ -z "$listing" ]]; then
    listing="$(xorriso -indev "$ISO" -find / -type f -exec lsdl 2>/dev/null || true)"
fi
grep -q 'BOOTAA64.EFI' <<<"$listing" || die "ISO has no EFI/BOOT/BOOTAA64.EFI"
grep -qE '/?arch/boot/aarch64/Image$' <<<"$listing" || die "ISO has no /arch/boot/aarch64/Image"
grep -q 'initramfs-linux.img' <<<"$listing" || die "ISO has no initramfs-linux.img"

log "ISO ready: $ISO ($(du -h "$ISO" | cut -f1))"
sha256sum "$ISO" | tee "$ISO.sha256"
