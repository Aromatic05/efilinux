#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=shadow
pkgver=4.19.3
sysroot=false

depends=(acl attr glibc libxcrypt linux-pam)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/shadow-$pkgver.tar.xz"
    download \
        "https://github.com/shadow-maint/shadow/releases/download/$pkgver/shadow-$pkgver.tar.xz" \
        "$archive"
    checksum sha256 11a8f358910712cf957dd4fd205063fce7e386b68fc7dfe3a0e1e53155ec53c5 "$archive"
    extract "$archive" "$srcdir/shadow"
}

build() {
    cd "$srcdir/shadow"
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    sed -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD YESCRYPT@' \
        -e 's@/var/spool/mail@/var/mail@' \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
        -i etc/login.defs

    log "Configuring Shadow"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        ./configure \
            --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static \
            --disable-logind \
            --disable-nls \
            --without-libbsd \
            --with-libpam \
            --without-nscd \
            --without-sssd \
            --with-bcrypt \
            --with-yescrypt

    log "Building Shadow"
    make -j"$EFILINUX_JOBS"
    make DESTDIR="$develdir" exec_prefix=/usr pamddir= install
}

devel() {
    find "$develdir/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true
    if [[ -d "$develdir/usr/sbin" ]]; then
        install -d -m0755 "$develdir/usr/bin"
        mv "$develdir/usr/sbin"/* "$develdir/usr/bin/"
        rmdir "$develdir/usr/sbin"
    fi
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    package_keep \
        /etc/login.defs \
        /usr/bin/chage \
        /usr/bin/chfn \
        /usr/bin/chsh \
        /usr/bin/expiry \
        /usr/bin/faillog \
        /usr/bin/gpasswd \
        /usr/bin/login \
        /usr/bin/newgrp \
        /usr/bin/passwd \
        /usr/bin/sg \
        /usr/bin/su \
        /usr/bin/chpasswd \
        /usr/bin/groupadd \
        /usr/bin/groupdel \
        /usr/bin/groupmod \
        /usr/bin/grpck \
        /usr/bin/grpconv \
        /usr/bin/grpunconv \
        /usr/bin/newusers \
        /usr/bin/nologin \
        /usr/bin/pwck \
        /usr/bin/pwconv \
        /usr/bin/pwunconv \
        /usr/bin/useradd \
        /usr/bin/userdel \
        /usr/bin/usermod \
        /usr/bin/vigr \
        /usr/bin/vipw
}

recipe_main "$@"
