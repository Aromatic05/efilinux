#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl tar sha256sum
ensure_directories

archive="$EFILINUX_DOWNLOADS/wireless-regdb-$WIRELESS_REGDB_VERSION.tar.xz"
source_directory="$EFILINUX_BUILD/sources/wireless-regdb-$WIRELESS_REGDB_VERSION"
firmware_root="$EFILINUX_ROOTFS/usr/lib/firmware"

[[ -d "$EFILINUX_ROOTFS" ]] || die "target rootfs has not been built"

download \
    "https://www.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-$WIRELESS_REGDB_VERSION.tar.xz" \
    "$archive"
verify_sha256 "$WIRELESS_REGDB_SHA256" "$archive"
extract_source "$archive" "$source_directory"

mkdir -p "$firmware_root"
install -m 0644 "$source_directory/regulatory.db" "$firmware_root/regulatory.db"
install -m 0644 "$source_directory/regulatory.db.p7s" "$firmware_root/regulatory.db.p7s"
