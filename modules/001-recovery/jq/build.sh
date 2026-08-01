#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=jq
pkgver=1.8.2
depends=(glibc)
builddepends=()
makedepends=(autoconf automake gcc libtool make)

prepare() {
    local archive="$downloaddir/jq-$pkgver.tar.gz"
    download "https://github.com/jqlang/jq/releases/download/jq-$pkgver/jq-$pkgver.tar.gz" "$archive"
    checksum sha256 71b8d6e8f5fe81f6c6d0d110e3892251f6ce76ed095abd315e26e6e1193af3af "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --disable-shared \
        --enable-static \
        --disable-docs \
        --with-oniguruma=builtin
    target_make_install "$builddir" "$develdir"
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin/jq"
}

package() {
    package_keep /usr/bin/jq
}

recipe_main "$@"
