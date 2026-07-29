#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make sha256sum tar
ensure_directories
package="libcap-$LIBCAP_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/$package.tar.xz" "$archive"
verify_sha256 "$LIBCAP_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Building Libcap"
make -C "$PACKAGE_SOURCE" -j"$EFILINUX_JOBS" BUILD_CC=gcc CC=gcc \
    CFLAGS="$(target_cflags) -fPIC" LDFLAGS="$(target_ldflags)" \
    prefix=/usr lib=lib PAM_CAP=no GOLANG=no RAISE_SETFCAP=no
make -C "$PACKAGE_SOURCE" DESTDIR="$PACKAGE_STAGING" prefix=/usr lib=lib \
    PAM_CAP=no GOLANG=no RAISE_SETFCAP=no install
rm -f "$PACKAGE_STAGING/usr/lib"/*.a
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
