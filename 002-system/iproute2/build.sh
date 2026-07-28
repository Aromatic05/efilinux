#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make pkg-config sha256sum tar
ensure_directories

package="iproute2-$IPROUTE2_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"

prepare_package "$package"
download "https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/$package.tar.xz" "$archive"
verify_sha256 "$IPROUTE2_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
cp -a "$PACKAGE_SOURCE/." "$PACKAGE_BUILD/"

cd "$PACKAGE_BUILD"
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    ./configure

log "Building iproute2"
make -j"$EFILINUX_JOBS" \
    PREFIX=/usr SBINDIR=/usr/bin LIBDIR=/usr/lib \
    CONFDIR=/etc/iproute2 NETNS_RUN_DIR=/run/netns
make DESTDIR="$PACKAGE_STAGING" install \
    PREFIX=/usr SBINDIR=/usr/bin LIBDIR=/usr/lib \
    CONFDIR=/etc/iproute2 NETNS_RUN_DIR=/run/netns
rm -rf "$PACKAGE_STAGING/usr/share/man" "$PACKAGE_STAGING/usr/share/doc"
merge_sysroot "$PACKAGE_STAGING"
