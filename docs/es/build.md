# Compilar X Linux para aarch64

Este repositorio es un **build por overlay**: clona `equislinux/x` en un commit
fijado, aplica `overlay/` y ejecuta archiso. El árbol x86_64 no se modifica.

## 1. Host de compilación

La ISO se compila en aarch64. En un Mac con Apple Silicon, crea una VM Arch
Linux ARM (UTM, "Virtualize", 8 GiB de RAM, 20 GiB de disco) y trabaja dentro.

```bash
# dentro de la VM ALARM
pacman -Syu --needed base-devel git grub squashfs-tools libisoburn \
  dosfstools mtools erofs-utils mkinitcpio-archiso systemd-ukify \
  arch-install-scripts rsync qemu-img qemu-system-aarch64 xorriso libarchive
```

`archiso` no está empaquetado en ALARM. `scripts/fetch-archiso.sh` clona
upstream, que ya soporta aarch64 (`grub_target=arm64-efi`, `BOOTAA64.EFI`,
`kernel_params_aarch64`).

No compiles como root el repo: `makepkg` lo rechaza. Usa el usuario normal;
solo `build-iso.sh` necesita root.

## 2. Entradas

```bash
scripts/fetch-x.sh            # vendor/x en vendor/x.sha
scripts/fetch-archiso.sh      # vendor/archiso en vendor/archiso.sha
scripts/apply-overlay.sh      # reset + overlay + parche del instalador + checks
```

`apply-overlay.sh` resetea `vendor/x` a su commit fijado, así el resultado es
reproducible y no se cuelan ficheros viejos.

`vendor/x.sha` es el contrato con x86_64: súbelo a propósito cuando quieras
cambios nuevos de upstream, y vuelve a aplicar el overlay y los checks.

## 3. Repositorio `[x]/aarch64`

```bash
scripts/build-repo.sh              # sin firma (pruebas locales)
X_REPO_SIGN_KEY=... scripts/build-repo.sh --sign
```

Por defecto: `x-release`, `x-wallpapers`, `x-dev`, `xfetch-bin`, `xtop-git`.
`--all` añade `opencode-bin` y `x-kde-settings`.

Los overrides de `overlay/packages/` pasan a aarch64 lo que era x86_64:

| Paquete | Cambio |
|---|---|
| `xfetch-bin` | tarball aarch64 v1.0.1 + sha256 fijado |
| `opencode-bin` | v1.19.5 `opencode-linux-arm64.tar.gz` + sha256 fijado |
| `xtop-git` | `arch=('aarch64')`; Rust desde fuente |
| `x-release`, `x-wallpapers`, `x-dev`, `x-kde-settings` | `any`, sin cambios |

Salida: `out/repo/aarch64/` (`x.db`, paquetes, `SHA256SUMS`, firmas).

## 4. ISO

```bash
sudo scripts/build-iso.sh                  # usa out/repo/aarch64
sudo scripts/build-iso.sh --no-repo        # usa la URL publicada de [x]/aarch64
```

`build-iso.sh` renderiza `pacman.aarch64.conf`, apunta `[x]` al repo local
(`file://`) y los mirrors ALARM al mirrorlist incluido. Luego ejecuta
`mkarchiso`, comprueba que existen `EFI/BOOT/BOOTAA64.EFI`,
`arch/boot/aarch64/Image` e `initramfs-linux.img`, e imprime el SHA-256.

Salida: `out/iso/x-<versión>-aarch64.iso`.

## 5. Imagen de VM

```bash
scripts/build-vm.sh --create      # qcow2 vacío
scripts/build-vm.sh --install     # arranca la ISO con scripts/vm.sh
scripts/build-vm.sh --export      # .qcow2 + .raw + .sha256 en out/vm/
```

Ver `../vm/README.md` para importar en UTM/Parallels/VMware y el aviso de no-3D.

## 6. Publicar

```bash
X_REPO_SIGN_KEY=... scripts/publish-arm.sh --verify
```

Sube a SourceForge (`/home/frs/project/equislinux/arm/iso`) y actualiza
`web/data/releases-arm.json`, separado del índice x86_64.

## Problemas típicos

| Síntoma | Causa | Arreglo |
|---|---|---|
| `target not found: linux` | ALARM no tiene `linux` | usa `linux-aarch64` (ya está en `packages.aarch64`) |
| `target not found: archiso` | no está en ALARM | `scripts/fetch-archiso.sh` |
| `target not found: stubble` | no está en ALARM | aviso esperado; no se fusionan DTBs |
| `grub-mkstandalone: cannot find arm64-efi` | host x86_64 | compila en aarch64; instala `grub` de ALARM |
| la ISO no tiene `BOOTAA64.EFI` | se coló el perfil x86 | `apply-overlay.sh` y revisa `bootmodes` |
| `xgen: no archived kernel` | `xgen` busca `vmlinuz-*` | gap conocido; `x gen new` es best-effort |
| error de firma de la DB | las DB de ALARM no están firmadas | `SigLevel = Required DatabaseOptional` |
| arranca sin salida por serie | `console=ttyS0` es x86 | `console=ttyAMA0` |
| `makepkg` se niega | se ejecutó como root | usa un usuario normal |

## Estado de paridad

Hecho: perfil, lista de paquetes, repo `[x]`, ISO, imágenes de VM, publicación
y parche del instalador (UEFI, `arm64-efi`, `BOOTAA64`, `Image`, keyring ALARM,
repos ALARM).

Pendiente: soporte de `Image` y de la ausencia de `pkgbase` en
`xgen`/`xkernel`; instalación desatendida en VM; generación de bundles `.utm`;
pruebas en hardware aarch64 real. Nada de esto impide arrancar e instalar.
