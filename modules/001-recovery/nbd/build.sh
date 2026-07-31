#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=nbd
pkgver=3.24
depends=(glibc)
builddepends=(linux-headers)
makedepends=(autoconf automake bison flex gcc libtool make pkg-config)

prepare() {
    local archive="$downloaddir/nbd-$pkgver.tar.xz"
    download "https://downloads.sourceforge.net/project/nbd/nbd/$pkgver/nbd-$pkgver.tar.xz" "$archive"
    checksum sha256 6877156d23a7b33f75eee89d2f5c2c91c542afc3cdcb636dea5a88539a58d10c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --disable-manpages \
        --without-gnutls
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/nbd-client
}

recipe_main "$@"
