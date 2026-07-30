#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=cronie
pkgver=1.7.2
sysroot=false

depends=(glibc linux-pam)
builddepends=(linux-headers)
makedepends=(gcc make patch pkg-config)

prepare() {
    local archive="$downloaddir/cronie-$pkgver.tar.gz"

    download \
        "https://github.com/cronie-crond/cronie/releases/download/cronie-$pkgver/cronie-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 f1da374a15ba7605cf378347f96bc8b678d3d7c0765269c8242cfe5b0789c571 "$archive"
    extract "$archive" "$srcdir/cronie"
    input_file \
        "$recipedir/patches/0001-complete-load-entry-error-callback-prototype.patch" \
        "$srcdir/load-entry-error-callback.patch"
}

build() {
    patch -d "$srcdir/cronie" -Np1 < "$srcdir/load-entry-error-callback.patch"

    log "Configuring Cronie"
    cd "$builddir"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/cronie/configure" \
            --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --runstatedir=/run \
            --enable-syscrontab \
            --disable-anacron \
            --with-inotify \
            --with-pam \
            --without-selinux \
            --without-audit

    log "Building Cronie"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
    install -Dm0644 "$srcdir/cronie/pam/crond" "$develdir/etc/pam.d/crond"
}

devel() {
    if [[ -d "$develdir/usr/sbin" ]]; then
        install -d -m0755 "$develdir/usr/bin"
        mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/usr/sbin"
    fi
    chmod 4755 "$develdir/usr/bin/crontab"
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/crond \
        /usr/bin/crontab \
        /usr/bin/cronnext
}

recipe_main "$@"
