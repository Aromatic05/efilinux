#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=e2fsprogs
pkgver=1.47.4

depends=(
    glibc
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
    local archive="$downloaddir/e2fsprogs-$pkgver.tar.gz"

    download \
        "https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v$pkgver/e2fsprogs-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        2cec05f39c20ee621f14926195664e66e6017190ac8e4bbdb16d86082e43c5da \
        "$archive"
    extract "$archive" "$srcdir/e2fsprogs"
}

build() {
    log "Configuring E2fsprogs"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/e2fsprogs/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --with-root-prefix=/usr \
            --enable-elf-shlibs \
            --disable-uuidd \
            --disable-fuse2fs \
            --disable-nls \
            --disable-rpath \
            --without-libarchive \
            --with-udev-rules-dir=/usr/lib/udev/rules.d \
            --with-systemd-unit-dir=no

    log "Building E2fsprogs"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" LDCONFIG=true install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local soname target
    local -a keep=(
        /usr/bin/dumpe2fs
        /usr/bin/e2fsck
        /usr/bin/e2image
        /usr/bin/e2label
        /usr/bin/fsck.ext2
        /usr/bin/fsck.ext3
        /usr/bin/fsck.ext4
        /usr/bin/mke2fs
        /usr/bin/mkfs.ext2
        /usr/bin/mkfs.ext3
        /usr/bin/mkfs.ext4
        /usr/bin/resize2fs
        /usr/bin/tune2fs
    )

    for soname in \
        libcom_err.so.2 \
        libe2p.so.2 \
        libext2fs.so.2; do
        target=$(readlink -- "$pkgdir/usr/lib/$soname")
        [[ -f "$pkgdir/usr/lib/$target" ]] || \
            die "E2fsprogs SONAME target is missing: $target"
        keep+=("/usr/lib/$soname" "/usr/lib/$target")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
