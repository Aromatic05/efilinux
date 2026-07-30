#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=iputils
pkgver=20250605
sysroot=false

depends=(glibc libcap)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)

package_capability /usr/bin/ping cap_net_raw=ep
package_capability /usr/bin/arping cap_net_raw=ep

prepare() {
    local archive="$downloaddir/iputils-$pkgver.tar.xz"

    download \
        "https://github.com/iputils/iputils/releases/download/$pkgver/iputils-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 6f213700dbf96b5cc4499ca70cb15ecd69c09f405b06785bb4a1a10b572b6276 "$archive"
    extract "$archive" "$srcdir/iputils"
}

build() {
    log "Configuring iputils"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/iputils" \
            --prefix=/usr \
            --sbindir=bin \
            --buildtype=release \
            -DUSE_CAP=true \
            -DUSE_IDN=false \
            -DUSE_GETTEXT=false \
            -DBUILD_ARPING=true \
            -DBUILD_CLOCKDIFF=false \
            -DBUILD_PING=true \
            -DBUILD_TRACEPATH=true \
            -DBUILD_MANS=false \
            -DBUILD_HTML_MANS=false \
            -DNO_SETCAP_OR_SUID=true \
            -DINSTALL_SYSTEMD_UNITS=false \
            -DSKIP_TESTS=true

    log "Building iputils"
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    strip_all "$develdir/usr/bin"
}

package() {
    package_keep \
        /usr/bin/ping \
        /usr/bin/arping \
        /usr/bin/tracepath
}

recipe_main "$@"
