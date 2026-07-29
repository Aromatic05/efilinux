#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make patch pkg-config sha256sum tar
ensure_directories

package="cronie-$CRONIE_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"

prepare_package "$package"
download "https://github.com/cronie-crond/cronie/releases/download/cronie-$CRONIE_VERSION/$package.tar.gz" "$archive"
verify_sha256 "$CRONIE_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
patch -d "$PACKAGE_SOURCE" -Np1 < \
    "$ROOT/002-system/cronie/patches/0001-complete-load-entry-error-callback-prototype.patch"

log "Configuring Cronie"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    "$PACKAGE_SOURCE/configure" \
        --prefix=/usr --sysconfdir=/etc \
        --localstatedir=/var --runstatedir=/run \
        --enable-syscrontab --disable-anacron \
        --with-inotify --with-pam \
        --without-selinux --without-audit

log "Building Cronie"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install

install -d "$PACKAGE_STAGING/etc/pam.d"
install -m644 "$PACKAGE_SOURCE/pam/crond" "$PACKAGE_STAGING/etc/pam.d/crond"

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
