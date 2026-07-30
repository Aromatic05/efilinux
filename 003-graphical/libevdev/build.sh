#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libevdev
pkgver=1.13.6

depends=(glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libevdev-1.13.6.tar.gz"

    download \
        "https://gitlab.freedesktop.org/libevdev/libevdev/-/archive/libevdev-1.13.6/libevdev-libevdev-1.13.6.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        54748fded25633399a8418d7c4c123fe365037c901b4389e0bf3dd7688fb1c7e \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dtests=disabled \
        -Dtools=disabled \
        -Ddocumentation=disabled
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libevdev.so.2*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
