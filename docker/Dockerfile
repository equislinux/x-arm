# X Linux aarch64 builder container.
#
# Base: the Arch Linux ARM rootfs imported by docker/build-image.sh
# (pinned by docker/rootfs.sha). Everything the x-arm pipeline needs is
# installed here, so the ISO can be built on any host with Docker:
#
#   docker/build-image.sh            # import rootfs + build xlinux-arm-builder
#   docker/run.sh scripts/fetch-x.sh # run anything inside the container
#
# The equislinux workspace is mounted at /workspace; the user inside the
# container is remapped to the workspace owner, so vendor/, out/ and work/
# are shared with the host.
ARG ROOTFS_IMAGE=xlinux-alarm-rootfs:latest
FROM ${ROOTFS_IMAGE}

RUN printf 'Server = http://mirror.archlinuxarm.org/$arch/$repo\n' > /etc/pacman.d/mirrorlist \
 && sed -i 's/^#DisableSandbox/DisableSandbox/' /etc/pacman.conf \
 && pacman-key --init \
 && pacman-key --populate archlinuxarm \
 && pacman -Syu --noconfirm --needed \
      base-devel git grub squashfs-tools libisoburn libarchive \
      dosfstools mtools erofs-utils mkinitcpio-archiso systemd-ukify \
      arch-install-scripts rsync qemu-img jq gnupg sudo rust \
 && useradd -m -s /bin/bash builder \
 && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder \
 && chmod 0440 /etc/sudoers.d/builder \
 && pacman -Scc --noconfirm

COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["bash"]
