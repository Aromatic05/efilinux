#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=userspace-rcu
pkgver=0.15.2

depends=(
    glibc
)
builddepends=(
    linux-headers
)
makedepends=(
    gcc
    make
    pkg-config
)

prepare() {
    local archive="$downloaddir/userspace-rcu-$pkgver.tar.bz2"

    download \
        "https://lttng.org/files/urcu/userspace-rcu-$pkgver.tar.bz2" \
        "$archive"
    checksum \
        sha256 \
        59f36f2b8bda1b7620a7eced2634f26c549444818a8313025a3bb09c0766a61d \
        "$archive"
    extract "$archive" "$srcdir/userspace-rcu"
}

build() {
    log "Configuring Userspace RCU"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        "$srcdir/userspace-rcu/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --disable-static

    log "Building Userspace RCU"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/lib"
}

package() {
    local soname target
    local -a keep=()

    for soname in \
        liburcu.so.8 \
        liburcu-common.so.8; do
        target=$(readlink -- "$pkgdir/usr/lib/$soname")
        [[ -f "$pkgdir/usr/lib/$target" ]] || \
            die "Userspace RCU SONAME target is missing: $target"
        keep+=("/usr/lib/$soname" "/usr/lib/$target")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
