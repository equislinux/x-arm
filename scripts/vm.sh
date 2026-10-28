#!/usr/bin/env bash
# vm.sh — boot the aarch64 ISO (or an installed disk) with QEMU.
#
# Works on Linux aarch64 (KVM), macOS arm64 (HVF) and, slowly, anywhere else
# (TCG). For UTM/Parallels/VMware use the .qcow2 produced by build-vm.sh.
#
# Usage: scripts/vm.sh [options]
#
#   --iso PATH        ISO to boot (default: newest out/iso/*-aarch64.iso)
#   --disk PATH       qcow2 disk (default: out/vm/x-aarch64.qcow2; created 40G)
#   --boot iso|disk   Boot the ISO (default when --iso exists) or the disk
#   --size SIZE       disk size when creating it (default 40G)
#   --firmware PATH   UEFI firmware (auto-detected)
#   --vars PATH       writable UEFI vars (default: <disk>.vars)
#   --ram MB          guest RAM (default 4096)
#   --cpus N          guest vCPUs (default 4)
#   --no-accel        force TCG
#   --gui             virtio-gpu + graphical display (default: serial)
#   --ssh-port PORT   forward host PORT -> guest 22
#   --seed-json FILE  attach a cidata seed disk with x-install.json
#   --print           print the qemu command and exit
set -Eeuo pipefail
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SELF_DIR/common.sh"

ISO=""
DISK="$OUT/vm/x-$ARCH.qcow2"
BOOT=""
SIZE="40G"
FW=""
VARS=""
RAM=4096
CPUS=4
ACCEL="auto"
GUI=0
SSH_PORT=""
SEED_JSON=""
PRINT=0

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)      ISO="${2:?--iso needs a path}"; shift 2 ;;
        --disk)     DISK="${2:?--disk needs a path}"; shift 2 ;;
        --boot)     BOOT="${2:?--boot needs iso|disk}"; shift 2 ;;
        --size)     SIZE="${2:?--size needs a value}"; shift 2 ;;
        --firmware) FW="${2:?--firmware needs a path}"; shift 2 ;;
        --vars)     VARS="${2:?--vars needs a path}"; shift 2 ;;
        --ram)      RAM="${2:?--ram needs a number}"; shift 2 ;;
        --cpus)     CPUS="${2:?--cpus needs a number}"; shift 2 ;;
        --no-accel) ACCEL="tcg"; shift ;;
        --gui)      GUI=1; shift ;;
        --ssh-port) SSH_PORT="${2:?--ssh-port needs a port}"; shift 2 ;;
        --seed-json) SEED_JSON="${2:?--seed-json needs a path}"; shift 2 ;;
        --print)    PRINT=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

need_cmd qemu-system-aarch64 qemu-img

if [[ -z "$BOOT" ]]; then
    if [[ -n "$ISO" ]] || compgen -G "$OUT/iso/x-*-$ARCH.iso" >/dev/null; then
        BOOT="iso"
    else
        BOOT="disk"
    fi
fi
case "$BOOT" in iso|disk) ;; *) die "--boot must be iso or disk" ;; esac

if [[ "$BOOT" == "iso" ]]; then
    ISO="$(resolve_iso "$ISO")"
fi

if [[ ! -f "$DISK" ]]; then
    mkdir -p "$(dirname -- "$DISK")"
    log "creating $DISK ($SIZE)"
    qemu-img create -q -f qcow2 "$DISK" "$SIZE"
fi

find_firmware() {
    local c
    for c in \
        /usr/share/edk2/aarch64/QEMU_EFI.fd \
        /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw \
        /usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd \
        /usr/share/edk2/aarch64/QEMU_CODE.fd \
        /usr/share/qemu/edk2-aarch64-code.fd \
        /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        /usr/local/share/qemu/edk2-aarch64-code.fd \
        /usr/share/AAVMF/AAVMF_CODE.fd; do
        [[ -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
        done
    return 1
}

if [[ -z "$FW" ]]; then
    FW="$(find_firmware || true)"
fi
[[ -n "$FW" ]] || die "no UEFI firmware found; install edk2-aarch64/edk2-armvirt or pass --firmware"

firmware_args=()
case "$FW" in
    *code.fd|*CODE.fd)
        [[ -n "$VARS" ]] || VARS="$DISK.vars"
        if [[ ! -f "$VARS" ]]; then
            log "creating UEFI vars: $VARS"
            truncate -s 64M "$VARS"
        fi
        firmware_args=(-drive "if=pflash,format=raw,readonly=on,file=$FW"
                       -drive "if=pflash,format=raw,file=$VARS")
        ;;
    *)
        firmware_args=(-bios "$FW")
        ;;
esac

if [[ "$ACCEL" == "auto" ]]; then
    case "$(uname -s)-$(uname -m)" in
        Linux-aarch64|Linux-arm64)
            if [[ -w /dev/kvm ]]; then ACCEL=kvm; CPU="host"; else ACCEL=tcg; CPU="max"; fi
            ;;
        Darwin-arm64)
            ACCEL=hvf; CPU="host"
            ;;
        *)
            ACCEL=tcg; CPU="max"
            ;;
    esac
fi
if [[ "$ACCEL" == "tcg" ]]; then
    CPU="max"
else
    CPU="${CPU:-host}"
fi

netdev="user,id=n0"
if [[ -n "$SSH_PORT" ]]; then
    netdev="$netdev,hostfwd=tcp::$SSH_PORT-:22"
fi

args=(
    -M 'virt,highmem=on'
    -accel "$ACCEL"
    -cpu "$CPU"
    -smp "$CPUS"
    -m "$RAM"
    -rtc base=utc
    "${firmware_args[@]}"
    -drive "if=none,id=disk,file=$DISK,format=qcow2"
    -device 'virtio-blk-pci,drive=disk'
    -netdev "$netdev"
    -device 'virtio-net-pci,netdev=n0'
    -device virtio-rng-pci
    -device virtio-balloon-pci
)

if [[ "$BOOT" == "iso" ]]; then
    args+=(
        -drive "if=none,id=cdrom,media=cdrom,readonly=on,file=$ISO"
        -device virtio-scsi-pci
        -device 'scsi-cd,drive=cdrom'
    )
fi

if [[ -n "$SEED_JSON" ]]; then
    [[ -f "$SEED_JSON" ]] || die "seed JSON not found: $SEED_JSON"
    need_cmd mkfs.vfat mcopy
    seed_img="$OUT/vm/$(basename -- "$DISK").cidata.img"
    mkdir -p "$OUT/vm"
    rm -f -- "$seed_img"
    truncate -s 4M "$seed_img"
    mkfs.vfat -n cidata "$seed_img" >/dev/null
    mcopy -i "$seed_img" "$SEED_JSON" ::/x-install.json
    log "seed: $seed_img (boot the 'autoinstall' GRUB entry)"
    args+=(
        -drive "if=none,id=seed,file=$seed_img,format=raw"
        -device 'virtio-blk-pci,drive=seed'
    )
fi

if [[ "$GUI" -eq 1 ]]; then
    args+=(-device virtio-gpu-pci -display "${QEMU_DISPLAY:-default}")
else
    args+=(-nographic)
fi

log "boot=$BOOT accel=$ACCEL cpu=$CPU disk=$DISK"
[[ "$BOOT" == "iso" ]] && log "iso=$ISO"

if [[ "$PRINT" -eq 1 ]]; then
    printf 'qemu-system-aarch64'
    printf ' %q' "${args[@]}"
    printf '\n'
    exit 0
fi

exec qemu-system-aarch64 "${args[@]}"
