#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=grep
pkgver=3.12
depends=(glibc pcre2)
builddepends=()
makedepends=(gcc make pkg-config)
prepare() {
    local archive="$downloaddir/grep-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/grep/grep-$pkgver.tar.xz" "$archive"
    checksum sha256 2649b27c0e90e632eadcd757be06c6e9a4f48d941de51e7c0f83ff76408a07b9 "$archive"
    extract "$archive" "$srcdir/source"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    sed -i 's/echo/#echo/' "$srcdir/source/src/egrep.sh"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --disable-dependency-tracking
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() { rm -rf "$develdir/usr/share"; strip_all "$develdir/usr/bin/grep"; }
package() { package_keep /usr/bin/grep; }
recipe_main "$@"
