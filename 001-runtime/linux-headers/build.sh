#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

ensure_directories
package="linux-headers-$LINUX_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi

require_command curl make md5sum tar
prepare_package "$package"
archive="$EFILINUX_DOWNLOADS/linux-$LINUX_VERSION.tar.xz"

download \
    "https://www.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-$LINUX_VERSION.tar.xz" \
    "$archive"
verify_md5 "$LINUX_MD5" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Installing Linux UAPI headers"
make -C "$PACKAGE_SOURCE" mrproper
make -C "$PACKAGE_SOURCE" headers
find "$PACKAGE_SOURCE/usr/include" -type f ! -name '*.h' -delete
mkdir -p "$PACKAGE_STAGING/usr"
cp -a "$PACKAGE_SOURCE/usr/include" "$PACKAGE_STAGING/usr/"

binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
