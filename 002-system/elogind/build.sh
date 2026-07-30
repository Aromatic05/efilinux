#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=elogind
pkgver=257.16

depends=(acl dbus glibc libcap linux-pam util-linux)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/elogind-$pkgver.tar.gz"
    download \
        "https://github.com/elogind/elogind/archive/refs/tags/v$pkgver.tar.gz" \
        "$archive"
    checksum sha256 3c8146409bfb9daa77f272212c2b0bf0ae727c782ec87ece0d2d25e0e5bf5f4c "$archive"
    extract "$archive" "$srcdir/elogind"
}

build() {
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/elogind" \
            --prefix=/usr \
            --libdir=lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --buildtype=release \
            --wrap-mode=nodownload \
            -Dmode=release \
            -Dsplit-bin=true \
            -Dstatic-libelogind=false \
            -Dsysvinit-path=/etc/rc.d/init.d \
            -Dsysvrcnd-path=/etc/rc.d \
            -Dudevrulesdir=/usr/lib/udev/rules.d \
            -Ddbuspolicydir=/usr/share/dbus-1/system.d \
            -Ddbussystemservicedir=/usr/share/dbus-1/system-services \
            -Dpkgconfiglibdir=/usr/lib/pkgconfig \
            -Dpamlibdir=/usr/lib/security \
            -Dpamconfdir=/etc/pam.d \
            -Dhalt-path=/usr/bin/halt \
            -Dpoweroff-path=/usr/bin/poweroff \
            -Dreboot-path=/usr/bin/reboot \
            -Dnss-elogind=true \
            -Duserdb=false \
            -Dvarlink=true \
            -Defi=false \
            -Dman=disabled \
            -Dhtml=disabled \
            -Dtranslations=false \
            -Dselinux=disabled \
            -Dsmack=false \
            -Dpolkit=enabled \
            -Dacl=enabled \
            -Daudit=disabled \
            -Dpam=enabled \
            -Ddbus=enabled \
            -Dutmp=true \
            -Ddefault-hierarchy=unified
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/libexec"
}

package() {
    local -a keep=(
        /etc/elogind/
        /usr/bin/loginctl
        /usr/bin/elogind-inhibit
        /usr/libexec/elogind
        /usr/libexec/elogind-cgroups-agent
        /usr/libexec/elogind-uaccess-command
        /usr/lib/security/pam_elogind.so
        /usr/lib/elogind/
        /usr/lib/udev/rules.d/
        /usr/share/dbus-1/
        /usr/share/polkit-1/
    )
    package_add_library_family keep 'libelogind.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
