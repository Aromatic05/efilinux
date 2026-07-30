#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=linux-headers
pkgver=6.18.10

depends=()
builddepends=()
makedepends=(
    make
)

prepare() {
    local archive="$downloaddir/linux-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/kernel/v${pkgver%%.*}.x/linux-$pkgver.tar.xz" \
        "$archive"
    checksum \
        md5 \
        660e706a43f634b1fcd911f8839d2f61 \
        "$archive"
    extract "$archive" "$srcdir/linux"
}

build() {
    make -C "$srcdir/linux" mrproper
    make -C "$srcdir/linux" headers
    find "$srcdir/linux/usr/include" -type f ! -name '*.h' -delete
    mkdir -p "$develdir/usr"
    cp -a "$srcdir/linux/usr/include" "$develdir/usr/"
}

package() {
    package_keep
}

recipe_main "$@"
