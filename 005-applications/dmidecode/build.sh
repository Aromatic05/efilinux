#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=dmidecode
pkgver=3.7
depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/dmidecode-$pkgver.tar.xz"
    download "https://download.savannah.gnu.org/releases/dmidecode/dmidecode-$pkgver.tar.xz" "$archive"
    checksum sha256 2c3aed12c85a1e6a9410d406d5e417c455466dc1bc7c89278bb32cf7cad91e8a "$archive"
    extract "$archive" "$srcdir/dmidecode"
}

build() {
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
        make -C "$srcdir/dmidecode" -j"$EFILINUX_JOBS"
    make -C "$srcdir/dmidecode" prefix=/usr DESTDIR="$develdir" install
}

devel() {
    install -d -m0755 "$develdir/usr/bin"
    mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
    rmdir "$develdir/usr/sbin"
    strip_all "$develdir/usr/bin"
}
package() { package_keep /usr/bin/dmidecode /usr/bin/biosdecode /usr/bin/ownership; }

recipe_main "$@"
