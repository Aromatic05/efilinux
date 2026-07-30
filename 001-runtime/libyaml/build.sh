#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=libyaml
pkgver=0.2.5

depends=(
    glibc
)
builddepends=()
makedepends=(
    gcc
    make
)

prepare() {
    local archive="$downloaddir/yaml-$pkgver.tar.gz"

    download \
        "https://pyyaml.org/download/libyaml/yaml-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4 \
        "$archive"
    extract "$archive" "$srcdir/libyaml"
}

build() {
    log "Configuring libyaml"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/libyaml/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static

    log "Building libyaml"
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
            -name 'libyaml-0.so.*' \
            -print0 | LC_ALL=C sort -z
    )
    ((${#libraries[@]} > 0)) || die "libyaml runtime library is missing"
    for library in "${libraries[@]}"; do
        relative=/${library#"$pkgdir/"}
        keep+=("$relative")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
