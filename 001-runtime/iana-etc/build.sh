#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=iana-etc
pkgver=20260617

depends=()
builddepends=()
makedepends=(
    install
)

prepare() {
    local archive="$downloaddir/iana-etc-$pkgver.tar.gz"

    download \
        "https://github.com/Mic92/iana-etc/releases/download/$pkgver/iana-etc-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        236bf9bf41e7d576f7343284d1ad7e37a7570b05cea58c5490fa56ad237a6497 \
        "$archive"
    extract "$archive" "$srcdir/iana-etc"
}

build() {
    install -Dm0644 "$srcdir/iana-etc/protocols" "$develdir/etc/protocols"
    install -Dm0644 "$srcdir/iana-etc/services" "$develdir/etc/services"
}

package() {
    :
}

recipe_main "$@"
