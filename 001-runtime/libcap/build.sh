#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libcap
pkgver=2.78

depends=(
    glibc
)
builddepends=(
    linux-headers
)
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/libcap-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        0d621e562fd932ccf67b9660fb018e468a683d7b827541df27813228c996bb11 \
        "$archive"
    extract "$archive" "$srcdir/libcap"
}

build() {
    log "Building Libcap"
    make -C "$srcdir/libcap" -j"$EFILINUX_JOBS" \
        BUILD_CC=gcc \
        CC="$CC" \
        CFLAGS="$CFLAGS -fPIC" \
        LDFLAGS="$LDFLAGS" \
        prefix=/usr \
        lib=lib \
        PAM_CAP=no \
        GOLANG=no \
        RAISE_SETFCAP=no
    make -C "$srcdir/libcap" \
        DESTDIR="$develdir" \
        prefix=/usr \
        lib=lib \
        PAM_CAP=no \
        GOLANG=no \
        RAISE_SETFCAP=no \
        install
}

devel() {
    rm -f "$develdir/usr/lib"/*.a
    if [[ -d "$develdir/usr/sbin" ]]; then
        mkdir -p "$develdir/usr/bin"
        mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/usr/sbin"
    fi
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local library_target

    library_target=$(readlink -- "$pkgdir/usr/lib/libcap.so.2")
    [[ -f "$pkgdir/usr/lib/$library_target" ]] || \
        die "Libcap SONAME target is missing: $library_target"

    package_keep \
        /usr/bin/capsh \
        /usr/bin/getcap \
        /usr/bin/getpcaps \
        /usr/bin/setcap \
        /usr/lib/libcap.so.2 \
        "/usr/lib/$library_target"
}

recipe_main "$@"
