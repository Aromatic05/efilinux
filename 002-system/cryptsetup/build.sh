#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=cryptsetup
pkgver=2.8.7

depends=(device-mapper glibc json-c openssl popt udev util-linux)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/cryptsetup-$pkgver.tar.xz"
    download \
        "https://www.kernel.org/pub/linux/utils/cryptsetup/v2.8/cryptsetup-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 e776f0d381e86ca61042c457069491fe8e0ac286780c7c3b1e4f9921abc961da "$archive"
    extract "$archive" "$srcdir/cryptsetup"
}

build() {
    cd "$builddir"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        "$srcdir/cryptsetup/configure" \
            --prefix=/usr \
            --libdir=/usr/lib \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static \
            --disable-asciidoc \
            --disable-external-tokens \
            --disable-ssh-token \
            --disable-luks2-reencryption \
            --disable-fips \
            --disable-pwquality \
            --disable-passwdqc \
            --disable-selinux \
            --disable-veritysetup \
            --disable-integritysetup \
            --enable-keyring \
            --enable-udev \
            --enable-blkid \
            --with-crypto_backend=openssl \
            --enable-internal-argon2 \
            --disable-libargon2 \
            --with-tmpfilesdir=no
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install
}

devel() {
    rm -rf "$develdir/usr/lib/systemd"
    if [[ -d "$develdir/usr/sbin" ]]; then
        install -d -m0755 "$develdir/usr/bin"
        mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/usr/sbin"
    fi
    find "$develdir" -type f -name '*.la' -delete
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/bin/cryptsetup)
    package_add_library_family keep 'libcryptsetup.so.12*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
