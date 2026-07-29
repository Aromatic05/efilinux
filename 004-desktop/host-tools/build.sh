#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/004-desktop/config.sh"
source "$ROOT/lib/common.sh"

require_command curl make perl sha256sum tar
ensure_directories

prefix="$EFILINUX_BUILD/host-tools/intltool-$INTLTOOL_VERSION"
if [[ -x "$prefix/bin/intltool-update" ]]; then
    exit 0
fi

archive="$EFILINUX_DOWNLOADS/intltool-$INTLTOOL_VERSION.tar.gz"
source_directory="$EFILINUX_BUILD/sources/intltool-$INTLTOOL_VERSION"
build_directory="$EFILINUX_BUILD/host-intltool-$INTLTOOL_VERSION"

download \
    "https://distfiles.macports.org/intltool/intltool-$INTLTOOL_VERSION.tar.gz" \
    "$archive"
verify_sha256 "$INTLTOOL_SHA256" "$archive"
reset_directory "$source_directory"
extract_source "$archive" "$source_directory"
reset_directory "$build_directory"

log "Building host intltool $INTLTOOL_VERSION"
(
    cd "$build_directory"
    "$source_directory/configure" --prefix="$prefix"
)
make -C "$build_directory" -j"$EFILINUX_JOBS"
make -C "$build_directory" install
