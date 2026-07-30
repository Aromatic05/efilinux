#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=keyutils
pkgver=1.6.3

depends=(glibc)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/keyutils-$pkgver.tar.gz"
    download \
        "https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 46d4df640b9f50bfc53534c6f931046258cb8fe043497881473c5b664a7326ec "$archive"
    extract "$archive" "$srcdir/keyutils"
}

build() {
    make -C "$srcdir/keyutils" -j"$EFILINUX_JOBS" \
        CC="$CC" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        NO_ARLIB=1 \
        BINDIR=/usr/bin \
        SBINDIR=/usr/bin \
        LIBDIR=/usr/lib \
        USRLIBDIR=/usr/lib
    make -C "$srcdir/keyutils" install \
        DESTDIR="$develdir" \
        NO_ARLIB=1 \
        BINDIR=/usr/bin \
        SBINDIR=/usr/bin \
        LIBDIR=/usr/lib \
        USRLIBDIR=/usr/lib
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/lib"
}

package() {
    local target
    target=$(readlink -- "$pkgdir/usr/lib/libkeyutils.so.1")
    [[ -f "$pkgdir/usr/lib/$target" ]] || die "keyutils SONAME target is missing: $target"
    package_keep /usr/lib/libkeyutils.so.1 "/usr/lib/$target"
}

recipe_main "$@"
