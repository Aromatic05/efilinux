#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=pixman
pkgver=0.46.4

depends=(glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/pixman-0.46.4.tar.gz"

    download \
        "https://gitlab.freedesktop.org/pixman/pixman/-/archive/pixman-0.46.4/pixman-pixman-0.46.4.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        1b8288086e5da0ec5cb95cf174a919cc6fe4548f10dc3cd873b3bb1d9e8fdeab \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dopenmp=disabled \
        -Dgtk=disabled \
        -Dlibpng=disabled \
        -Dtests=disabled \
        -Ddemos=disabled \
        -Dtimers=false \
        -Dgnuplot=false
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libpixman-1.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
