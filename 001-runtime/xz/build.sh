#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
package="xz-$XZ_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi

require_command curl gcc make md5sum tar
prepare_package "$package"
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"

download \
    "https://github.com/tukaani-project/xz/releases/download/v$XZ_VERSION/$package.tar.xz" \
    "$archive"
verify_md5 "$XZ_MD5" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring XZ Utils"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --disable-static \
        --disable-doc \
        --disable-nls

log "Building XZ Utils"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
