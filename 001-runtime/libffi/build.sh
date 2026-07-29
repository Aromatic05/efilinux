#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make sha256sum tar
ensure_directories

package="libffi-$LIBFFI_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"

download \
    "https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/$package.tar.gz" \
    "$archive"
verify_sha256 "$LIBFFI_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring libffi"
cd "$PACKAGE_BUILD"
CC=gcc \
CFLAGS="$(target_cflags)" \
LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" \
    --prefix=/usr \
    --libdir=/usr/lib \
    --disable-static \
    --disable-docs

log "Building libffi"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
rm -f "$PACKAGE_STAGING/usr/lib"/*.la
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
