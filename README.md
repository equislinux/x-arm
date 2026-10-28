# x-arm — X Linux for aarch64

Overlay build of X Linux for 64-bit ARM. It consumes [`equislinux/x`](../x)
pinned to a commit, applies the `overlay/` delta, and produces:

- a UEFI-only live ISO (`x-<version>-aarch64.iso`) for real hardware and VMs;
- an `[x]/aarch64` pacman repository;
- VM images for Apple Silicon (UTM/Parallels/VMware) and generic `virt` hosts.

Nothing in this directory modifies `x`, `x-repo` or `web`. The x86_64 profile
stays untouched: this is a separate tree on purpose, so an ARM change can never
be merged into `main` by accident.

## Status

This is the first working iteration. Honest parity map:

| Area | State |
|---|---|
| archiso profile (UEFI/GRUB, arm64-efi) | done |
| `packages.aarch64` against Arch Linux ARM | done |
| Build pipeline (fetch -> overlay -> repo -> ISO) | done |
| `[x]` aarch64 repo (x-release, x-wallpapers, x-dev, xfetch, xtop) | done |
| QEMU `virt` launcher and VM image export | done |
| Installer parity (`x-installer`) | patch included, needs hardware test |
| `xgen`/`xkernel` (`Image`, no `pkgbase`) | **not yet** (installer degrades gracefully) |
| Desktop (Hyprland/niri) inside a VM | works with software rendering, no 3D |
| CI | static checks only; the ISO build needs an aarch64 host |
| Secure Boot, Raspberry Pi, Asahi, ARMv7 | out of scope |

## Requirements

Build host: **aarch64 Arch Linux ARM**, root, ~15 GiB free. On a MacBook this
means an Arch Linux ARM VM in UTM (see `docs/en/build.md`).

```bash
pacman -S --needed base-devel git grub squashfs-tools libisoburn libarchive \
  dosfstools mtools erofs-utils mkinitcpio-archiso systemd-ukify \
  arch-install-scripts rsync qemu-img qemu-system-aarch64 jq gnupg
```

`archiso` is not packaged in ALARM; `scripts/fetch-archiso.sh` clones upstream
archiso, which already supports aarch64 (`grub_target=arm64-efi`,
`BOOTAA64.EFI`).

## Quick start

```bash
# 1. resolve inputs
scripts/fetch-x.sh
scripts/fetch-archiso.sh

# 2. overlay onto the pinned x checkout
scripts/apply-overlay.sh

# 3. build the [x]/aarch64 repo (normal user), then the ISO (root)
X_REPO_SIGN_KEY=... scripts/build-repo.sh --sign
sudo scripts/build-iso.sh

# 4. boot it locally (QEMU) or install into a VM disk
scripts/vm.sh --iso out/iso/x-*-aarch64.iso --disk out/vm/x-aarch64.qcow2
```

`build-iso.sh --no-repo` uses the published `[x]/aarch64` URL instead of the
local repo (only valid after a release).

## Layout

```
vendor/x.sha            pinned commit of equislinux/x
vendor/archiso.sha      pinned commit of archlinux/archiso
overlay/                the ARM-only delta
  profiledef.sh
  packages.aarch64
  pacman.aarch64.conf.in
  airootfs/             live system overrides (pacman, keyring, presets)
  grub/                 GRUB config for /boot/Image
  patches/              patches applied to vendor/x
  packages/             aarch64 build overrides for [x] packages
scripts/                fetch, overlay, build, VM, publish
vm/                     UTM/QEMU notes and bundle helpers
docs/                   es/ and en/ build docs, acceptance criteria
```

## Design rules

- `x`, `x-repo` and `web` are consumed read-only; the only writes are in
  `x-arm/out` (gitignored).
- The overlay is applied on a clean checkout every time, so builds are
  reproducible and a stale file can never leak in.
- No ISOs, `.qcow2`, `.raw` or `.utm` bundles in git; they go to SourceForge.
- x86_64 behaviour is untouched by construction.

See `docs/en/build.md` for the full flow and `docs/acceptance.md` for the exit
criteria of a release.
