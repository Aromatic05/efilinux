#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=cpio
pkgver=2.15
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/cpio-$pkgver.tar.bz2"
    download "https://ftp.gnu.org/gnu/cpio/cpio-$pkgver.tar.bz2" "$archive"
    checksum sha256 937610b97c329a1ec9268553fb780037bcfff0dcffe9725ebc4fd9c1aa9075db "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/gcc16-c23-prototypes.patch" \
        "$srcdir/gcc16-c23-prototypes.patch"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 < "$srcdir/gcc16-c23-prototypes.patch"
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
devel() { rm -rf "$develdir/usr/share"; strip_all "$develdir/usr/bin/cpio"; }
package() { package_keep /usr/bin/cpio; }
recipe_main "$@"
