#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=curl
pkgver=8.21.0
depends=(glibc openssl zlib)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/curl-$pkgver.tar.xz"
    download "https://curl.se/download/curl-$pkgver.tar.xz" "$archive"
    checksum sha256 aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6 "$archive"
    extract "$archive" "$srcdir/curl"
}

build() {
    cd "$builddir"
    target_env "$srcdir/curl/configure" --prefix=/usr --libdir=/usr/lib \
        --disable-static --with-openssl --with-zlib --without-libpsl --without-nghttp2 \
        --without-brotli --without-zstd --without-libssh2 --without-libssh \
        --without-gnutls --without-gssapi --disable-ldap --disable-ldaps \
        --disable-manual --disable-docs --with-ca-path=/etc/ssl/certs
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin" "$develdir/usr/lib"; }
package() {
    local -a keep=(/usr/bin/curl)
    package_add_library_family keep 'libcurl.so.4*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
