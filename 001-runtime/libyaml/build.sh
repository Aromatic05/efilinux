#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/001-runtime/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command curl gcc make sha256sum tar
ensure_directories

package="libyaml-$LIBYAML_VERSION"
recipe_inputs=("$ROOT/001-runtime/config.sh")
if binary_package_restore_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"; then
    exit 0
fi

archive="$EFILINUX_DOWNLOADS/yaml-$LIBYAML_VERSION.tar.gz"
prepare_package "$package"
download "https://pyyaml.org/download/libyaml/yaml-$LIBYAML_VERSION.tar.gz" "$archive"
verify_sha256 "$LIBYAML_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"

log "Configuring libyaml"
(
    cd "$PACKAGE_BUILD"
    CC=gcc \
    CFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
        "$PACKAGE_SOURCE/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        --disable-static
)
log "Building libyaml"
make -C "$PACKAGE_BUILD" -j"$EFILINUX_JOBS"
make -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 -name '*.la' -delete

binary_package_publish_sysroot \
    "$package" "${BASH_SOURCE[0]}" "${recipe_inputs[@]}"
