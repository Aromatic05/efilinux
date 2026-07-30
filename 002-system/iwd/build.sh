#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=iwd
pkgver=3.12
sysroot=false

depends=(dbus ell glibc readline)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/iwd-$pkgver.tar.xz"
    download \
        "https://mirrors.edge.kernel.org/pub/linux/network/wireless/iwd-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 d89a5e45c7180170e19be828f9e944a768c593758094fc57a358d0e7c4cb1a49 "$archive"
    extract "$archive" "$srcdir/iwd"
}

build() {
    mkdir -p "$builddir/pkgconfig"
    cat > "$builddir/pkgconfig/tinfo.pc" <<'PC'
prefix=/usr
libdir=${prefix}/lib
Name: tinfo
Description: ncurses wide-character terminfo compatibility
Version: 6.6
Libs: -L${libdir} -lncursesw
PC

    cd "$builddir"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$builddir/pkgconfig:$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/iwd/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --libexecdir=/usr/lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --enable-daemon \
            --enable-client \
            --disable-monitor \
            --enable-dbus-policy \
            --with-dbus-datadir=/usr/share \
            --disable-systemd-service \
            --disable-manual-pages \
            --enable-external-ell \
            --disable-libedit \
            --disable-wired \
            --disable-hwsim \
            --disable-tools \
            --disable-ofono
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    find "$develdir" -type f -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    package_keep \
        /usr/bin/iwctl \
        /usr/lib/iwd \
        /usr/share/dbus-1/
}

recipe_main "$@"
