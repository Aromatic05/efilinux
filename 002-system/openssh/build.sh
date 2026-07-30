#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=openssh
pkgver=10.4p1
sysroot=false

depends=(glibc libxcrypt linux-pam openssl zlib)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/openssh-$pkgver.tar.gz"

    download \
        "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 ef6026dd2aea8d56059638d5d3262902c892ceba9f88395835e0d06d3fb63238 "$archive"
    extract "$archive" "$srcdir/openssh"
}

build() {
    cd "$srcdir/openssh"
    log "Configuring OpenSSH"
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    ac_cv_search_SHA256Update=no \
        ./configure \
            --prefix=/usr \
            --sysconfdir=/etc/ssh \
            --libexecdir=/usr/lib/ssh \
            --localstatedir=/var \
            --with-privsep-path=/var/empty \
            --with-privsep-user=sshd \
            --with-pam \
            --with-zlib="$EFILINUX_SYSROOT/usr" \
            --with-ssl-dir="$EFILINUX_SYSROOT/usr" \
            --without-openssl-header-check \
            --without-ldns \
            --without-libedit \
            --without-kerberos5 \
            --with-sandbox=seccomp_filter \
            --without-security-key-builtin

    log "Building OpenSSH"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" install-nokeys
}

devel() {
    rm -rf "$develdir/usr/share/man"
    if [[ -d "$develdir/usr/sbin" ]]; then
        install -d -m0755 "$develdir/usr/bin"
        mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/usr/sbin"
    fi
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    package_keep \
        /etc/ssh/ssh_config \
        /etc/ssh/moduli \
        /usr/bin/scp \
        /usr/bin/sftp \
        /usr/bin/ssh \
        /usr/bin/ssh-add \
        /usr/bin/ssh-agent \
        /usr/bin/ssh-keygen \
        /usr/bin/ssh-keyscan \
        /usr/bin/sshd \
        /usr/lib/ssh/
}

recipe_main "$@"
