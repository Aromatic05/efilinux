#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
package="zlib-$ZLIB_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi

require_command curl gcc make md5sum tar
prepare_package "$package"
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"

download "https://zlib.net/fossils/$package.tar.gz" "$archive"
verify_md5 "$ZLIB_MD5" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring zlib"
cd "$PACKAGE_SOURCE"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    ./configure --prefix=/usr --libdir=/usr/lib

log "Building zlib"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
