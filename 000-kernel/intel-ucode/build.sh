#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command curl sha256sum tar
ensure_directories

archive="$EFILINUX_DOWNLOADS/intel-microcode-$INTEL_UCODE_VERSION.tar.gz"
source_directory="$EFILINUX_BUILD/sources/intel-microcode-$INTEL_UCODE_VERSION"
firmware_root="$EFILINUX_ROOTFS/usr/lib/firmware/intel-ucode"

[[ -d "$EFILINUX_ROOTFS" ]] || die "target rootfs has not been built"

download \
    "https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/archive/refs/tags/microcode-$INTEL_UCODE_VERSION.tar.gz" \
    "$archive"
verify_sha256 "$INTEL_UCODE_SHA256" "$archive"
extract_source "$archive" "$source_directory"

reset_directory "$firmware_root"
cp -a "$source_directory/intel-ucode/." "$firmware_root/"
cp -a "$source_directory/intel-ucode-with-caveats/." "$firmware_root/"
