#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make pkg-config sha256sum tar
ensure_directories

package="dhcpcd-$DHCPCD_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"

prepare_package "$package"
download "https://github.com/NetworkConfiguration/dhcpcd/releases/download/v$DHCPCD_VERSION/$package.tar.xz" "$archive"
verify_sha256 "$DHCPCD_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

cd "$PACKAGE_SOURCE"
log "Configuring dhcpcd"
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    ./configure \
        --prefix=/usr --sbindir=/usr/bin \
        --libexecdir=/usr/lib/dhcpcd --sysconfdir=/etc \
        --localstatedir=/var --dbdir=/var/lib/dhcpcd \
        --rundir=/run/dhcpcd --mandir=/usr/share/man \
        --enable-privsep --privsepuser=dhcpcd \
        --disable-auth --with-udev

log "Building dhcpcd"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
rm -rf "$PACKAGE_STAGING/usr/share/man"
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
