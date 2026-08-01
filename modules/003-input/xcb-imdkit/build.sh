#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xcb-imdkit
pkgver=1.0.9
depends=(glibc xcb-util-keysyms xorg)
builddepends=(extra-cmake-modules xcb-util-keysyms)
makedepends=(cmake gcc ninja pkg-config)

prepare() {
    local archive="$downloaddir/xcb-imdkit-$pkgver.tar.gz"
    download "https://github.com/fcitx/xcb-imdkit/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 c2f0bbad8a335a64cdc7c19ac7b6ea1f0887dd6300ca9a4fa2e2fec6b9d3f695 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" -DBUILD_TESTING=OFF
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    local opt_lib="$develdir/opt/fcitx5/lib"

    install -d -m0755 "$opt_lib"
    find "$develdir/usr/lib" -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name 'libxcb-imdkit.so*' \) \
        -exec cp -a -t "$opt_lib" {} +
    strip_all "$develdir/usr/lib" "$opt_lib"
}

package() {
    local path
    local -a keep=()

    while IFS= read -r -d '' path; do
        keep+=("${path#$pkgdir}")
    done < <(find "$pkgdir/opt/fcitx5/lib" -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name 'libxcb-imdkit.so*' \) -print0)
    ((${#keep[@]} > 0)) || die "runtime libraries are missing for xcb-imdkit"
    package_keep "${keep[@]}"
}

recipe_main "$@"
