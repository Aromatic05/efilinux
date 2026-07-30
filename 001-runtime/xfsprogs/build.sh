#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=xfsprogs
pkgver=7.1.1

depends=(
    glibc
    inih
    userspace-rcu
    util-linux
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
    local archive="$downloaddir/xfsprogs-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/utils/fs/xfs/xfsprogs/xfsprogs-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        063edc31ba8e85c95c7faf9be465a04898bba7c6e622fdd9b146eed4ca5415e8 \
        "$archive"
    extract "$archive" "$srcdir/xfsprogs"
}

build() {
    log "Configuring XFSprogs"
    cd "$srcdir/xfsprogs"
    ac_cv_search_dm_task_create=no \
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        ./configure \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --enable-shared=yes \
            --enable-static=no \
            --enable-editline=no \
            --enable-lto=no \
            --enable-scrub=no \
            --enable-libicu=no

    log "Building XFSprogs"
    make -j"$EFILINUX_JOBS"
    make DIST_ROOT="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local library relative
    local -a keep=(
        /usr/bin/fsck.xfs
        /usr/bin/mkfs.xfs
        /usr/bin/xfs_admin
        /usr/bin/xfs_db
        /usr/bin/xfs_growfs
        /usr/bin/xfs_info
        /usr/bin/xfs_io
        /usr/bin/xfs_logprint
        /usr/bin/xfs_mdrestore
        /usr/bin/xfs_metadump
        /usr/bin/xfs_repair
    )
    local -a libraries=()

    mapfile -d '' -t libraries < <(
        find "$pkgdir/usr/lib" -maxdepth 1 \
            \( -type f -o -type l \) \
            -name 'libhandle.so.*' \
            -print0 | LC_ALL=C sort -z
    )
    ((${#libraries[@]} > 0)) || die "XFS runtime library is missing"
    for library in "${libraries[@]}"; do
        relative=/${library#"$pkgdir/"}
        keep+=("$relative")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
