#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make pkg-config sha256sum tar
ensure_directories

package="openssh-$OPENSSH_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"

prepare_package "$package"
download "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/$package.tar.gz" "$archive"
verify_sha256 "$OPENSSH_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

cd "$PACKAGE_SOURCE"
log "Configuring OpenSSH"
CC=gcc CFLAGS="$(target_cflags)" CPPFLAGS="--sysroot=$EFILINUX_SYSROOT" \
LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
ac_cv_search_SHA256Update=no \
    ./configure \
        --prefix=/usr --sysconfdir=/etc/ssh \
        --libexecdir=/usr/lib/ssh --localstatedir=/var \
        --with-privsep-path=/var/empty --with-privsep-user=sshd \
        --with-pam --with-zlib="$EFILINUX_SYSROOT/usr" \
        --with-ssl-dir="$EFILINUX_SYSROOT/usr" \
        --without-openssl-header-check --without-ldns \
        --without-libedit --without-kerberos5 \
        --with-sandbox=seccomp_filter --without-security-key-builtin

log "Building OpenSSH"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install-nokeys
rm -rf "$PACKAGE_STAGING/usr/share/man"
merge_sysroot "$PACKAGE_STAGING"
