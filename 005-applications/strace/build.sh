#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=strace
pkgver=6.17
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/strace-$pkgver.tar.xz"
    download "https://github.com/strace/strace/releases/download/v$pkgver/strace-$pkgver.tar.xz" "$archive"
    checksum sha256 0a7c7bedc7efc076f3242a0310af2ae63c292a36dd4236f079e88a93e98cb9c0 "$archive"
    extract "$archive" "$srcdir/strace"
}

build() {
    cd "$builddir"
    target_env "$srcdir/strace/configure" --prefix=/usr --disable-static \
        --disable-mpers --without-libunwind --without-libdw
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/strace; }

recipe_main "$@"
