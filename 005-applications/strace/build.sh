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
    checksum sha256 2aa1e5a8a7315a5f440a4d5d01cf4cd4a317026f320de8144e81c9ff178a0f9f "$archive"
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
