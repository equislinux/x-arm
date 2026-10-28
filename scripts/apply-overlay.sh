#!/usr/bin/env bash
# apply-overlay.sh — reset vendor/x and apply the aarch64 overlay.
#
# Idempotent: the vendored checkout is reset to its pinned commit first, so a
# stale file from a previous attempt can never leak into the next build.
#
# Usage: scripts/apply-overlay.sh [--check]
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

CHECK=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

[[ -d "$X_DIR/.git" ]] || die "vendor/x is missing; run scripts/fetch-x.sh first"

log "resetting vendor/x to the pinned commit"
git -C "$X_DIR" reset --hard -q HEAD
git -C "$X_DIR" clean -fdq

log "copying overlay"
tar -C "$ROOT/overlay" \
    --exclude=patches --exclude=packages --exclude='*.patch' \
    -cf - . | tar -C "$X_DIR" -xf -

log "applying installer patch"
patch --batch --forward --silent -p1 -d "$X_DIR" \
    -i "$ROOT/overlay/patches/x-installer-aarch64.patch"

# The x86 kernel preset is dead weight on aarch64 (no 'linux' package).
rm -f "$X_DIR/airootfs/etc/mkinitcpio.d/linux.preset"

# The installer resolves /root/x-installer/packages.$(uname -m); keep a single
# source of truth for the package list.
install -Dm644 "$X_DIR/packages.aarch64" "$X_DIR/airootfs/root/x-installer/packages.aarch64"

# --- verification -----------------------------------------------------------
fail=0
check() { if eval "$2"; then log "ok: $1"; else warn "FAIL: $1"; fail=1; fi; }

check "profiledef arch is aarch64" \
    "[[ \"\$(sed -n 's/^arch=\"\\(.*\\)\"/\\1/p' \"\$X_DIR/profiledef.sh\")\" == aarch64 ]]"
check "profiledef uses packages.aarch64" \
    "grep -q '^packages_file=\"packages.aarch64\"' \"\$X_DIR/profiledef.sh\""
check "profiledef is UEFI-only" \
    "grep -q \"^bootmodes=('uefi.grub')\" \"\$X_DIR/profiledef.sh\""
check "kernel is linux-aarch64" \
    "grep -qx 'linux-aarch64' \"\$X_DIR/packages.aarch64\""
check "x86 kernel is gone from the list" \
    "! grep -qx 'linux' \"\$X_DIR/packages.aarch64\""
check "installer uses arm64-efi" \
    "grep -q 'grub-install --target=arm64-efi' \"\$X_DIR/airootfs/root/x-installer/install.sh\""
check "installer has no x86_64-efi" \
    "! grep -q 'x86_64-efi' \"\$X_DIR/airootfs/root/x-installer/install.sh\""
check "grub config uses /Image" \
    "grep -q 'boot/%ARCH%/Image' \"\$X_DIR/grub/grub.cfg\""
check "choose-mirror uses the ALARM layout" \
    "grep -q '\\\$arch/\\\$repo' \"\$X_DIR/airootfs/usr/local/bin/choose-mirror\""

for f in "$X_DIR"/airootfs/root/x-installer/*.sh; do
    bash -n "$f" || { warn "syntax error: $f"; fail=1; }
done

if [[ "$CHECK" -eq 1 ]]; then
    if [[ "$fail" -ne 0 ]]; then
        die "overlay verification failed"
    fi
else
    [[ "$fail" -eq 0 ]] || die "overlay verification failed"
fi

log "overlay applied on $(git -C "$X_DIR" rev-parse --short HEAD)"
