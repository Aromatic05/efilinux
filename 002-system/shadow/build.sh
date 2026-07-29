#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="shadow-$SHADOW_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://github.com/shadow-maint/shadow/releases/download/$SHADOW_VERSION/$package.tar.xz" "$archive"
verify_sha256 "$SHADOW_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
cd "$PACKAGE_SOURCE"
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
sed -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD YESCRYPT@' \
    -e 's@/var/spool/mail@/var/mail@' \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
    -i etc/login.defs
log "Configuring Shadow"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    ./configure --prefix=/usr --sysconfdir=/etc --disable-static \
        --disable-logind --disable-nls --without-libbsd \
        --with-libpam --without-nscd --without-sssd \
        --with-bcrypt --with-yescrypt
log "Building Shadow"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" exec_prefix=/usr pamddir= install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
