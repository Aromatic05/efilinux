#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=nmap
pkgver=7.99
depends=(gcc-libs glibc libpcap openssl pcre2 zlib)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/nmap-$pkgver.tar.bz2"
    download "https://nmap.org/dist/nmap-$pkgver.tar.bz2" "$archive"
    checksum sha256 df512492ffd108e53a27a06f26d8635bbe89e0e569455dc8ffef058c035d51b2 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    cp -a "$srcdir/source/." "$builddir/"
    target_release_configure "$builddir" "$builddir" \
        --bindir=/usr/bin \
        --without-zenmap \
        --without-ndiff \
        --without-libssh2 \
        --with-libpcap="$EFILINUX_SYSROOT/usr" \
        --with-openssl="$EFILINUX_SYSROOT/usr" \
        --with-libpcre="$EFILINUX_SYSROOT/usr" \
        --with-libz="$EFILINUX_SYSROOT/usr" \
        --with-libdnet=included \
        --with-liblua=included \
        --with-liblinear=included
    target_make_install "$builddir" "$develdir"
}

devel() {
    chmod 0755 "$develdir/usr/bin/nmap" "$develdir/usr/bin/ncat" "$develdir/usr/bin/nping"
    rm -rf \
        "$develdir/usr/share/man" \
        "$develdir/usr/share/doc" \
        "$develdir/usr/share/applications" \
        "$develdir/usr/share/icons"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/nmap \
        /usr/bin/ncat \
        /usr/bin/nping \
        /usr/share/nmap/
}

recipe_main "$@"
