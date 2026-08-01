#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=dialog
pkgver=1.3-20260721
depends=(glibc ncurses)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/dialog-$pkgver.tgz"
    download "https://invisible-mirror.net/archives/dialog/dialog-$pkgver.tgz" "$archive"
    checksum sha256 62bdf59057d4f760a1cc2217827f07887b4a3eebf694c25eacd4803d2171cdc6 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --with-ncursesw \
        --enable-widec \
        --disable-rpath-hack \
        --disable-echo
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin/dialog"
}

package() {
    package_keep /usr/bin/dialog
}

recipe_main "$@"
