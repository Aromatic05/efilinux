#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libime
pkgver=1.1.11
depends=(boost fcitx5 glibc zstd)
builddepends=(boost extra-cmake-modules fcitx5)
makedepends=(cmake gcc g++ ninja pkg-config)

prepare() {
    local archive="$downloaddir/libime-$pkgver.tar.zst"
    download "https://download.fcitx-im.org/fcitx5/libime/libime-$pkgver.tar.zst" "$archive"
    checksum sha256 26e57d1262658317532c746b599d47037f99ab8e122c7daafc93705a89405c2f "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/disable-fcitx4-migration-tools.patch" \
        "$srcdir/disable-fcitx4-migration-tools.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/disable-fcitx4-migration-tools.patch"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DENABLE_TEST=OFF \
        -DENABLE_DOC=OFF \
        -DENABLE_TOOLS=ON \
        -DENABLE_DATA=ON
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/lib/libime/ /usr/share/libime/)
    package_add_library_family keep 'libIME*.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
