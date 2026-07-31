#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=gptfdisk
pkgver=1.0.10
depends=(glibc ncurses popt util-linux)
builddepends=()
makedepends=(gcc make)
prepare() {
    local archive="$downloaddir/gptfdisk-$pkgver.tar.gz"
    download "https://downloads.sourceforge.net/project/gptfdisk/gptfdisk/$pkgver/gptfdisk-$pkgver.tar.gz" "$archive"
    checksum sha256 2abed61bc6d2b9ec498973c0440b8b804b7a72d7144069b5a9209b2ad693a282 "$archive"
    extract "$archive" "$srcdir/source"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    sed -i 's#<ncursesw/ncurses.h>#<ncurses.h>#' "$srcdir/source/gptcurses.cc"
}
build() {
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        CXX="$CXX" CXXFLAGS="$CXXFLAGS -Wall -D_FILE_OFFSET_BITS=64" \
        LDFLAGS="$LDFLAGS" STRIP=:
    install -d -m0755 "$develdir/usr/bin"
    install -m0755 "$srcdir/source"/{gdisk,cgdisk,sgdisk,fixparts} "$develdir/usr/bin/"
}
devel() { strip_all "$develdir/usr/bin"; }
package() { package_keep /usr/bin/gdisk /usr/bin/cgdisk /usr/bin/sgdisk /usr/bin/fixparts; }
recipe_main "$@"
