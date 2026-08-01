#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=breeze-cursor-theme
pkgver=5.27.12
sysroot=false

depends=()
builddepends=()
makedepends=()

prepare() {
    local archive="$downloaddir/breeze-$pkgver.tar.xz"
    download "https://download.kde.org/stable/plasma/$pkgver/breeze-$pkgver.tar.xz" "$archive"
    checksum sha256 b20443f360164a070416b642215e71ac4df89f544f27805907e7fc074e18fb6f "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    mkdir -p "$develdir/usr/share/icons"
    cp -a "$srcdir/source/cursors/Breeze/Breeze" \
        "$develdir/usr/share/icons/breeze-cursors"
}

package() {
    package_keep /usr/share/icons/breeze-cursors/
}

recipe_main "$@"
