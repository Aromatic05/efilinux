#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=rsync
pkgver=3.4.4
depends=(acl glibc popt zlib)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/rsync-$pkgver.tar.gz"
    download "https://download.samba.org/pub/rsync/src/rsync-$pkgver.tar.gz" "$archive"
    checksum sha256 bd88cf82fa653da32314fb229136407c5c90f80d1758d8f4b091767877d8fa96 "$archive"
    extract "$archive" "$srcdir/rsync"
}

build() {
    cd "$builddir"
    target_env "$srcdir/rsync/configure" --prefix=/usr --disable-static \
        --with-included-zlib=no --with-included-popt=no --enable-acl \
        --disable-openssl --disable-xxhash --disable-zstd --disable-lz4
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/rsync; }

recipe_main "$@"
