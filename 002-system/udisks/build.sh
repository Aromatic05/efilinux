#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=udisks
pkgver=2.11.1

depends=(acl elogind glib glibc libblockdev libgudev polkit udev util-linux)
builddepends=(linux-headers)
makedepends=(autoreconf gcc gtkdocize make pkg-config)

prepare() {
    local archive="$downloaddir/udisks-$pkgver.tar.gz"
    download \
        "https://github.com/storaged-project/udisks/archive/refs/tags/udisks-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 e40ee20e1f24783f30109d7fd20553aeb93c4808ceb67a4c980bf698cfde32d6 "$archive"
    extract "$archive" "$srcdir/udisks"
}

build() {
    sed -i \
        -e 's|--sourcedir=$(top_srcdir) udisks-daemon-resources.xml|--sourcedir=$(top_srcdir) $(srcdir)/udisks-daemon-resources.xml|g' \
        "$srcdir/udisks/src/Makefile.am"
    (cd "$srcdir/udisks" && env -u srcdir NOCONFIGURE=1 ./autogen.sh)

    cd "$builddir"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/udisks/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static \
            --enable-daemon \
            --disable-man \
            --enable-acl \
            --disable-lvm2 \
            --disable-iscsi \
            --disable-btrfs \
            --disable-smart \
            --libexecdir=/usr/lib \
            --sbindir=/usr/bin \
            --with-udevdir=/usr/lib/udev \
            --with-systemdsystemunitdir=no \
            --with-tmpfilesdir=no \
            --with-modloaddir=no \
            --with-modprobedir=no
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir" -type f -name '*.la' -delete
    rm -f "$develdir/etc/udisks2/mount_options.conf.example"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/udisksctl
        /usr/lib/udisks2/
        /etc/udisks2/
        /usr/share/dbus-1/
        /usr/share/polkit-1/
        /usr/lib/udev/rules.d/
    )
    package_add_library_family keep 'libudisks2.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
