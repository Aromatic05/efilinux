#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories

package="iputils-$IPUTILS_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"

prepare_package "$package"
download "https://github.com/iputils/iputils/releases/download/$IPUTILS_VERSION/$package.tar.xz" "$archive"
verify_sha256 "$IPUTILS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring iputils"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
        --prefix=/usr --sbindir=bin --buildtype=release \
        -DUSE_CAP=true -DUSE_IDN=false -DUSE_GETTEXT=false \
        -DBUILD_ARPING=true -DBUILD_CLOCKDIFF=false \
        -DBUILD_PING=true -DBUILD_TRACEPATH=true \
        -DBUILD_MANS=false -DBUILD_HTML_MANS=false \
        -DNO_SETCAP_OR_SUID=true -DINSTALL_SYSTEMD_UNITS=false \
        -DSKIP_TESTS=true

log "Building iputils"
meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"
merge_sysroot "$PACKAGE_STAGING"
