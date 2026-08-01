#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=rpcbind
pkgver=1.2.9
depends=(glibc libtirpc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/rpcbind-$pkgver.tar.bz2"
    download "https://downloads.sourceforge.net/project/rpcbind/rpcbind/$pkgver/rpcbind-$pkgver.tar.bz2" "$archive"
    checksum sha256 ce5f1a87c566ef0b2897a28f50a75c1dc23fec413a46a7f4183423b6b6aa991b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --disable-libwrap \
        --disable-warmstarts \
        --disable-rmtcalls \
        --with-statedir=/run/rpcbind \
        --with-rpcuser=root \
        --with-nss-modules=files \
        --with-systemdsystemunitdir=no
    target_make_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/rpcbind \
        /usr/bin/rpcinfo
}

recipe_main "$@"
