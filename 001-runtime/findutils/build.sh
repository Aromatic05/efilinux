#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=findutils
pkgver=4.11.0
depends=(glibc)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/findutils-$pkgver.tar.xz"
    download "https://ftp.gnu.org/gnu/findutils/findutils-$pkgver.tar.xz" "$archive"
    checksum sha256 bfd19cb06cc71f3352d567e90284d8cdac02ac89774bbeadf0b533b0c11432fd "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --localstatedir=/var/lib/locate --disable-nls --disable-dependency-tracking \
        --without-selinux
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() { rm -rf "$develdir/usr/share" "$develdir/var"; strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/find /usr/bin/xargs; }
recipe_main "$@"
