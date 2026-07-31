#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=util-linux
pkgver=2.42.2

depends=(
    glibc
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
    local archive="$downloaddir/util-linux-$pkgver.tar.xz"

    download \
        "https://www.kernel.org/pub/linux/utils/util-linux/v${pkgver%.*}/util-linux-$pkgver.tar.xz" \
        "$archive"
    checksum \
        sha256 \
        03a05d3adf9602ef128f2da05b84b3205ce60c351e5737c0370f74000679ce8a \
        "$archive"
    extract "$archive" "$srcdir/util-linux"
}

build() {
    log "Configuring Util-linux"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/util-linux/configure" \
            --prefix=/usr \
            --bindir=/usr/bin \
            --sbindir=/usr/bin \
            --libdir=/usr/lib \
            --runstatedir=/run \
            --sysconfdir=/etc \
            --disable-static \
            --disable-chfn-chsh \
            --disable-login \
            --disable-nologin \
            --disable-su \
            --disable-runuser \
            --disable-pylibmount \
            --disable-makeinstall-chown \
            --disable-makeinstall-setuid \
            --without-python \
            --without-systemd \
            --without-udev \
            --without-ncursesw \
            --without-tinfo \
            --without-readline \
            --without-selinux \
            --without-audit \
            --without-cap-ng \
            --without-cryptsetup \
            --without-btrfs \
            --enable-rfkill

    log "Building Util-linux"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    for program in partx rfkill; do
        if [[ -e "$develdir/usr/sbin/$program" ]]; then
            mkdir -p "$develdir/usr/bin"
            mv "$develdir/usr/sbin/$program" "$develdir/usr/bin/$program"
        fi
    done
    if [[ -d "$develdir/usr/sbin" && -z $(find "$develdir/usr/sbin" -mindepth 1 -print -quit) ]]; then
        rmdir "$develdir/usr/sbin"
    fi
    strip_all \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    local soname target
    local -a keep=(
        /usr/bin/agetty
        /usr/bin/blockdev
        /usr/bin/blkid
        /usr/bin/dmesg
        /usr/bin/fdisk
        /usr/bin/kill
        /usr/bin/logger
        /usr/bin/setsid
        /usr/bin/findmnt
        /usr/bin/fsck
        /usr/bin/hwclock
        /usr/bin/losetup
        /usr/bin/lsblk
        /usr/bin/mcookie
        /usr/bin/mkfs
        /usr/bin/mkswap
        /usr/bin/mount
        /usr/bin/mountpoint
        /usr/bin/partx
        /usr/bin/rfkill
        /usr/bin/sfdisk
        /usr/bin/swapoff
        /usr/bin/swapon
        /usr/bin/umount
        /usr/bin/wipefs
    )

    for soname in \
        libblkid.so.1 \
        libfdisk.so.1 \
        libmount.so.1 \
        libsmartcols.so.1 \
        libuuid.so.1; do
        target=$(readlink -- "$pkgdir/usr/lib/$soname")
        [[ -f "$pkgdir/usr/lib/$target" ]] || \
            die "Util-linux SONAME target is missing: $target"
        keep+=("/usr/lib/$soname" "/usr/lib/$target")
    done

    package_keep "${keep[@]}"
}

recipe_main "$@"
