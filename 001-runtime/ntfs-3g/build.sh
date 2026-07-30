#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=ntfs-3g
pkgver=2026.7.7

depends=(
    glibc
)
builddepends=(
    linux-headers
)
makedepends=(
    autoreconf
    gcc
    make
    pkg-config
)

prepare() {
    local archive="$downloaddir/ntfs-3g-$pkgver.tar.gz"

    download \
        "https://github.com/tuxera/ntfs-3g/archive/refs/tags/$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        7742bfe3399a7b2f677fea8aa193dc21d38112d77ae8beb0fb66aaf550f72c1d \
        "$archive"
    extract "$archive" "$srcdir/ntfs-3g"
}

build() {
    log "Preparing NTFS maintenance tools"
    autoreconf -fi "$srcdir/ntfs-3g"

    log "Configuring NTFS maintenance tools"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/ntfs-3g/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --disable-static \
            --disable-ntfs-3g \
            --disable-plugins \
            --enable-extras \
            --disable-nls

    log "Building NTFS maintenance tools"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
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
        /usr/bin/mkntfs
        /usr/bin/ntfsclone
        /usr/bin/ntfsfix
        /usr/bin/ntfsinfo
        /usr/bin/ntfslabel
        /usr/bin/ntfsresize
        /usr/bin/ntfsundelete
    )
    local -a libraries=()

    if [[ -L "$pkgdir/usr/bin/mkfs.ntfs" ]]; then
        keep+=(/usr/bin/mkfs.ntfs)
    fi

    mapfile -d '' -t libraries < <(
        find "$pkgdir/usr/lib" -maxdepth 1 \
            \( -type f -o -type l \) \
            -name 'libntfs-3g.so.*' \
            -print0 | LC_ALL=C sort -z
    )
    ((${#libraries[@]} > 0)) || die "NTFS runtime library is missing"
    for library in "${libraries[@]}"; do
        relative=/${library#"$pkgdir/"}
        keep+=("$relative")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
