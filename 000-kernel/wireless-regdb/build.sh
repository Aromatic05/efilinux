#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=wireless-regdb
pkgver=2026.05.30
sysroot=false

depends=()
builddepends=()
makedepends=(install)

prepare() {
    local archive="$downloaddir/wireless-regdb-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        8a27bfc081bafed8c24dd70fab0d96f098e5a0bfcd08d3da672595f225ab8993 \
        "$archive"
    extract "$archive" "$srcdir/wireless-regdb"
}

build() {
    install -Dm0644 \
        "$srcdir/wireless-regdb/regulatory.db" \
        "$develdir/usr/lib/firmware/regulatory.db"
    install -Dm0644 \
        "$srcdir/wireless-regdb/regulatory.db.p7s" \
        "$develdir/usr/lib/firmware/regulatory.db.p7s"
}

package() {
    :
}

recipe_main "$@"
