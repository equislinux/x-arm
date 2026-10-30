#!/bin/bash
# entrypoint.sh — remap the container user to the /workspace owner and run the
# requested command as that user. Pass "root" as the first argument to stay
# root (for sudo-required steps it is still better to let the user sudo).
#
# Signing material mounted read-only at /keys/{gnupg,ssh} is copied into the
# builder home first (works around virtiofs socket limits for gpg-agent).
set -e

if [[ -d /keys/gnupg ]]; then
    rm -rf /home/builder/.gnupg
    cp -a /keys/gnupg /home/builder/.gnupg
    chmod 700 /home/builder/.gnupg
    find /home/builder/.gnupg -type f -exec chmod 600 {} + 2>/dev/null || true
fi
if [[ -d /keys/ssh ]]; then
    rm -rf /home/builder/.ssh
    mkdir -p /home/builder/.ssh
    find /keys/ssh -maxdepth 1 -type f -exec cp -p {} /home/builder/.ssh/ \;
    chmod 700 /home/builder/.ssh
    chmod 600 /home/builder/.ssh/* 2>/dev/null || true
fi

ws_uid="$(stat -c %u /workspace 2>/dev/null || echo 0)"
ws_gid="$(stat -c %g /workspace 2>/dev/null || echo 0)"
if [[ "$ws_uid" -ne 0 ]] && id builder >/dev/null 2>&1; then
    usermod -u "$ws_uid" builder 2>/dev/null || true
    groupmod -g "$ws_gid" builder 2>/dev/null || true
fi
# Always align /home/builder ownership: on macOS the /workspace mount is
# root-owned (VirtioFS), so ws_uid is 0 and the remap above is skipped.
chown -R builder:builder /home/builder 2>/dev/null || true

if [[ "$(id -u)" -eq 0 && "${1:-}" != "root" ]]; then
    exec runuser -u builder -- "$@"
fi
shift 2>/dev/null || true
exec "$@"
