#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl find sha256sum tar
ensure_directories

package="sof-firmware-$SOF_FIRMWARE_VERSION"
producer=${BASH_SOURCE[0]}
archive="$EFILINUX_DOWNLOADS/sof-bin-$SOF_FIRMWARE_VERSION.tar.gz"

[[ -d "$EFILINUX_ROOTFS/usr/lib/modules/$LINUX_VERSION" ]] || \
    die "kernel modules must be built before SOF firmware"
set_package_paths "$package"

if binary_package_extract "$package" "$PACKAGE_STAGING" "$producer"; then
    log "Using binary package $(basename -- "$PACKAGE_ARCHIVE")"
else
    download \
        "https://github.com/thesofproject/sof-bin/releases/download/v$SOF_FIRMWARE_VERSION/sof-bin-$SOF_FIRMWARE_VERSION.tar.gz" \
        "$archive"
    verify_sha256 "$SOF_FIRMWARE_SHA256" "$archive"
    prepare_package "$package"
    extract_source "$archive" "$PACKAGE_SOURCE"

    firmware_staging="$PACKAGE_STAGING/usr/lib/firmware/intel"
    mkdir -p "$firmware_staging"
    log "Installing signed SOF firmware and topology data"
    for directory in \
        sof \
        sof-ipc4 \
        sof-ipc4-lib \
        sof-ipc4-tplg \
        sof-tplg; do
        [[ -d "$PACKAGE_SOURCE/$directory" ]] || \
            die "SOF archive is missing directory: $directory"
        cp -a "$PACKAGE_SOURCE/$directory" "$firmware_staging/$directory"
    done

    # Signed images are the runtime path; community and LDC data are for
    # development and firmware-log decoding.
    find "$firmware_staging" -type d -name community -prune -exec rm -rf -- {} +
    find "$firmware_staging" -type f -name '*.ldc' -delete
    find -L "$firmware_staging" -type l -delete
    ln -s sof-ipc4-tplg "$firmware_staging/sof-ace-tplg"

    binary_package_create "$package" "$PACKAGE_STAGING" "$producer"
fi

install_rootfs_tree \
    "$package" "$PACKAGE_STAGING/usr/lib/firmware/intel" /usr/lib/firmware/intel
rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
