#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=xarchiver
pkgver=0.5.4.25
depends=(glibc gtk3 libarchive sevenzip)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/xarchiver-$pkgver.tar.gz"
    download "https://github.com/ib/xarchiver/releases/download/$pkgver/xarchiver-$pkgver.tar.gz" "$archive"
    checksum sha256 9a80c2f6a9ea17f66df4085a97f7d94021ae82f3386c90c1467009121683a445 "$archive"
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
package() { package_keep /usr/bin/xarchiver /usr/share/applications/xarchiver.desktop; }

recipe_main "$@"
