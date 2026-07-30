#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=dosfstools
pkgver=4.2

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/dosfstools-$pkgver.tar.gz"

    download \
        "https://github.com/dosfstools/dosfstools/releases/download/v$pkgver/dosfstools-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        64926eebf90092dca21b14259a5301b7b98e7b1943e8a201c7d726084809b527 \
        "$archive"
    extract "$archive" "$srcdir/dosfstools"
}

build() {
    log "Configuring dosfstools"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/dosfstools/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --disable-nls

    log "Building dosfstools"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/fatlabel \
        /usr/bin/fsck.fat \
        /usr/bin/mkfs.fat
}

recipe_main "$@"
