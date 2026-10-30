#!/usr/bin/env bash
# build-image.sh — import the pinned Arch Linux ARM rootfs into Docker and
# build the xlinux-arm-builder image.
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="$SELF_DIR/rootfs/ArchLinuxARM-aarch64-latest.tar.gz"
PIN_FILE="$SELF_DIR/rootfs.sha"
IMAGE_ROOTFS="xlinux-alarm-rootfs:latest"
IMAGE_BUILDER="${X_ARM_DOCKER_IMAGE:-xlinux-arm-builder:latest}"

[[ -f "$TARBALL" ]] || {
    echo "missing $TARBALL; run docker/fetch-rootfs.sh first" >&2
    exit 1
}

actual="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
pinned="$(grep -v '^#' "$PIN_FILE" | head -n1 | tr -d '[:space:]')"
[[ "$actual" == "$pinned" ]] || {
    echo "rootfs sha256 mismatch: got $actual, pinned $pinned" >&2
    exit 1
}

if ! docker image inspect "$IMAGE_ROOTFS" >/dev/null 2>&1; then
    echo "importing rootfs -> $IMAGE_ROOTFS"
    docker import "$TARBALL" "$IMAGE_ROOTFS"
fi

docker build -t "$IMAGE_BUILDER" "$SELF_DIR"
echo "builder ready: $IMAGE_BUILDER"
