#!/usr/bin/env bash
# Shared helpers for x-arm scripts. Source it, do not execute it.
# shellcheck shell=bash
# shellcheck disable=SC2034

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
X_DIR="$VENDOR/x"
ARCHISO_DIR="$VENDOR/archiso"
OUT="$ROOT/out"
ARCH="aarch64"
# The [x]/aarch64 repository is published from the dedicated
# equislinux/x-arm-repo repo (GitHub Pages), mirroring x-repo for x86_64.
X_REPO_URL="${X_ARM_X_REPO_URL:-https://equislinux.github.io/x-arm-repo/repo/$ARCH}"

x_repo_url() { printf '%s\n' "$X_REPO_URL"; }
X_SRC_URL="${X_ARM_X_SRC_URL:-https://github.com/equislinux/x.git}"
ARCHISO_SRC_URL="${X_ARM_ARCHISO_SRC_URL:-https://github.com/archlinux/archiso.git}"

if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_OFF=$'\033[0m'
else
    C_BLUE="" C_YELLOW="" C_RED="" C_OFF=""
fi

log()  { printf '%s::%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
warn() { printf '%s !%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%sxx%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

need_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "missing command: $c"
    done
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "run as root (needed for pacstrap/mount/mkarchiso)"
}

require_aarch64() {
    local machine
    machine="$(uname -m)"
    if [[ "$machine" != "aarch64" && "$machine" != "arm64" ]]; then
        if [[ "${X_ARM_ALLOW_CROSS:-0}" == "1" ]]; then
            warn "host is $machine, not aarch64; cross-building is unsupported"
        else
            die "host is $machine; build on aarch64 (or set X_ARM_ALLOW_CROSS=1 to try)"
        fi
    fi
}

require_cmds_build() {
    need_cmd git tar gzip sha256sum
}

require_cmds_iso() {
    need_cmd git tar gzip sha256sum xorriso bsdtar mksquashfs
    need_cmd mkinitcpio pacstrap
}

# git_clone_pinned <url|path> <dest> <sha-or-ref>
git_clone_pinned() {
    local src="$1" dest="$2" ref="$3"
    rm -rf -- "$dest"
    log "cloning $src at $ref -> $dest"
    git clone -q --filter=blob:none --no-checkout "$src" "$dest"
    git -C "$dest" checkout -q --detach "$ref"
}

# git_clone_local_pinned <path> <dest> <sha>
git_clone_local_pinned() {
    local src="$1" dest="$2" ref="$3"
    rm -rf -- "$dest"
    log "cloning local $src at $ref -> $dest"
    git clone -q --no-local --no-checkout "$src" "$dest"
    git -C "$dest" checkout -q --detach "$ref"
}

pin_value() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$file" | head -n1
}

resolve_iso() {
    local iso="${1:-}"
    if [[ -z "$iso" ]]; then
        iso="$(find "$OUT/iso" -maxdepth 1 -type f -name "x-*-$ARCH.iso" \
            -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
    fi
    [[ -n "$iso" && -f "$iso" ]] || die "no ISO found (pass --iso or build one first)"
    printf '%s\n' "$iso"
}

iso_version() {
    local iso="$1" name
    name="$(basename -- "$iso")"
    sed -n "s/^x-\\([0-9.]*\\)-${ARCH}\\.iso$/\\1/p" <<<"$name"
}
