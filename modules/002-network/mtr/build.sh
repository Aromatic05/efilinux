#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=mtr
pkgver=0.96
depends=(glibc jansson libcap ncurses)
builddepends=()
makedepends=(autoconf automake gcc make pkg-config)

prepare() {
    local archive="$downloaddir/mtr-$pkgver.tar.gz"
    download "https://github.com/traviscross/mtr/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 73e6aef3fb6c8b482acb5b5e2b8fa7794045c4f2420276f035ce76c5beae632d "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --without-gtk \
        --with-jansson \
        --with-ncurses \
        --with-ncursesw
    target_make_install "$builddir" "$develdir"
}

devel() {
    setcap -r "$develdir/usr/bin/mtr-packet" 2>/dev/null || true
    chmod 0755 "$develdir/usr/bin/mtr"
    chmod 4755 "$develdir/usr/bin/mtr-packet"
    rm -rf "$develdir/usr/share/man" "$develdir/usr/share/doc"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/mtr /usr/bin/mtr-packet
}

recipe_main "$@"
