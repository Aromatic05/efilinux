#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=sed
pkgver=4.10
depends=(acl attr glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/sed-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/sed/sed-$pkgver.tar.xz" "$archive"
    checksum sha256 b8e72182b2ec96a3574e2998c47b7aaa64cc20ce000d8e9ac313cc07cecf28c7 "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --disable-dependency-tracking --without-selinux
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() { rm -rf "$develdir/usr/share"; strip_all "$develdir/usr/bin/sed"; }
package() { package_keep /usr/bin/sed; }
recipe_main "$@"
