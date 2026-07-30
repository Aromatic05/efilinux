#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=doas
pkgver=6.8.2
sysroot=false

depends=(glibc linux-pam)
builddepends=(linux-headers)
makedepends=(gcc make yacc)

prepare() {
    local archive="$downloaddir/opendoas-$pkgver.tar.gz"
    download \
        "https://github.com/Duncaen/OpenDoas/archive/refs/tags/v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 6da058a0e70b7543bc60624389b0b00b686189ec933828c522bf8b2600495a67 "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    cp -a "$srcdir/source/." "$builddir/"
    cd "$builddir"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
        ./configure \
            --prefix=/usr \
            --sysconfdir=/etc \
            --pamdir=/etc/pam.d \
            --with-pam \
            --with-timestamp
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" BINOWN=0 BINGRP=0 install
}

devel() {
    strip_all "$develdir/usr/bin/doas"
}

package() {
    package_keep /usr/bin/doas
}

recipe_main "$@"
