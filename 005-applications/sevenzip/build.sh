#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=sevenzip
pkgver=25.01
depends=(glibc)
builddepends=()
makedepends=(gcc g++ make)

prepare() {
    local archive="$downloaddir/7z${pkgver//./}-src.tar.xz"
    download "https://www.7-zip.org/a/7z${pkgver//./}-src.tar.xz" "$archive"
    checksum sha256 ed087f83ee789c1ea5f39c464c55a5c9d4008deb0efe900814f2df262b82c36e "$archive"
    extract "$archive" "$srcdir/sevenzip"
}

build() {
    CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
        make -C "$srcdir/sevenzip/CPP/7zip/Bundles/Alone2" -f makefile -j"$EFILINUX_JOBS"
    install -Dm0755 "$srcdir/sevenzip/CPP/7zip/Bundles/Alone2/b/7zz" \
        "$develdir/usr/bin/7zz"
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/7zz; }

recipe_main "$@"
