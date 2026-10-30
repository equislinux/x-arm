# prepare/ — candidate patches for upstream repos

Drafts that would land in other EquisLinux repositories. Nothing here is
applied by the x-arm build pipeline; each file documents its target repo,
base commit and status. When approved, the patch becomes a branch + PR on
that repo (never pushed without explicit approval).

| File | Target repo | Base commit | Purpose | Status |
|---|---|---|---|---|
| `generations-aarch64.patch` | `equislinux/scripts` | `21d43e3` (main, 2026-10-28) | Make the generations engine work on aarch64: `/boot/Image(.gz)`, no `pkgbase`, `linux-aarch64` | Draft; headless test suite green against the patched tree |

## generations-aarch64.patch

Contents (all x86_64 behaviour unchanged; every fallback is behind
`uname -m == aarch64` or the existence of `Image*` files, which Arch x86_64
does not install):

- `install/helpers/xkernel.sh`
  - `xkernel_known()`: adds `linux-aarch64` on aarch64 (keeps `X_KERNEL_KNOWN`).
  - New `xkernel_pkgbase_of()`: single place for the ALARM fallback (no
    `pkgbase` file in `/usr/lib/modules/<rel>/`).
  - `xkernel_release_of_pkgbase` / `xkernel_installed_pkgbases` /
    `xkernel_running_pkgbase` use the helper; restores the running-kernel
    protection in `x kernel remove`.
- `install/helpers/xgen.sh`
  - `xgen_capture_kernel`: archives `/boot/Image` and `/boot/Image.gz`.
  - `kernels.tsv`: synthesizes `pkgbase=linux-aarch64` (v1: single kernel) and
    maps the kernel name to `Image.gz`/`Image`.
  - `xgen_pick_pair`: legacy path pairs `Image*` with the first
    `initramfs-*.img`.
  - `xgen_state_unchanged`: compares `Image*` too, so a changed kernel is
    never skipped by the dedupe check.

Not covered (documented as P2 in ops `0002-aarch64-generations-strategy`):
`/boot/dtbs` archiving for frozen generations, aarch64 test fixtures, docs
updates, U-Boot support.

Validation done: `bash -n` on both helpers and the full headless suite of
`scripts` (`test/validate.sh`, generations + kernel sections) pass against
the patched tree inside the aarch64 Docker builder. The real aarch64 path
still needs a run on an installed ARM system (`x gen new` in the VM).
