#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl sha256sum tar
ensure_directories

archive="$EFILINUX_DOWNLOADS/sof-bin-$SOF_FIRMWARE_VERSION.tar.gz"
source_directory="$EFILINUX_BUILD/sources/sof-bin-$SOF_FIRMWARE_VERSION"
firmware_root="$EFILINUX_ROOTFS/usr/lib/firmware/intel"

[[ -d "$EFILINUX_ROOTFS/usr/lib/modules/$LINUX_VERSION" ]] || \
    die "kernel modules must be built before SOF firmware"

download \
    "https://github.com/thesofproject/sof-bin/releases/download/v$SOF_FIRMWARE_VERSION/sof-bin-$SOF_FIRMWARE_VERSION.tar.gz" \
    "$archive"
verify_sha256 "$SOF_FIRMWARE_SHA256" "$archive"
extract_source "$archive" "$source_directory"

log "Installing signed SOF firmware and topology data"
for directory in \
    sof \
    sof-ipc4 \
    sof-ipc4-lib \
    sof-ipc4-tplg \
    sof-tplg; do
    [[ -d "$source_directory/$directory" ]] || \
        die "SOF archive is missing directory: $directory"
    rm -rf "$firmware_root/$directory"
    cp -a "$source_directory/$directory" "$firmware_root/$directory"
done

rm -f "$firmware_root/sof-ace-tplg"
ln -s sof-ipc4-tplg "$firmware_root/sof-ace-tplg"
