#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar make md5sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/linux-$LINUX_VERSION.tar.xz"
source_directory="$EFILINUX_BUILD/sources/linux-$LINUX_VERSION-headers"

download \
    "https://www.kernel.org/pub/linux/kernel/v${LINUX_VERSION%%.*}.x/linux-$LINUX_VERSION.tar.xz" \
    "$archive"
verify_md5 "$LINUX_MD5" "$archive"
extract_source "$archive" "$source_directory"

log "Installing Linux UAPI headers"
make -C "$source_directory" mrproper
make -C "$source_directory" headers
find "$source_directory/usr/include" -type f ! -name '*.h' -delete
mkdir -p "$EFILINUX_SYSROOT/usr"
rm -rf "$EFILINUX_SYSROOT/usr/include"
cp -a "$source_directory/usr/include" "$EFILINUX_SYSROOT/usr/"
