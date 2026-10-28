# Building X Linux for aarch64

This repository is an **overlay build**: it checks out `equislinux/x` at a pinned
commit, applies `overlay/`, and runs archiso. The x86_64 tree is never modified.

## 1. Builder host

The ISO must be built on aarch64. On an Apple Silicon Mac, create an Arch Linux
ARM VM (UTM, "Virtualize", 8 GiB RAM, 20 GiB disk) and work inside it.

```bash
# inside the ALARM VM
pacman -Syu --needed base-devel git grub squashfs-tools libisoburn \
  dosfstools mtools erofs-utils mkinitcpio-archiso systemd-ukify \
  arch-install-scripts rsync qemu-img qemu-system-aarch64 xorriso libarchive
```

`archiso` is not packaged in ALARM. `scripts/fetch-archiso.sh` clones upstream,
which already supports aarch64 (`grub_target=arm64-efi`, `BOOTAA64.EFI`,
`kernel_params_aarch64`).

Do **not** build as root inside the VM for the repo step: `makepkg` refuses it.
Use the normal user; only `build-iso.sh` needs root.

## 2. Inputs

```bash
scripts/fetch-x.sh            # vendor/x at vendor/x.sha
scripts/fetch-archiso.sh      # vendor/archiso at vendor/archiso.sha
scripts/apply-overlay.sh      # reset + overlay + installer patch + checks
```

`apply-overlay.sh` resets `vendor/x` to its pinned commit first, so the result is
reproducible and stale files cannot leak in.

`vendor/x.sha` is the contract with x86_64: bump it deliberately when you want
new upstream changes, then re-run the overlay and the checks.

## 3. `[x]/aarch64` repository

```bash
scripts/build-repo.sh              # unsigned (local testing)
X_REPO_SIGN_KEY=... scripts/build-repo.sh --sign
```

Default packages: `x-release`, `x-wallpapers`, `x-dev`, `xfetch-bin`,
`xtop-git`. `--all` adds `opencode-bin` and `x-kde-settings`.

Overrides under `overlay/packages/` switch the x86_64-only definitions to
aarch64:

| Package | Change |
|---|---|
| `xfetch-bin` | v1.0.1 aarch64 tarball + pinned sha256 |
| `opencode-bin` | v1.19.5 `opencode-linux-arm64.tar.gz` + pinned sha256 |
| `xtop-git` | `arch=('aarch64')`; Rust source, native build |
| `x-release`, `x-wallpapers`, `x-dev`, `x-kde-settings` | `any`, unchanged |

Output: `out/repo/aarch64/` (`x.db`, packages, `SHA256SUMS`, signatures).

## 4. ISO

```bash
sudo scripts/build-iso.sh                  # uses out/repo/aarch64
sudo scripts/build-iso.sh --no-repo        # uses the published [x]/aarch64 URL
```

`build-iso.sh` renders `pacman.aarch64.conf` from the template, pointing `[x]`
at the local repo (`file://`) and the ALARM mirrors at the shipped mirrorlist.
It then runs `mkarchiso`, checks that `EFI/BOOT/BOOTAA64.EFI`,
`arch/boot/aarch64/Image` and `initramfs-linux.img` are present, and prints the
SHA-256.

Output: `out/iso/x-<version>-aarch64.iso`.

## 5. VM image

```bash
scripts/build-vm.sh --create      # empty qcow2
scripts/build-vm.sh --install     # boots the ISO with scripts/vm.sh
scripts/build-vm.sh --install --seed-json x-install.json   # unattended
scripts/build-vm.sh --export      # .qcow2 + .raw + .sha256 in out/vm/
```

See `../vm/README.md` for UTM/Parallels/VMware import and the no-3D caveat.

## 6. Publish

```bash
X_REPO_SIGN_KEY=... scripts/publish-arm.sh --verify
```

Uploads to SourceForge (`/home/frs/project/equislinux/arm/iso`) and updates
`web/data/releases-arm.json`, which is separate from the x86_64 index.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `target not found: linux` | ALARM has no `linux` | use `linux-aarch64` (already in `packages.aarch64`) |
| `target not found: archiso` | not packaged in ALARM | `scripts/fetch-archiso.sh` |
| `target not found: stubble` | not packaged in ALARM | expected warning; DTBs are not merged |
| `grub-mkstandalone: cannot find arm64-efi` | x86_64 host | build on aarch64; install ALARM `grub` |
| ISO has no `BOOTAA64.EFI` | x86 profile leaked in | `apply-overlay.sh` and check `bootmodes` |
| `xgen: no archived kernel` | `xgen` globs `vmlinuz-*` | known gap; `x gen new` is best-effort |
| pacman DB signature error | ALARM DBs are unsigned | `SigLevel = Required DatabaseOptional` |
| Boot hangs with no serial output | `console=ttyS0` is x86 | `console=ttyAMA0` |
| `makepkg` refuses to run | running as root | use a normal user |

## Parity status

Implemented: profile, package set, `[x]` repo, ISO build, VM images, publishing,
installer patch (UEFI layout, `arm64-efi`, `BOOTAA64`, `Image`, ALARM keyring,
ALARM repos).

Pending: `xgen`/`xkernel` support for `Image` and the missing `pkgbase` file;
a fully unattended VM install; UTM `.utm` bundle generation; hardware tests on
real aarch64 machines. None of these block booting and installing.
