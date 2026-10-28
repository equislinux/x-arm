#!/usr/bin/env bash
# shellcheck disable=SC2034
# archiso profile for X Linux on aarch64. Overlaid on the pinned equislinux/x
# checkout by scripts/apply-overlay.sh.

iso_name="x"
iso_label="x_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Xscriptor <https://xscriptor.io/x>"
iso_application="X Live/Rescue (aarch64)"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
# aarch64 has no BIOS path in this port: UEFI only.
bootmodes=('uefi.grub')
packages_file="packages.aarch64"
arch="aarch64"
pacman_conf="pacman.aarch64.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'arm64' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
# Generic aarch64 (QEMU virt, Apple Virtualization, SBCs). console=ttyAMA0 is
# added only to the serial/autoinstall boot entries, not to the GUI default.
kernel_params_aarch64="clk_ignore_unused pd_ignore_unused arm64.nopauth"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/x-repo-key"]="0:0:755"
  ["/usr/local/bin/xinstall"]="0:0:755"
)
