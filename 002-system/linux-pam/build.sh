#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories
package="Linux-PAM-$LINUX_PAM_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://github.com/linux-pam/linux-pam/releases/download/v$LINUX_PAM_VERSION/$package.tar.xz" "$archive"
verify_sha256 "$LINUX_PAM_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring Linux-PAM"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
        --prefix=/usr --libdir=lib --buildtype=release \
        -Di18n=disabled -Ddocs=disabled -Daudit=disabled \
        -Deconf=disabled -Dlogind=disabled -Delogind=disabled \
        -Dopenssl=enabled -Dpwaccess=disabled -Dselinux=disabled \
        -Dnis=disabled -Dexamples=false -Dxtests=false \
        -Dpam_userdb=disabled -Dpam_unix=enabled
log "Building Linux-PAM"
meson compile -C "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" meson install -C "$PACKAGE_BUILD"
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
merge_sysroot "$PACKAGE_STAGING"
