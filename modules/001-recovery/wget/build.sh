#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=wget
pkgver=1.25.0
depends=(glibc openssl pcre2 zlib)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/wget-$pkgver.tar.gz"
    local ca_bundle="$downloaddir/cacert-2026-07-16.pem"

    download "https://ftp.gnu.org/gnu/wget/wget-$pkgver.tar.gz" "$archive"
    checksum sha256 \
        766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784 \
        "$archive"
    download "https://curl.se/ca/cacert-2026-07-16.pem" "$ca_bundle"
    checksum sha256 \
        3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91 \
        "$ca_bundle"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/cookie-header-overflow.patch" \
        "$srcdir/cookie-header-overflow.patch"
    input_file "$recipedir/files/reproducible-build-info.patch" \
        "$srcdir/reproducible-build-info.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -Np1 -i "$srcdir/cookie-header-overflow.patch"
    patch -d "$srcdir/source" -Np1 -i "$srcdir/reproducible-build-info.patch"
    cp "$ca_bundle" "$srcdir/cacert.pem"
}

build() {
    local config_root=/opt/efilinux/modules/recovery/etc/wget
    local ca_root=/opt/efilinux/modules/recovery/share/ca-certificates
    local mapped_source=/usr/src/wget-$pkgver

    CFLAGS+=" -ffile-prefix-map=$srcdir/source=$mapped_source"
    CFLAGS+=" -fmacro-prefix-map=$srcdir/source=$mapped_source"
    export CFLAGS

    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --sysconfdir="$config_root" \
        --disable-debug \
        --disable-nls \
        --disable-iri \
        --disable-opie \
        --without-libpsl \
        --without-libssl-prefix \
        --with-ssl=openssl \
        --with-zlib
    make -C "$builddir/lib" -j"$EFILINUX_JOBS"
    make -C "$builddir/src" -j"$EFILINUX_JOBS"
    install -Dm0755 "$builddir/src/wget" "$develdir/usr/bin/wget"

    install -Dm0644 "$srcdir/cacert.pem" \
        "$develdir$ca_root/cacert.pem"
    install -d -m0755 "$develdir$config_root"
    cat > "$develdir$config_root/wgetrc" <<WGETRC
ca_certificate = $ca_root/cacert.pem
check_certificate = on
WGETRC
}

devel() {
    strip_all "$develdir/usr/bin/wget"
}

package() {
    package_keep \
        /usr/bin/wget \
        /opt/efilinux/modules/recovery/etc/wget/wgetrc \
        /opt/efilinux/modules/recovery/share/ca-certificates/cacert.pem
}

recipe_main "$@"
