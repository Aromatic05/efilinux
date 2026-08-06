#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=ncdu
pkgver=1.22
depends=(glibc ncurses)
builddepends=()
makedepends=(autoconf automake gcc make pkg-config)
prepare() {
    local archive="$downloaddir/ncdu-$pkgver.tar.gz"
    download "https://dev.yorhel.nl/download/ncdu-$pkgver.tar.gz" "$archive"
    checksum sha256 0ad6c096dc04d5120581104760c01b8f4e97d4191d6c9ef79654fa3c691a176b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}
build() {
    target_autotools_configure "$srcdir/source" "$builddir" \
        --prefix=/opt/recovery \
        --libdir=/opt/recovery/lib \
        --with-ncursesw
    target_make_install "$builddir" "$develdir"
}
check() { [[ -x "$develdir/opt/recovery/bin/ncdu" ]] || die "ncdu binary is missing"; }
devel() { strip_all "$develdir/opt/recovery/bin/ncdu"; }
package() { package_keep /opt/recovery/bin/ncdu; }
recipe_main "$@"
