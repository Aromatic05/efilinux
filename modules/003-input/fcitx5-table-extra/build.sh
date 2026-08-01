#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fcitx5-table-extra
pkgver=5.1.8
depends=(fcitx5 libime)
builddepends=(extra-cmake-modules fcitx5 libime)
makedepends=(cmake gettext ninja pkg-config)

prepare() {
    local archive="$downloaddir/fcitx5-table-extra-$pkgver.tar.gz"
    download "https://github.com/fcitx/fcitx5-table-extra/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 39577ac6ff74f559f0c7b8ba64100458bd56fac34b62d9aff64575dd3a0f2805 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir"
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
}

package() {
    package_keep /usr/share/fcitx5/inputmethod/
}

recipe_main "$@"
