#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=squashfs-tools
pkgver=4.6.1

depends=(zstd)
builddepends=(zstd)
makedepends=(gcc make)

prepare() {
    local archive="$downloaddir/squashfs-tools-$pkgver.tar.gz"

    download \
        "https://github.com/plougher/squashfs-tools/archive/refs/tags/$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        9c4974e07c61547dae14af4ed1f358b7d04618ae194e54d6be72ee126f0d2f53 \
        "$archive"
    extract "$archive" "$srcdir/squashfs-tools"
}

build() {
    make -C "$srcdir/squashfs-tools/squashfs-tools" \
        -j"$EFILINUX_JOBS" \
        COMP_DEFAULT=zstd \
        XZ_SUPPORT=0 \
        LZ4_SUPPORT=0 \
        LZO_SUPPORT=0 \
        LZMA_XZ_SUPPORT=0 \
        GZIP_SUPPORT=0 \
        CC="$CC" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS"

    install -Dm0755 \
        "$srcdir/squashfs-tools/squashfs-tools/mksquashfs" \
        "$develdir/usr/bin/mksquashfs"
    install -Dm0755 \
        "$srcdir/squashfs-tools/squashfs-tools/unsquashfs" \
        "$develdir/usr/bin/unsquashfs"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    :
}

recipe_main "$@"
