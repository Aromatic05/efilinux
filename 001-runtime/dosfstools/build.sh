#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make sha256sum tar
ensure_directories
package="dosfstools-$DOSFSTOOLS_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"
download "https://github.com/dosfstools/dosfstools/releases/download/v$DOSFSTOOLS_VERSION/$package.tar.gz" "$archive"
verify_sha256 "$DOSFSTOOLS_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring dosfstools"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
        --disable-nls
log "Building dosfstools"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
