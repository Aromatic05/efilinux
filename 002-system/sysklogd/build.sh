#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=sysklogd
pkgver=2.7.2
sysroot=false

depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/sysklogd-$pkgver.tar.gz"
    download \
        "https://github.com/troglobit/sysklogd/releases/download/v$pkgver/sysklogd-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 bc410ca64551a11fac6518b418fb6b8afbd888a70af2c5eb353334a706727bca "$archive"
    extract "$archive" "$srcdir/sysklogd"
}

build() {
    log "Configuring Sysklogd"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/sysklogd/configure" \
            --prefix=/usr \
            --sbindir=/usr/bin \
            --sysconfdir=/etc \
            --runstatedir=/run \
            --without-logger \
            --disable-static \
            --disable-man-pages

    log "Building Sysklogd"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/syslogd
}

recipe_main "$@"
