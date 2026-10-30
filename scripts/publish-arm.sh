#!/usr/bin/env bash
# publish-arm.sh — publish an aarch64 ISO to SourceForge and update the web index.
#
# It writes data/releases-arm.json (separate from the x86_64 releases.json so the
# x86 "latest" redirect never points at an ARM image).
#
# Usage:
#   scripts/publish-arm.sh [--iso PATH] [--dry-run] [--no-upload] [--verify]
#                          [--keep] [--web-dir DIR]
#
# Env:
#   X_REPO_SIGN_KEY   gpg key (required unless --dry-run)
#   SF_USER           SourceForge account         (default: xscriptor)
#   SF_KEY            SSH key for SourceForge     (default: ~/.ssh/id_ed25519_sourceforge)
#   SF_PATH           remote directory            (default: /home/frs/project/equislinux/arm/iso)
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

ISO=""
DRY_RUN=0
UPLOAD=1
VERIFY=0
KEEP=0
WEB_DIR="${X_ARM_WEB_DIR:-$ROOT/../web}"
SF_USER="${SF_USER:-xscriptor}"
SF_KEY="${SF_KEY:-$HOME/.ssh/id_ed25519_sourceforge}"
SF_PATH="${SF_PATH:-/home/frs/project/equislinux/arm/iso}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)       ISO="${2:?--iso needs a path}"; shift 2 ;;
        --dry-run)   DRY_RUN=1; UPLOAD=0; shift ;;
        --no-upload) UPLOAD=0; shift ;;
        --verify)    VERIFY=1; shift ;;
        --keep)      KEEP=1; shift ;;
        --web-dir)   WEB_DIR="${2:?--web-dir needs a path}"; shift 2 ;;
        -h|--help)   sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

need_cmd sha256sum gpg jq rsync sftp ssh
[[ "$DRY_RUN" -eq 1 || -n "${X_REPO_SIGN_KEY:-}" ]] \
    || die "X_REPO_SIGN_KEY is unset (export it or use --dry-run)"
[[ -f "$SF_KEY" || "$UPLOAD" -eq 0 ]] || die "SourceForge SSH key not found: $SF_KEY"

ISO="$(resolve_iso "$ISO")"
NAME="$(basename -- "$ISO")"
VERSION="$(iso_version "$ISO")"
[[ -n "$VERSION" ]] || die "cannot derive the version from $NAME"
DATE="${X_ISO_DATE:-$(date +%Y-%m-%d)}"

log "ISO:     $ISO"
log "version: $VERSION ($ARCH)"

STAGE="$(mktemp -d)"
trap 'rm -rf -- "$STAGE"' EXIT

SHA="$(sha256sum "$ISO" | awk '{print $1}')"
printf '%s  %s\n' "$SHA" "$NAME" >"$STAGE/SHA256SUMS"
log "sha256:  $SHA"

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run: would sign with ${X_REPO_SIGN_KEY:-<unset>}"
else
    gpg --batch --yes --detach-sign -o "$STAGE/$NAME.sig" --local-user "$X_REPO_SIGN_KEY" "$ISO"
    gpg --batch --yes --detach-sign -o "$STAGE/SHA256SUMS.sig" --local-user "$X_REPO_SIGN_KEY" "$STAGE/SHA256SUMS"
    gpg --verify "$STAGE/SHA256SUMS.sig" "$STAGE/SHA256SUMS" >/dev/null 2>&1 \
        || die "SHA256SUMS signature failed"
fi

cat >"$STAGE/README.md" <<EOF
# X Linux $VERSION for aarch64

- ISO: \`$NAME\`
- SHA-256: \`$SHA\`
- Published: $DATE
- Architecture: aarch64 (UEFI only)

Verify:

\`\`\`sh
sha256sum -c SHA256SUMS
gpg --verify SHA256SUMS.sig SHA256SUMS
\`\`\`

Boot on real hardware or import the published .qcow2 in UTM/Parallels/VMware.
There is no virtual 3D acceleration: Hyprland/niri run with software rendering.
EOF

RSH=(ssh -i "$SF_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

# Create the remote directory tree if missing (sftp mkdir is one level at a time).
if [[ "$UPLOAD" -eq 1 ]]; then
    path="$SF_PATH"
    dirs=()
    while [[ "$path" != "/home/frs/project/"* && "$path" != "/" ]]; do
        dirs+=("$path")
        path="$(dirname -- "$path")"
    done
    batch=""
    for ((i=${#dirs[@]}-1; i>=0; i--)); do
        batch+="mkdir ${dirs[$i]}"$'\n'
    done
    if [[ -n "$batch" ]]; then
        printf '%s' "$batch" | timeout 60 sftp -b - -i "$SF_KEY" -o BatchMode=yes \
            -o StrictHostKeyChecking=accept-new "$SF_USER@frs.sourceforge.net" >/dev/null 2>&1 || true
    fi
fi

if [[ "$UPLOAD" -eq 0 ]]; then
    log "no upload: skipping $SF_USER@frs.sourceforge.net:$SF_PATH"
else
    log "uploading ISO (this can take a while)"
    rsync -e "${RSH[*]}" -h --partial --info=progress2 \
        "$ISO" "$SF_USER@frs.sourceforge.net:$SF_PATH/"
    rsync -e "${RSH[*]}" -h \
        "$STAGE/README.md" "$STAGE/SHA256SUMS" "$STAGE/SHA256SUMS.sig" "$STAGE/$NAME.sig" \
        "$SF_USER@frs.sourceforge.net:$SF_PATH/"

    if [[ "$KEEP" -eq 0 ]]; then
        log "pruning previous aarch64 ISOs"
        listing="$(timeout 30 sftp -b - -i "$SF_KEY" -o BatchMode=yes "$SF_USER@frs.sourceforge.net" 2>/dev/null <<LIST
ls -1 $SF_PATH/
LIST
)"
        batch=""
        while IFS= read -r f; do
            f="$(basename -- "$f")"
            case "$f" in
                "$NAME"|"$NAME.sig") continue ;;
                x-*-aarch64.iso|x-*-aarch64.iso.sig) batch+="rm $SF_PATH/$f"$'\n' ;;
            esac
        done < <(awk '{print $NF}' <<<"$listing" | tr -d '\r')
        if [[ -n "$batch" ]]; then
            printf '%s' "$batch" | timeout 60 sftp -b - -i "$SF_KEY" -o BatchMode=yes \
                "$SF_USER@frs.sourceforge.net" >/dev/null 2>&1 || true
        fi
    fi
fi

BASE="https://sourceforge.net/projects/equislinux/files/arm/iso"
RELEASES="$WEB_DIR/data/releases-arm.json"
if [[ ! -f "$RELEASES" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "dry-run: would create $RELEASES"
    else
        mkdir -p "$(dirname -- "$RELEASES")"
        printf '{"schema":1,"arch":"aarch64","releases":[]}\n' >"$RELEASES"
    fi
fi

if [[ -f "$RELEASES" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "dry-run: would upsert $VERSION into $RELEASES"
    else
        jq --arg v "$VERSION" --arg d "$DATE" --arg n "$NAME" \
           --arg url "$BASE/$NAME/download" --arg sig "$BASE/$NAME.sig/download" \
           --arg sums "$BASE/SHA256SUMS/download" --arg sha "$SHA" \
           --argjson size "$(stat -c %s "$ISO")" --arg arch "$ARCH" \
           'def entry: {version:$v,date:$d,arch:$arch,iso:{name:$n,url:$url,size:$size,sha256:$sha,sig:$sig,checksums:$sums}};
            .arch = $arch |
            if any(.releases[]; .version == $v)
              then .releases |= map(select(.version == $v) = entry)
              else .releases = [entry] + .releases
            end' \
           "$RELEASES" >"$RELEASES.tmp" && mv "$RELEASES.tmp" "$RELEASES"
        log "updated $RELEASES"
    fi
fi

if [[ "$VERIFY" -eq 1 && "$DRY_RUN" -ne 1 && "$UPLOAD" -eq 1 ]]; then
    URL="$BASE/$NAME/download"
    log "waiting for SourceForge to publish $URL"
    ready=0
    for _ in $(seq 1 40); do
        info="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -I "$URL" || true)"
        code="${info%% *}"
        target="${info#* }"
        if [[ "$code" == "302" && "$target" == *downloads.sourceforge.net* ]]; then
            ready=1
            break
        fi
        sleep 30
    done
    [[ "$ready" -eq 1 ]] || die "download not released yet ($code -> $target)"
    tmp="$(mktemp)"
    curl -fsSL -o "$tmp" "$URL"
    [[ "$(sha256sum "$tmp" | awk '{print $1}')" == "$SHA" ]] || die "downloaded hash mismatch"
    rm -f "$tmp"
    log "public download verified: $SHA"
fi

log "done"
cat <<EOF

Next steps:
  1. commit & push the web repo:
       git -C $WEB_DIR add data/releases-arm.json
       git -C $WEB_DIR commit -m "release: $VERSION (aarch64)"
       git -C $WEB_DIR push
  2. stable link: https://equislinux.github.io/web/download/arm/
EOF
