#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
pkgname=foremost
pkgver=1.5.7
depends=(glibc)
builddepends=()
makedepends=(gcc make patch)
prepare() {
    local archive="$downloaddir/foremost-$pkgver.tar.gz"
    download "https://github.com/korczis/foremost/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 da27368947a3402b15f63190a90a37c09e45517783e0d9435c87a81f97d29e80 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/safety.patch" "$srcdir/safety.patch"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 < "$srcdir/safety.patch"
    sed -i 's#"/usr/local/etc/foremost.conf"#"/opt/efilinux/modules/recovery/foremost.conf"#' \
        "$srcdir/source/config.c"
    sed -i "/#define AUTHOR/a #define VERSION \"$pkgver\"" "$srcdir/source/main.h"
}
build() {
    make -C "$srcdir/source" -j"$EFILINUX_JOBS" \
        RAW_CC="$CC" \
        RAW_FLAGS="$CPPFLAGS $CFLAGS -Wall -fcommon" \
        LINK_OPT="$LDFLAGS"
    install -Dm0755 "$srcdir/source/foremost" "$develdir/usr/bin/foremost"
    install -Dm0644 "$srcdir/source/foremost.conf" \
        "$develdir/opt/efilinux/modules/recovery/foremost.conf"
}
devel() { strip_all "$develdir/usr/bin/foremost"; }
package() {
    package_keep /usr/bin/foremost /opt/efilinux/modules/recovery/foremost.conf
}
recipe_main "$@"
