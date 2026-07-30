#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libxml2
pkgver=2.15.3

depends=(glibc zlib)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libxml2-$pkgver.tar.xz"
    download "https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.3.tar.xz" "$archive"
    checksum sha256 78262a6e7ac170d6528ebfe2efccdf220191a5af6a6cd61ea4a9a9a5042c7a07 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Ddocs=disabled \
        -Ddebugging=disabled \
        -Dhistory=disabled \
        -Dicu=disabled \
        -Dlegacy=disabled \
        -Dmodules=disabled \
        -Dpython=disabled \
        -Dreadline=disabled \
        -Diconv=enabled \
        -Dthreads=enabled \
        -Dzlib=enabled
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=()
    package_add_library_family keep 'libxml2.so.16*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
