#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=less
pkgver=679
depends=(glibc ncurses pcre2)
builddepends=()
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/less-$pkgver.tar.gz"
    download "https://www.greenwoodsoftware.com/less/less-$pkgver.tar.gz" "$archive"
    checksum sha256 9b68820c34fa8a0af6b0e01b74f0298bcdd40a0489c61649b47058908a153d78 "$archive"
    extract "$archive" "$srcdir/less"
}

build() {
    cd "$builddir"
    target_env "$srcdir/less/configure" --prefix=/usr --sysconfdir=/etc \
        --with-regex=pcre2 --with-secure-user=none
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/less /usr/bin/lessecho /usr/bin/lesskey; }

recipe_main "$@"
