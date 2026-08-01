#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=traceroute
pkgver=2.1.6
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/traceroute-$pkgver.tar.gz"
    download "https://downloads.sourceforge.net/project/traceroute/traceroute/traceroute-$pkgver/traceroute-$pkgver.tar.gz" "$archive"
    checksum sha256 9ccef9cdb9d7a98ff7fbf93f79ebd0e48881664b525c4b232a0fcec7dcb9db5e "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    cp -a "$srcdir/source/." "$builddir/"
    make -C "$builddir" -j"$EFILINUX_JOBS" env=yes \
        CC="$(target_compiler_wrapper gcc)" \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        prefix=/usr
    make -C "$builddir" env=yes \
        CC="$(target_compiler_wrapper gcc)" \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        prefix=/usr \
        DESTDIR="$develdir" \
        install
}

devel() {
    chmod 0755 "$develdir/usr/bin/traceroute"
    rm -rf "$develdir/usr/share/man"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/traceroute
}

recipe_main "$@"
