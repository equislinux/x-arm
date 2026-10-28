#!/usr/bin/env bash
# fetch-archiso.sh — clone upstream archiso at the pinned commit.
#
# archiso is not packaged in Arch Linux ARM. Upstream already supports aarch64
# (grub_target=arm64-efi, BOOTAA64.EFI), so the build uses it from source.
#
# Usage: scripts/fetch-archiso.sh [--sha SHA] [--remote URL]
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

SHA=""
REMOTE="$ARCHISO_SRC_URL"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sha)    SHA="${2:?--sha needs a value}"; shift 2 ;;
        --remote) REMOTE="${2:?--remote needs a URL}"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_cmds_build

if [[ -z "$SHA" ]]; then
    SHA="$(pin_value "$ROOT/vendor/archiso.sha" || true)"
    [[ -n "$SHA" ]] || die "no --sha and no vendor/archiso.sha pin"
fi

git_clone_pinned "$REMOTE" "$ARCHISO_DIR" "$SHA"

MKARCHISO="$ARCHISO_DIR/archiso/mkarchiso"
[[ -x "$MKARCHISO" ]] || die "archiso checkout is missing archiso/mkarchiso"
if ! grep -q "aarch64.*AA64" "$ARCHISO_DIR/archiso/mkarchiso"; then
    die "pinned archiso does not know about aarch64 (AA64); update vendor/archiso.sha"
fi

resolved="$(git -C "$ARCHISO_DIR" rev-parse HEAD)"
log "archiso: $resolved"
