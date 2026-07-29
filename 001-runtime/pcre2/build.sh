#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make sha256sum tar
ensure_directories

package="pcre2-$PCRE2_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.bz2"
prepare_package "$package"

download \
    "https://github.com/PCRE2Project/pcre2/releases/download/$package/$package.tar.bz2" \
    "$archive"
verify_sha256 "$PCRE2_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring PCRE2"
cd "$PACKAGE_BUILD"
CC=gcc \
CFLAGS="$(target_cflags)" \
LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" \
    --prefix=/usr \
    --libdir=/usr/lib \
    --disable-static \
    --disable-pcre2-16 \
    --disable-pcre2-32 \
    --enable-jit

log "Building PCRE2"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
rm -f "$PACKAGE_STAGING/usr/lib"/*.la
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
