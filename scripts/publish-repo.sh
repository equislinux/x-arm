#!/usr/bin/env bash
# publish-repo.sh — publish out/repo/aarch64 to equislinux/x-arm-repo.
#
# The [x]/aarch64 repository is served from https://equislinux.github.io/
# x-arm-repo/repo/aarch64 (GitHub Pages, main branch); x-repo keeps serving
# x86_64 only (ops/docs/x-arm/plan.md).
#
# Usage:
#   scripts/publish-repo.sh           # stage into ../x-arm-repo, no push
#   scripts/publish-repo.sh --push    # ... commit and push main
#
# Requires a signed repo first: X_REPO_SIGN_KEY=... scripts/build-repo.sh --sign
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

PUSH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push) PUSH=1; shift ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

SRC="$OUT/repo/$ARCH"
[[ -f "$SRC/x.db.tar.gz" ]] || die "no repo at $SRC; run scripts/build-repo.sh first"
need_cmd git

# Run from the host (not the container): pushing needs the host's git
# credentials. The x-arm-repo checkout is a workspace sibling.
X_ARM_REPO_DIR="${X_ARM_REPO_DIR:-$ROOT/../x-arm-repo}"
[[ -d "$X_ARM_REPO_DIR/.git" ]] || die "x-arm-repo checkout not found at $X_ARM_REPO_DIR"
[[ -z "$(git -C "$X_ARM_REPO_DIR" status --porcelain 2>/dev/null)" ]] \
    || warn "x-arm-repo has uncommitted changes; publishing anyway"

log "staging $SRC -> $X_ARM_REPO_DIR/repo/$ARCH"
mkdir -p "$X_ARM_REPO_DIR/repo/$ARCH"
rsync -a --delete "$SRC"/ "$X_ARM_REPO_DIR/repo/$ARCH/"

if [[ ! -f "$X_ARM_REPO_DIR/index.html" ]]; then
    cat >"$X_ARM_REPO_DIR/index.html" <<EOF
<!doctype html><meta charset="utf-8"><title>X Linux — [x]/aarch64</title>
<h1>X Linux aarch64 repository</h1>
<p>Pacman repository for X Linux on aarch64.</p>
<pre><code>[x]
SigLevel = Required
Server = https://equislinux.github.io/x-arm-repo/repo/aarch64
</code></pre>
<p>Packages: <a href="repo/aarch64/">repo/aarch64/</a></p>
EOF
fi

git -C "$X_ARM_REPO_DIR" add -A
if [[ "$PUSH" -eq 1 ]]; then
    GIT_ID=(-c "user.name=${GIT_USER_NAME:-xscriptor}" -c "user.email=${GIT_USER_EMAIL:-preciado.oscar.osorio@gmail.com}")
    git -C "$X_ARM_REPO_DIR" "${GIT_ID[@]}" commit -q -m "repo: publish [x]/$ARCH ($(date +%Y.%m.%d))" || true
    git -C "$X_ARM_REPO_DIR" push -q origin main
    log "pushed x-arm-repo main"
    log "repo: https://equislinux.github.io/x-arm-repo/repo/$ARCH"
else
    log "staged in $X_ARM_REPO_DIR (no push)"
    log "review with: git -C $X_ARM_REPO_DIR diff --cached --stat"
    log "then re-run with --push"
fi
