#!/usr/bin/env bash
# fetch-rootfs.sh — download the Arch Linux ARM aarch64 rootfs tarball and pin
# its sha256 in docker/rootfs.sha (the file docker/build-image.sh verifies).
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
URL="${X_ARM_ROOTFS_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}"
TARBALL="$SELF_DIR/rootfs/ArchLinuxARM-aarch64-latest.tar.gz"

mkdir -p "$SELF_DIR/rootfs"
echo "fetching $URL"
curl -fsSL --retry 3 -o "$TARBALL.part" "$URL"
mv "$TARBALL.part" "$TARBALL"
shasum -a 256 "$TARBALL" | awk '{print $1}' >"$SELF_DIR/rootfs.sha"
echo "pinned: $(cat "$SELF_DIR/rootfs.sha")"
ls -lh "$TARBALL"
