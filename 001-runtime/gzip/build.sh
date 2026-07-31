#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=gzip
pkgver=1.14
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/gzip-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/gzip/gzip-$pkgver.tar.xz" "$archive"
    checksum sha256 01a7b881bd220bfdf615f97b8718f80bdfd3f6add385b993dcf6efd14e8c0ac6 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-dependency-tracking
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() { rm -rf "$develdir/usr/share"; strip_all "$develdir/usr/bin/gzip"; }
package() { package_keep /usr/bin/gzip /usr/bin/gunzip /usr/bin/zcat /usr/bin/zgrep; }
recipe_main "$@"
