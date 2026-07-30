#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=glibc
pkgver=2.43

depends=()
builddepends=(
    linux-headers
)
makedepends=(
    bison
    g++
    gawk
    gcc
    make
    perl
    python3
)

prepare() {
    local archive="$downloaddir/glibc-$pkgver.tar.xz"

    download \
        "https://ftpmirror.gnu.org/glibc/glibc-$pkgver.tar.xz" \
        "$archive"
    checksum \
        md5 \
        7ec2588300b299215a65aec7e6afa04f \
        "$archive"
    extract "$archive" "$srcdir/glibc"
}

build() {
    local bootstrap_cflags="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic"

    log "Configuring glibc"
    cd "$builddir"
    CFLAGS="$bootstrap_cflags" \
    CXXFLAGS="$bootstrap_cflags" \
        "$srcdir/glibc/configure" \
            --prefix=/usr \
            --with-headers="$EFILINUX_SYSROOT/usr/include" \
            --enable-kernel=6.1 \
            --disable-werror \
            libc_cv_slibdir=/usr/lib

    log "Building glibc"
    CFLAGS="$bootstrap_cflags" \
    CXXFLAGS="$bootstrap_cflags" \
        make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install

    log "Generating compact English and Simplified Chinese locale archive"
    mkdir -p "$develdir/usr/lib/locale"
    for locale_name in en_US zh_CN; do
        env -u LD_PRELOAD -u LD_LIBRARY_PATH \
            I18NPATH="$develdir/usr/share/i18n" \
            "$develdir/usr/lib/ld-linux-x86-64.so.2" \
            --library-path "$develdir/usr/lib" \
            "$develdir/usr/bin/localedef" \
            --prefix="$develdir" \
            --no-archive \
            -i "$locale_name" \
            -f UTF-8 \
            "$locale_name.UTF-8"
    done

    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        I18NPATH="$develdir/usr/share/i18n" \
        "$develdir/usr/lib/ld-linux-x86-64.so.2" \
        --library-path "$develdir/usr/lib" \
        "$develdir/usr/bin/localedef" \
        --prefix="$develdir" \
        --add-to-archive \
        "$develdir/usr/lib/locale/en_US.utf8" \
        "$develdir/usr/lib/locale/zh_CN.utf8"
    rm -rf \
        "$develdir/usr/lib/locale/en_US.utf8" \
        "$develdir/usr/lib/locale/zh_CN.utf8"
}

devel() {
    strip_all \
        "$develdir/sbin" \
        "$develdir/usr/bin" \
        "$develdir/usr/lib"
}

package() {
    package_keep \
        /usr/bin/locale \
        /usr/lib/ld-linux-x86-64.so.2 \
        /usr/lib/libc.so.6 \
        /usr/lib/libdl.so.2 \
        /usr/lib/libm.so.6 \
        /usr/lib/libnss_dns.so.2 \
        /usr/lib/libnss_files.so.2 \
        /usr/lib/libpthread.so.0 \
        /usr/lib/libresolv.so.2 \
        /usr/lib/librt.so.1 \
        /usr/lib/locale/locale-archive
}

recipe_main "$@"
