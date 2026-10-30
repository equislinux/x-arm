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
[[ -d "$ARCHISO_DIR/.git" ]] || die "vendor/archiso is missing; run scripts/fetch-archiso.sh first"

log "resetting vendor/x to the pinned commit"
git -C "$X_DIR" reset --hard -q HEAD
git -C "$X_DIR" clean -fdq

log "resetting vendor/archiso to the pinned commit"
git -C "$ARCHISO_DIR" reset --hard -q HEAD
git -C "$ARCHISO_DIR" clean -fdq

log "copying overlay"
tar -C "$ROOT/overlay" \
    --exclude=patches --exclude=packages --exclude='*.patch' \
    -cf - . | tar -C "$X_DIR" -xf -

log "applying installer patch"
patch --batch --forward --silent -p1 -d "$X_DIR" \
    -i "$ROOT/overlay/patches/x-installer-aarch64.patch"

log "applying mkarchiso patch"
patch --batch --forward --silent -p1 -d "$ARCHISO_DIR" \
    -i "$ROOT/overlay/patches/mkarchiso-aarch64.patch"

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
check "installer injects the GRUB initrd on aarch64" \
    "grep -q 'initrd.*initramfs-linux.img' \"\$X_DIR/airootfs/root/x-installer/install.sh\""
check "installer keeps a single aarch64 kernel in pacstrap" \
    "grep -q 'grep -vE .*linux-aarch64' \"\$X_DIR/airootfs/root/x-installer/install.sh\""
check "installer has no x86_64-efi" \
    "! grep -q 'x86_64-efi' \"\$X_DIR/airootfs/root/x-installer/install.sh\""
check "grub config uses /Image" \
    "grep -q 'boot/%ARCH%/Image' \"\$X_DIR/grub/grub.cfg\""
check "choose-mirror uses the ALARM layout" \
    "grep -q '\\\$arch/\\\$repo' \"\$X_DIR/airootfs/usr/local/bin/choose-mirror\""
check "mkarchiso handles /boot/Image on aarch64" \
    "grep -q 'boot_dir}/Image' \"\$ARCHISO_DIR/archiso/mkarchiso\""
check "mirrorlist only lists resolvable ALARM mirrors" \
    "[[ \"\$(grep -c '^Server = ' \"\$X_DIR/airootfs/etc/pacman.d/mirrorlist\")\" -eq 2 ]] && grep -q '^Server = http://de.mirror.archlinuxarm.org/' \"\$X_DIR/airootfs/etc/pacman.d/mirrorlist\" && grep -q '^Server = http://mirror.archlinuxarm.org/' \"\$X_DIR/airootfs/etc/pacman.d/mirrorlist\""
check "live pacman.conf disables the download timeout" \
    "grep -qx 'DisableDownloadTimeout' \"\$X_DIR/airootfs/etc/pacman.conf\""
check "ARM desktop wrapper is installed and executable" \
    "[[ -x \"\$X_DIR/airootfs/usr/local/bin/x-hyprland-arm\" ]]"
check "profile grants exec permissions to the ARM desktop wrapper" \
    "grep -q 'x-hyprland-arm.*0:0:755' \"\$X_DIR/profiledef.sh\""
check "installer invokes the ARM desktop wrapper" \
    "grep -q 'env \$HYPR_ENV /usr/local/bin/x-hyprland-arm' \"\$X_DIR/airootfs/root/x-installer/install.sh\""
check "installer copies the ARM desktop wrapper into the target" \
    "grep -q 'install -Dm755 /usr/local/bin/x-hyprland-arm \"\$MNT/usr/local/bin/x-hyprland-arm\"' \"\$X_DIR/airootfs/root/x-installer/install.sh\""

for f in "$X_DIR"/airootfs/root/x-installer/*.sh; do
    bash -n "$f" || { warn "syntax error: $f"; fail=1; }
done
bash -n "$X_DIR/airootfs/usr/local/bin/x-hyprland-arm" \
    || { warn "syntax error: x-hyprland-arm"; fail=1; }

if [[ "$CHECK" -eq 1 ]]; then
    if [[ "$fail" -ne 0 ]]; then
        die "overlay verification failed"
    fi
else
    [[ "$fail" -eq 0 ]] || die "overlay verification failed"
fi

log "overlay applied on $(git -C "$X_DIR" rev-parse --short HEAD)"
