#!/usr/bin/env bash
# build-vm.sh — create, install and export an aarch64 VM image.
#
# The install step is interactive on purpose: it boots the ISO with scripts/vm.sh
# (serial console), you run the installer, then --export produces the
# deliverables. For UTM on Apple Silicon use the exported .qcow2 (QEMU backend)
# or .raw (Apple Virtualization backend).
#
# Usage: scripts/build-vm.sh {--create|--install|--export|--all} [options]
#
#   --iso PATH     ISO for --install (default: newest out/iso)
#   --disk PATH    working qcow2 (default: out/vm/x-aarch64.qcow2)
#   --name NAME    export basename (default: x-<version>-aarch64)
#   --size SIZE    disk size for --create (default 40G)
#   --force        recreate the disk even if it exists
#   --ram MB       RAM for --install (default 4096)
#   --cpus N       vCPUs for --install (default 4)
#   --gui          graphical display for --install
#   --seed-json F  unattended install seed (boot the autoinstall GRUB entry)
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

MODE=""
ISO=""
DISK="$OUT/vm/x-$ARCH.qcow2"
NAME=""
SIZE="40G"
FORCE=0
RAM=4096
CPUS=4
GUI=0
SEED_JSON=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --create|--install|--export|--all) MODE="${1#--}"; shift ;;
        --iso)   ISO="${2:?--iso needs a path}"; shift 2 ;;
        --disk)  DISK="${2:?--disk needs a path}"; shift 2 ;;
        --name)  NAME="${2:?--name needs a value}"; shift 2 ;;
        --size)  SIZE="${2:?--size needs a value}"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --ram)   RAM="${2:?--ram needs a number}"; shift 2 ;;
        --cpus)  CPUS="${2:?--cpus needs a number}"; shift 2 ;;
        --gui)   GUI=1; shift ;;
        --seed-json) SEED_JSON="${2:?--seed-json needs a path}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done
MODE="${MODE:-create}"

need_cmd qemu-img
mkdir -p "$(dirname -- "$DISK")" "$OUT/vm"

create_disk() {
    if [[ -f "$DISK" && "$FORCE" -eq 0 ]]; then
        die "$DISK exists (use --force to recreate)"
    fi
    log "creating $DISK ($SIZE)"
    qemu-img create -q -f qcow2 "$DISK" "$SIZE"
}

install_disk() {
    [[ -f "$DISK" ]] || die "no disk at $DISK; run --create first"
    ISO="$(resolve_iso "$ISO")"
    local args=(--iso "$ISO" --disk "$DISK" --boot iso --ram "$RAM" --cpus "$CPUS")
    [[ "$GUI" -eq 1 ]] && args+=(--gui)
    [[ -n "$SEED_JSON" ]] && args+=(--seed-json "$SEED_JSON")
    log "booting the installer; when it finishes, run --export"
    "$ROOT/scripts/vm.sh" "${args[@]}"
}

export_disk() {
    [[ -f "$DISK" ]] || die "no disk at $DISK"
    if [[ -z "$NAME" ]]; then
        local ver=""
        ver="$(iso_version "$(resolve_iso "$ISO")" 2>/dev/null || true)"
        NAME="x-${ver:-$(date +%Y.%m.%d)}-$ARCH"
    fi
    local base="$OUT/vm/$NAME"
    mkdir -p "$OUT/vm"

    log "exporting qcow2 (compressed): $base.qcow2"
    qemu-img convert -q -O qcow2 -c "$DISK" "$base.qcow2"

    log "exporting raw for Apple Virtualization: $base.raw"
    qemu-img convert -q -O raw -S 4k "$DISK" "$base.raw"

    (
        cd "$OUT/vm"
        sha256sum "$(basename "$base.qcow2")" "$(basename "$base.raw")" >"$(basename "$base").sha256"
    )

    log "done"
    ls -lh "$base".qcow2 "$base".raw "$base".sha256
    cat <<EOF

Import in UTM (Apple Silicon):
  1. Create a VM > Virtualize (Apple backend) or Emulate (QEMU backend).
  2. Linux, aarch64; RAM >= 4096 MiB; disk: replace with $base.qcow2 (QEMU)
     or $base.raw (Apple VZ).
  3. Disable 3D acceleration: there is no virtual GPU; use llvmpipe/software.
  4. For the Apple backend, enable Rosetta only if you need x86_64 userland.

The default install has no desktop unless you selected one; a Hyprland/niri
session runs without GPU acceleration (slow blur/animations).
EOF
}

case "$MODE" in
    create)  create_disk ;;
    install) install_disk ;;
    export)  export_disk ;;
    all)     create_disk; install_disk; export_disk ;;
    *) die "invalid mode: $MODE" ;;
esac
