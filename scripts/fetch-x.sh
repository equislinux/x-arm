#!/usr/bin/env bash
# fetch-x.sh — clone equislinux/x at the pinned commit into vendor/x.
#
# Usage:
#   scripts/fetch-x.sh [--sha SHA] [--src PATH] [--remote URL]
#
# Defaults: vendor/x.sha (if present) and https://github.com/equislinux/x.git.
# --src clones a local checkout (works with commits not pushed yet).
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

SHA=""
SRC=""
REMOTE="$X_SRC_URL"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sha)    SHA="${2:?--sha needs a value}"; shift 2 ;;
        --src)    SRC="${2:?--src needs a path}"; shift 2 ;;
        --remote) REMOTE="${2:?--remote needs a URL}"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_cmds_build

if [[ -z "$SHA" ]]; then
    SHA="$(pin_value "$ROOT/vendor/x.sha" || true)"
    [[ -n "$SHA" ]] || die "no --sha and no vendor/x.sha pin"
fi

if [[ -n "$SRC" ]]; then
    [[ -d "$SRC/.git" ]] || die "--src is not a git checkout: $SRC"
    SHA="$(git -C "$SRC" rev-parse --verify "${SHA}^{commit}")"
    git_clone_local_pinned "$SRC" "$X_DIR" "$SHA"
else
    git_clone_pinned "$REMOTE" "$X_DIR" "$SHA"
fi

resolved="$(git -C "$X_DIR" rev-parse HEAD)"
subject="$(git -C "$X_DIR" log -1 --format=%s)"
mkdir -p "$VENDOR"
printf '%s\n' "$resolved" >"$VENDOR/.x-resolved"
log "x: $resolved ($subject)"
