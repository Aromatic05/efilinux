#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=sysvinit
pkgver=3.14
sysroot=false

depends=(glibc libxcrypt)
builddepends=(linux-headers)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/sysvinit-$pkgver.tar.xz"
    download \
        "https://github.com/slicer69/sysvinit/releases/download/$pkgver/sysvinit-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 c90874b8c054a35991fb8c4d30c443ed1e9b1815ff6165c7b483f558be4e4b53 "$archive"
    extract "$archive" "$srcdir/sysvinit"
}

build() {
    log "Building SysVinit"
    make -C "$srcdir/sysvinit/src" -j"$EFILINUX_JOBS" \
        CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
    make -C "$srcdir/sysvinit/src" ROOT="$develdir" install
}

devel() {
    install -d -m0755 "$develdir/usr/bin"
    if [[ -d "$develdir/sbin" ]]; then
        mv "$develdir/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/sbin"
    fi
    if [[ -d "$develdir/bin" ]]; then
        mv "$develdir/bin"/* "$develdir/usr/bin/"
        rmdir "$develdir/bin"
    fi
    ln -snf killall5 "$develdir/usr/bin/pidof"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep /usr/bin/
}

recipe_main "$@"
