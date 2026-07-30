#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=openssl
pkgver=3.6.3

depends=(glibc zlib)
builddepends=()
makedepends=(gcc make perl)

prepare() {
    local archive="$downloaddir/openssl-$pkgver.tar.gz"
    download \
        "https://github.com/openssl/openssl/releases/download/openssl-$pkgver/openssl-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1 "$archive"
    extract "$archive" "$srcdir/openssl"
}

build() {
    log "Configuring OpenSSL"
    cd "$srcdir/openssl"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        ./Configure linux-x86_64 \
            --prefix=/usr \
            --openssldir=/etc/ssl \
            --libdir=lib \
            shared zlib no-tests no-docs

    log "Building OpenSSL"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install_sw install_ssldirs
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/bin/openssl)
    package_add_library_family keep 'libcrypto.so.3*'
    package_add_library_family keep 'libssl.so.3*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
