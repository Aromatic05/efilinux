#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libepoxy
pkgver=1.5.10

depends=(glibc)
builddepends=(xorg mesa)
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libepoxy-1.5.10.tar.gz"

    download \
        "https://github.com/anholt/libepoxy/archive/refs/tags/1.5.10.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Ddocs=false \
        -Dtests=false \
        -Dglx=yes \
        -Degl=yes \
        -Dx11=true
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libepoxy.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
