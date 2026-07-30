#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libexif
pkgver=0.6.25

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/libexif-$pkgver.tar.xz"

    download \
        "https://github.com/libexif/libexif/releases/download/v$pkgver/libexif-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        62f74cf3bf673a6e24d2de68f6741643718541f83aca5947e76e3978c25dce83 \
        "$archive"
    extract "$archive" "$srcdir/libexif"
}

build() {
    log "Configuring libexif"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/libexif/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static \
            --disable-docs

    log "Building libexif"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local library relative
    local -a keep=()
    local -a libraries=()

    mapfile -d '' -t libraries < <(
        find "$pkgdir/usr/lib" -maxdepth 1 \
            \( -type f -o -type l \) \
            -name 'libexif.so.12*' \
            -print0 | LC_ALL=C sort -z
    )
    ((${#libraries[@]} > 0)) || die "libexif runtime library is missing"
    for library in "${libraries[@]}"; do
        relative=/${library#"$pkgdir/"}
        keep+=("$relative")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
