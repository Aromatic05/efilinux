#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=bash
pkgver=5.3
depends=(glibc ncurses readline)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/bash-$pkgver.tar.gz"
    download "https://ftp.gnu.org/gnu/bash/bash-$pkgver.tar.gz" "$archive"
    checksum sha256 0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba "$archive"
    extract "$archive" "$srcdir/source"
}
build() {
    local small_cflags="${CFLAGS/-O2/-Os} -ffunction-sections -fdata-sections"
    local small_ldflags="$LDFLAGS -Wl,--gc-sections"
    cd "$builddir"
    target_env env CFLAGS="$small_cflags" LDFLAGS="$small_ldflags" \
        "$srcdir/source/configure" --prefix=/usr --bindir=/usr/bin \
        --disable-nls --without-bash-malloc --with-installed-readline
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}
devel() {
    rm -rf "$develdir/usr/share" "$develdir/usr/include" "$develdir/usr/lib/bash"
    strip_all "$develdir/usr/bin/bash"
}
package() { package_keep /usr/bin/bash; }
recipe_main "$@"
