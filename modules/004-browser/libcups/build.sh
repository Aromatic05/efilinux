#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libcups
pkgver=2.4.7
depends=(glibc libxcrypt openssl zlib)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/cups-$pkgver-source.tar.gz"
    download "https://github.com/OpenPrinting/cups/releases/download/v$pkgver/cups-$pkgver-source.tar.gz" "$archive"
    checksum sha256 dd54228dd903526428ce7e37961afaed230ad310788141da75cebaa08362cf6c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    cp -a "$srcdir/source/." "$builddir/"
    target_release_configure "$builddir" "$builddir" \
        --disable-static \
        --disable-dbus \
        --disable-pam \
        --disable-libusb \
        --disable-acl \
        --with-tls=openssl \
        --with-dnssd=no \
        --without-systemd
    make -C "$builddir/cups" -j"$EFILINUX_JOBS" libcups.so.2
    install -Dm0755 "$builddir/cups/libcups.so.2" "$develdir/usr/lib/libcups.so.2"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    package_keep /usr/lib/libcups.so.2
}

recipe_main "$@"
