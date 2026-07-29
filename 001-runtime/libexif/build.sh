#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make sha256sum tar
ensure_directories

package="libexif-$LIBEXIF_VERSION"
recipe_inputs=("$ROOT/001-runtime/config.sh")
if binary_package_restore_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"; then
    exit 0
fi

archive="$EFILINUX_DOWNLOADS/$package.tar.xz"
prepare_package "$package"
download \
    "https://github.com/libexif/libexif/releases/download/v$LIBEXIF_VERSION/$package.tar.xz" \
    "$archive"
verify_sha256 "$LIBEXIF_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring libexif"
(
    cd "$PACKAGE_BUILD"
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
        "$PACKAGE_SOURCE/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --disable-static \
        --disable-docs
)
log "Building libexif"
make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 -name '*.la' -delete

binary_package_publish_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
