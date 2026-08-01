#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=linux-pam
pkgver=1.7.2

depends=(glibc libxcrypt openssl)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)

prepare() {
    local archive="$downloaddir/Linux-PAM-$pkgver.tar.xz"
    download \
        "https://github.com/linux-pam/linux-pam/releases/download/v$pkgver/Linux-PAM-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 3d86b6383fb5fd9eb9578d2cd47d92801191f4bf3f9bc61419bfefc8aa1e531a "$archive"
    extract "$archive" "$srcdir/linux-pam"
}

build() {
    log "Configuring Linux-PAM"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/linux-pam" \
            --prefix=/usr \
            --libdir=lib \
            --buildtype=release \
            -Di18n=disabled \
            -Ddocs=disabled \
            -Daudit=disabled \
            -Deconf=disabled \
            -Dlogind=disabled \
            -Delogind=disabled \
            -Dopenssl=enabled \
            -Dpwaccess=disabled \
            -Dselinux=disabled \
            -Dnis=disabled \
            -Dexamples=false \
            -Dxtests=false \
            -Dpam_userdb=disabled \
            -Dpam_unix=enabled

    log "Building Linux-PAM"
    meson compile -C "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" meson install -C "$builddir"
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
    if [[ -d "$develdir/usr/sbin" ]]; then
        install -d -m0755 "$develdir/usr/bin"
        mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/usr/sbin"
    fi
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
    chmod 4755 "$develdir/usr/bin/unix_chkpwd"
}

package() {
    rm -f \
        "$pkgdir/usr/lib/security/pam_debug.so" \
        "$pkgdir/usr/lib/security/pam_stress.so"

    local -a keep=(
        /usr/bin/faillock
        /usr/bin/unix_chkpwd
        /usr/lib/security/
    )
    package_add_library_family keep 'libpam.so.0*'
    package_add_library_family keep 'libpam_misc.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
