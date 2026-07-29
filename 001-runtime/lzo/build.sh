#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make sha256sum tar
ensure_directories
package="lzo-$LZO_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"
download "https://www.oberhumer.com/opensource/lzo/download/$package.tar.gz" "$archive"
verify_sha256 "$LZO_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring LZO"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --libdir=/usr/lib \
        --enable-shared --disable-static
log "Building LZO"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
rm -f "$PACKAGE_STAGING/usr/lib"/*.la
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
