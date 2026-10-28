# Acceptance criteria

A release is publishable when every item is checked on a clean aarch64 host.

## Inputs

- [ ] `vendor/x.sha` and `vendor/archiso.sha` are pinned to commits, not branches.
- [ ] `scripts/fetch-x.sh` and `scripts/fetch-archiso.sh` succeed from a clean clone.
- [ ] `scripts/apply-overlay.sh --check` passes (all checks green).
- [ ] `git -C vendor/x status --porcelain` shows only the expected overlay files.

## Repository `[x]/aarch64`

- [ ] `scripts/build-repo.sh` produces `x.db` and one package per default entry.
- [ ] `pacman -Sy --config /dev/null` style test: `repo-add` index lists every package.
- [ ] Every package has `arch=aarch64` or `arch=any` (`pacman -Qi` or `bsdtar -xOf`).
- [ ] `x-release` installs `os-release` with `ID=x` and no "Arch" in user-visible fields.
- [ ] With `--sign`, `gpg --verify` passes for `x.db`, packages and `SHA256SUMS`.

## ISO

- [ ] `sudo scripts/build-iso.sh` finishes with exit 0.
- [ ] The ISO contains `EFI/BOOT/BOOTAA64.EFI`, `arch/boot/aarch64/Image` and
      `arch/boot/aarch64/initramfs-linux.img`.
- [ ] No `vmlinuz-linux`, no `syslinux` boot, no `BOOTX64.EFI` in the ISO.
- [ ] `grub.cfg` and `loopback.cfg` point at `/Image` and `initramfs-linux.img`.
- [ ] `x-<version>-aarch64.iso.sha256` matches a fresh `sha256sum`.

## Boot (QEMU `virt`, edk2-aarch64)

- [ ] GRUB menu appears over serial/GUI; default entry boots.
- [ ] Live system reaches a login prompt.
- [ ] Serial console is `ttyAMA0`; the autoinstall entry passes `xauto=1`.
- [ ] `pacman -Sy` works against ALARM; `[x]` is trusted after `x-keyring.service`.
- [ ] `xinstall` starts and the configurator offers `linux-aarch64`.

## Install

- [ ] Wipe install on a fresh disk completes (ESP + btrfs subvolumes).
- [ ] Installed system boots with GRUB `arm64-efi` (and with systemd-boot if tested).
- [ ] `/etc/pacman.conf` in the target contains `[x]` pointing at `.../aarch64`.
- [ ] Keyring in the target has `archlinuxarm` populated and the X key signed.
- [ ] `uname -m` is `aarch64`; `pacman -Q linux-aarch64` succeeds.
- [ ] Dualboot path does not touch an existing ESP or foreign EFI entries.

## VM deliverables

- [ ] `build-vm.sh --export` produces `.qcow2`, `.raw` and `.sha256`.
- [ ] The `.qcow2` boots in UTM (QEMU backend) and the `.raw` in UTM (Apple backend).
- [ ] Desktop session (if installed) starts; blur/animations disabled in docs.
- [ ] No claim of 3D acceleration or hardware video decode anywhere.

## Publishing

- [ ] `publish-arm.sh --dry-run` shows the right version, size and hash.
- [ ] Uploaded files are `x-<version>-aarch64.iso`, `.sig`, `SHA256SUMS(.sig)`.
- [ ] `web/data/releases-arm.json` is valid JSON and does not alter the x86 index.
- [ ] `publish-arm.sh --verify` downloads and matches the SHA-256.

## Regressions

- [ ] `equislinux/x` main is untouched (`git -C ../x status` clean).
- [ ] The x86_64 ISO build is unaffected (no shared files modified).
- [ ] No ISO, qcow2, raw or `.utm.zip` committed to any repository.
