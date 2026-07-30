#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=vte
pkgver=0.74.2

depends=(at-spi2-core fribidi glib glibc gtk3 pango)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/vte-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/vte/0.74/vte-0.74.2.tar.xz" "$archive"
    checksum sha256 a535fb2a98fea8a2449cd1a02cccf5190131dddff52e715afdace3feb536eae7 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Da11y=true \
        -Ddebugg=false \
        -Ddocs=false \
        -Dgir=false \
        -Dfribidi=true \
        -Dglade=false \
        -Dgnutls=false \
        -Dgtk3=true \
        -Dgtk4=false \
        -Dicu=false \
        -D_systemd=false \
        -Dvapi=false
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=(/usr/libexec/)
    package_add_library_family keep 'libvte-2.91.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
