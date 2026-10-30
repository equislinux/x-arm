# Docker build environment (Arch Linux ARM, aarch64)

Builder container for the x-arm pipeline. It runs the pinned Arch Linux ARM
rootfs (`rootfs.sha`) with all the build dependencies installed, so the
aarch64 ISO can be produced on any Docker host (Apple Silicon runs it
natively).

```bash
docker/fetch-rootfs.sh      # download + pin the ALARM rootfs (once)
docker/build-image.sh       # import rootfs, build xlinux-arm-builder
```

Then run the normal pipeline inside the container:

```bash
docker/run.sh scripts/fetch-x.sh
docker/run.sh scripts/fetch-archiso.sh
docker/run.sh scripts/apply-overlay.sh
docker/run.sh scripts/build-repo.sh          # normal user (makepkg)
docker/run.sh sudo scripts/build-iso.sh      # root (mkarchiso)
```

`docker/run.sh` mounts the equislinux workspace at `/workspace`, so
`vendor/`, `work/` and `out/` are shared with the host. The container user is
remapped to the workspace owner.

Notes:

- The container is privileged: `mkarchiso` needs mounts and chroots.
- `qemu-system-aarch64` is deliberately not installed; run `scripts/vm.sh`
  on the host (macOS: `brew install qemu` uses HVF acceleration).
- The rootfs tarball is ~790 MB and lives in `docker/rootfs/` (gitignored).

## Signing keys

Signing stays out of git. Put the GPG homedir at
`~/.config/equislinux/keys/gnupg` (or point `X_ARM_GNUPGHOME` at it) and the
SourceForge SSH key in `~/.ssh`. `run.sh` mounts both read-only and the
entrypoint copies them into `/home/builder` (fresh copy each run, avoids
virtiofs socket issues with gpg-agent).

Import the project key once:

```sh
mkdir -p ~/.config/equislinux/keys/gnupg && chmod 700 ~/.config/equislinux/keys/gnupg
# transfer the key export, then:
docker/run.sh bash -lc 'gpg --import < /workspace/keys/export.asc 2>/dev/null || true'
```

Wait — prefer importing on the host with a dedicated GNUPGHOME so the key
never touches the container build cache:

```sh
GNUPGHOME=~/.config/equislinux/keys/gnupg gpg --import x-signing.asc
GNUPGHOME=~/.config/equislinux/keys/gnupg gpg --list-secret-keys --with-colons | awk -F: '/^sec/{print $5}'
```

Then sign and publish:

```sh
X_REPO_SIGN_KEY=<keyid> docker/run.sh scripts/build-repo.sh --sign
X_REPO_SIGN_KEY=<keyid> docker/run.sh scripts/publish-repo.sh --push
X_REPO_SIGN_KEY=<keyid> docker/run.sh scripts/publish-arm.sh --verify
```

For the ISO the `[x]` repo can be the published Pages URL
(`docker/run.sh sudo scripts/build-iso.sh --no-repo`), or rebuild the local
repo with `--sign` first.
