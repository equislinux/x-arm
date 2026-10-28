# VM images on ARM (Apple Silicon, QEMU)

The VM layer is intentionally thin: the aarch64 ISO is a normal UEFI image, and
a VM is just that ISO (or an installed disk) with virtio devices.

## What the scripts produce

| File | Use |
|---|---|
| `x-<version>-aarch64.iso` | live/installer; boot in any aarch64 VM |
| `x-<version>-aarch64.qcow2` | QEMU, UTM (QEMU backend), libvirt |
| `x-<version>-aarch64.raw` | Apple Virtualization.framework (UTM "Virtualize", Parallels, VMware) |

`build-vm.sh --export` writes all three plus a `.sha256`.

## Apple Silicon (M4) specifics

- A VM on an M4 is an **aarch64 guest with UEFI + virtio**. VirtualBuddy/UTM
  (Apple backend) use Virtualization.framework; UTM (QEMU backend) uses QEMU+HVF.
- **No 3D acceleration.** `virtio-gpu` is a framebuffer only; Hyprland/niri run
  on llvmpipe. Disable blur/animations for a usable session.
- **Rosetta** (x86_64 userland inside the ARM guest) exists only with the Apple
  Virtualization backend, and needs binfmt + x86_64 libraries. It does not
  replace aarch64 packages; do not enable it by default.
- Shared folders use virtiofs. Clipboard/drag-and-drop is backend-dependent;
  there is no `open-vm-tools` or Parallels Tools for Arch Linux ARM.
- `edk2` firmware is not packaged in ALARM. Use the firmware that ships with
  UTM, or install `edk2-armvirt` from the AUR on the build host. On macOS,
  Homebrew's QEMU ships `edk2-aarch64-code.fd`.

## UTM import

1. `File > New > Virtualize` (fast, Apple backend) or `Emulate` (QEMU backend).
2. Operating System: Linux. Architecture: aarch64.
3. Memory: 4096 MiB or more. CPU: 4 or more.
4. Storage: delete the default drive and attach `x-<version>-aarch64.qcow2`
   (QEMU backend) or `.raw` (Apple backend).
5. Disable 3D acceleration if offered. Boot.

For an install from scratch, create an empty disk instead, attach the ISO as a
CD-ROM, and install. The installer writes a UEFI GRUB (`arm64-efi`) or
systemd-boot (`BOOTAA64.EFI`) system.

Unattended install: `scripts/vm.sh --seed-json x-install.json --iso ...` attaches
a FAT volume labelled `cidata` with the JSON; pick the "autoinstall" GRUB entry
(it passes `xauto=1 console=ttyAMA0`).

## QEMU (Linux aarch64 or macOS arm64)

```bash
scripts/vm.sh --iso out/iso/x-*-aarch64.iso --disk out/vm/x-aarch64.qcow2
scripts/vm.sh --boot disk                 # installed system, serial console
scripts/vm.sh --boot disk --gui           # virtio-gpu window
scripts/vm.sh --print                     # show the resolved command
```

Acceleration is picked automatically: KVM on Linux aarch64, HVF on macOS arm64,
TCG elsewhere. TCG is usable for the installer but too slow for a desktop.

## Known limitations

- No GPU acceleration, no hardware video decode, no 3D.
- Serial console is `ttyAMA0` on `virt` (not `ttyS0`).
- Device trees are not merged into the kernel image (`stubble` is not packaged
  in ALARM); QEMU `virt` does not need them.
