#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=grub
pkgver=2.12
depends=(glibc util-linux xz zstd)
builddepends=()
makedepends=(bison flex gcc gettext make python3)
prepare() {
    local archive="$downloaddir/grub-$pkgver.tar.xz"
    download "https://ftpmirror.gnu.org/grub/grub-$pkgver.tar.xz" "$archive"
    checksum sha256 f3c97391f7c4eaa677a78e090c7e97e6dc47b16f655f04683ebd37bef7fe0faa "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    : > "$srcdir/source/grub-core/extra_deps.lst"
}
build_platform() {
    local target=$1 platform=$2 output=$3
    mkdir -p "$output"
    target_release_configure "$srcdir/source" "$output" \
        --target="$target" \
        --with-platform="$platform" \
        --sbindir=/usr/bin \
        --disable-werror \
        --disable-nls \
        --disable-device-mapper \
        --disable-libzfs \
        --disable-grub-mkfont \
        --disable-grub-mount \
        --disable-efiemu
    target_make_install "$output" "$develdir"
}
build() {
    build_platform x86_64 efi "$builddir/efi"
    build_platform i386 pc "$builddir/pc"
}
check() {
    [[ -d "$develdir/usr/lib/grub/x86_64-efi" ]] || die "GRUB x86_64 EFI modules are missing"
    [[ -d "$develdir/usr/lib/grub/i386-pc" ]] || die "GRUB i386 PC modules are missing"
}
devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib/grub" || true
}
package() {
    package_keep \
        /usr/bin/ \
        /usr/lib/grub/ \
        /usr/share/grub/
}
recipe_main "$@"
