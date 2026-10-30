#!/usr/bin/env bash
# build-repo.sh — build the aarch64 [x] repository (x.db) from equislinux/x-repo.
#
# Default set: x-release, x-wallpapers, x-dev, xfetch-bin, xtop-git.
# --all adds opencode-bin and x-kde-settings.
#
# Run as a normal user: makepkg refuses to run as root.
#
# Usage:
#   scripts/build-repo.sh [--all] [--sign|--no-sign] [--out DIR]
#
# Env:
#   X_REPO_DIR        equislinux/x-repo checkout (default ../x-repo)
#   X_REPO_SIGN_KEY   gpg key id/fingerprint (required with --sign)
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

ALL=0
SIGN=""
OUT_REPO="$OUT/repo/$ARCH"
X_REPO_DIR="${X_REPO_DIR:-$ROOT/../x-repo}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)     ALL=1; shift ;;
        --sign)    SIGN=1; shift ;;
        --no-sign) SIGN=0; shift ;;
        --out)     OUT_REPO="${2:?--out needs a path}"; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "${EUID}" -ne 0 ]] || die "makepkg refuses to run as root; use a normal user"
require_aarch64
[[ -d "$X_REPO_DIR/packages" ]] || die "x-repo not found at $X_REPO_DIR (set X_REPO_DIR)"
need_cmd makepkg repo-add gpg git tar sha256sum

if [[ -z "$SIGN" ]]; then
    if [[ -n "${X_REPO_SIGN_KEY:-}" ]]; then SIGN=1; else SIGN=0; fi
fi
if [[ "$SIGN" -eq 1 ]]; then
    [[ -n "${X_REPO_SIGN_KEY:-}" ]] || die "--sign needs X_REPO_SIGN_KEY in the environment"
    need_cmd gpg
fi

PACKAGES=(x-release x-wallpapers x-dev xfetch-bin xtop-git)
if [[ "$ALL" -eq 1 ]]; then
    PACKAGES+=(opencode-bin x-kde-settings)
fi

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
PKGDEST="$WORK/pkgs"
SRCDEST="${X_ARM_SRCDEST:-$WORK/src}"
mkdir -p "$PKGDEST" "$SRCDEST" "$OUT_REPO"

log "building ${#PACKAGES[@]} package(s) for $ARCH"
built=()
for pkg in "${PACKAGES[@]}"; do
    case "$pkg" in
        xfetch-bin) src="$X_REPO_DIR/packages/xfetch" ;;
        xtop-git)   src="$X_REPO_DIR/packages/xtop" ;;
        *)          src="$X_REPO_DIR/packages/$pkg" ;;
    esac
    [[ -d "$src" ]] || { warn "missing $src; skipping $pkg"; continue; }

    stage="$WORK/build/$pkg"
    mkdir -p "$WORK/build"
    cp -a "$src" "$stage"
    # Drop build artifacts accidentally committed in x-repo: stray pkg/src
    # dirs and bare git clones (e.g. packages/xtop/xtop), which make
    # makepkg abort with "is not a clone of ...".
    find "$stage" -mindepth 1 -maxdepth 1 \( -name pkg -o -name src \) -exec rm -rf -- {} +
    while IFS= read -r -d '' d; do
        [[ -f "$d/HEAD" && -d "$d/objects" ]] && rm -rf -- "$d"
    done < <(find "$stage" -mindepth 1 -maxdepth 1 -type d -print0)
    if [[ -d "$ROOT/overlay/packages/$pkg" ]]; then
        log "  $pkg (aarch64 override)"
        cp -a "$ROOT/overlay/packages/$pkg/." "$stage/"
    else
        log "  $pkg"
    fi

    case "$pkg" in
        xtop-git) need_cmd cargo ;;
    esac

    (
        cd "$stage"
        PKGDEST="$PKGDEST" SRCDEST="$SRCDEST" \
            makepkg -f --nodeps --noconfirm --nocheck --cleanbuild >/dev/null
    ) || die "makepkg failed for $pkg"

    shopt -s nullglob
    pkgs=("$PKGDEST/$pkg"-*.pkg.tar.*)
    shopt -u nullglob
    [[ "${#pkgs[@]}" -gt 0 ]] || die "no package produced for $pkg"
    built+=("${pkgs[@]}")
done

[[ "${#built[@]}" -gt 0 ]] || die "no packages were built"

log "assembling $OUT_REPO"
for p in "${built[@]}"; do
    cp -f "$p" "$OUT_REPO/"
done

for p in "${built[@]}"; do
    repo-add --quiet "$OUT_REPO/x.db.tar.gz" "$OUT_REPO/$(basename "$p")"
done

if [[ "$SIGN" -eq 1 ]]; then
    log "signing with $X_REPO_SIGN_KEY"
    (
        cd "$OUT_REPO"
        shopt -s nullglob
        for f in *.pkg.tar.* x.db.tar.gz x.files.tar.gz; do
            [[ -f "$f" ]] || continue
            rm -f "$f.sig"
            gpg --batch --yes --local-user "$X_REPO_SIGN_KEY" --detach-sign "$f"
        done
        # repo-add publishes x.db/x.files as symlinks to the tarballs.
        cp -f x.db.tar.gz.sig x.db.sig
        [[ -f x.files.tar.gz.sig ]] && cp -f x.files.tar.gz.sig x.files.sig
        gpg --batch --yes --export --armor "$X_REPO_SIGN_KEY" >signing.pub
        gpg --batch --yes --export "$X_REPO_SIGN_KEY" >trustedkeys.gpg
        files=()
        while IFS= read -r f; do files+=("$f"); done < <(
            find . -maxdepth 1 -type f ! -name 'SHA256SUMS*' ! -name '*.sig' ! -name '*.old' -printf '%P\n' | sort
        )
        sha256sum "${files[@]}" >SHA256SUMS
        gpg --batch --yes --local-user "$X_REPO_SIGN_KEY" --detach-sign SHA256SUMS
    )
fi

log "repository ready: $OUT_REPO"
ls -1 "$OUT_REPO"
