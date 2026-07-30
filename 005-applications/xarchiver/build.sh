#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=xarchiver
pkgver=0.5.4.27
depends=(glibc gtk3 libarchive sevenzip)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xarchiver-$pkgver.tar.gz"
    download "https://github.com/ib/xarchiver/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 a52db2697f433621346dc4af59952728192878471e29f46b4b4221b7d5623a86 "$archive"
    extract "$archive" "$srcdir/xarchiver"
}

build() {
    cd "$builddir"
    target_env "$srcdir/xarchiver/configure" --prefix=/usr --disable-static \
        --disable-dependency-tracking --without-libgsf
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/xarchiver /usr/share/applications/xarchiver.desktop /usr/share/icons/hicolor/; }

recipe_main "$@"
