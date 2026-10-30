#!/usr/bin/env bash
# run.sh — run a command inside the xlinux-arm-builder container with the
# equislinux workspace mounted at /workspace (x-arm is /workspace/x-arm,
# x-repo is /workspace/x-repo). Runs as the workspace owner; use sudo inside
# for the steps that need root (build-iso.sh).
#
# Signing material is mounted read-only into the container when present:
#   GNUPGHOME:  X_ARM_GNUPGHOME or ~/.config/equislinux/keys/gnupg  -> /keys/gnupg
#   SSH keys:   ~/.ssh                                              -> /keys/ssh
# Both are copied into /home/builder by the entrypoint (see docker/README.md).
#
# Usage:
#   docker/run.sh scripts/fetch-x.sh
#   docker/run.sh scripts/build-repo.sh
#   X_REPO_SIGN_KEY=<fpr> docker/run.sh scripts/build-repo.sh --sign
#   docker/run.sh scripts/publish-arm.sh --dry-run
#   docker/run.sh sudo scripts/build-iso.sh
#   docker/run.sh bash            # interactive shell
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd -- "$SELF_DIR/../.." && pwd)"
IMAGE="${X_ARM_DOCKER_IMAGE:-xlinux-arm-builder:latest}"

MOUNTS=(-v "$WORKSPACE:/workspace")

GNUPGHOME_HOST="${X_ARM_GNUPGHOME:-$HOME/.config/equislinux/keys/gnupg}"
if [[ -d "$GNUPGHOME_HOST" ]]; then
    MOUNTS+=(-v "$GNUPGHOME_HOST:/keys/gnupg:ro")
fi
if [[ -d "$HOME/.ssh" ]]; then
    MOUNTS+=(-v "$HOME/.ssh:/keys/ssh:ro")
fi

TTY=""
if [[ -t 0 && -t 1 ]]; then TTY="-it"; fi

exec docker run --rm $TTY --privileged \
    "${MOUNTS[@]}" \
    -w /workspace/x-arm \
    -e LANG=C -e LC_ALL=C \
    -e X_REPO_SIGN_KEY="${X_REPO_SIGN_KEY:-}" \
    -e X_ISO_DATE="${X_ISO_DATE:-}" \
    "$IMAGE" "$@"
