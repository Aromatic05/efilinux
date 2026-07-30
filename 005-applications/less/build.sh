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
    checksum sha256 6a39bcc1c6a8e30c90d9d43cefa0412a0c72686c7f4ab5cc0fb5f55c9be8c7b5 "$archive"
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
