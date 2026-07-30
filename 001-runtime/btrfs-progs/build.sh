#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=btrfs-progs
pkgver=7.1

depends=(
    glibc
    lzo
    util-linux
    zlib
    zstd
)
builddepends=(
    linux-headers
)
makedepends=(
    gcc
    make
    pkg-config
)

prepare() {
    local archive="$downloaddir/btrfs-progs-v$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/btrfs-progs-v$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        d1f55cc2971398c9142eaa79d203e63d586a3b4b867f956664a1d68322cd4e34 \
        "$archive"
    extract "$archive" "$srcdir/btrfs-progs"
}

build() {
    log "Configuring Btrfs-progs"
    cd "$srcdir/btrfs-progs"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        ./configure \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --disable-static \
            --disable-documentation \
            --disable-convert \
            --disable-zoned \
            --disable-libudev \
            --disable-python \
            --with-crypto=builtin

    log "Building Btrfs-progs"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local library relative
    local -a keep=(
        /usr/bin/btrfs
        /usr/bin/btrfs-find-root
        /usr/bin/btrfs-image
        /usr/bin/btrfstune
        /usr/bin/fsck.btrfs
        /usr/bin/mkfs.btrfs
    )
    local -a libraries=()

    mapfile -d '' -t libraries < <(
        find "$pkgdir/usr/lib" -maxdepth 1 \
            \( -type f -o -type l \) \
            \( -name 'libbtrfs.so.*' -o -name 'libbtrfsutil.so.*' \) \
            -print0 | LC_ALL=C sort -z
    )
    ((${#libraries[@]} > 0)) || die "Btrfs runtime libraries are missing"
    for library in "${libraries[@]}"; do
        relative=/${library#"$pkgdir/"}
        keep+=("$relative")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
