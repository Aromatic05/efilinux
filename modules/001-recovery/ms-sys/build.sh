#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=ms-sys
pkgver=2.8.0
depends=(glibc)
builddepends=()
makedepends=(gcc gzip make)
prepare() {
    local archive="$downloaddir/ms-sys-$pkgver.tar.gz"
    download "https://downloads.sourceforge.net/project/ms-sys/ms-sys%20stable/$pkgver/ms-sys-$pkgver.tar.gz" "$archive"
    checksum sha256 a902ee3ebd0cb7038ed077e3aa8a8c8335a6c472f5056d7e08af33d7e783f157 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    local cc
    cc=$(target_compiler_wrapper gcc)
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        CC="$cc" \
        EXTRA_CFLAGS="$CFLAGS" \
        EXTRA_LDFLAGS="$LDFLAGS" \
        LANGUAGES=
    make -C "$srcdir/source" \
        DESTDIR="$develdir" \
        PREFIX=/usr \
        LANGUAGES= \
        install
}
devel() { strip_all "$develdir/usr/bin/ms-sys"; }
package() { package_keep /usr/bin/ms-sys; }
recipe_main "$@"
