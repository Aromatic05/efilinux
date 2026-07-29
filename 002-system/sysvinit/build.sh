#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make sha256sum tar
ensure_directories
package="sysvinit-$SYSVINIT_VERSION"
if binary_package_reuse "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download "https://github.com/slicer69/sysvinit/releases/download/$SYSVINIT_VERSION/$package.tar.xz" "$archive"
verify_sha256 "$SYSVINIT_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Building SysVinit"
make -C "$PACKAGE_SOURCE/src" -j"$EFILINUX_JOBS" \
    CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)"
make -C "$PACKAGE_SOURCE/src" ROOT="$PACKAGE_STAGING" install
binary_package_publish_staging "$package" "${BASH_SOURCE[0]}"
