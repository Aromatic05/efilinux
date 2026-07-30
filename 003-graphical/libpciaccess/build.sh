#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libpciaccess
pkgver=0.19

depends=(glibc zlib)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libpciaccess-0.19.tar.gz"

    download \
        "https://gitlab.freedesktop.org/xorg/lib/libpciaccess/-/archive/libpciaccess-0.19/libpciaccess-libpciaccess-0.19.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        ae2d080c8394d2b36a54aed270bc826f1438e41e7daf783ca5cff60285529ae2 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dzlib=enabled \
        -Dlinux-rom-fallback=false \
        -Dinstall-scanpci=false
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libpciaccess.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
