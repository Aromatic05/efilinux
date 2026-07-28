#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make pkg-config sha256sum tar
ensure_directories
package="userspace-rcu-$USERSPACE_RCU_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.bz2"
prepare_package "$package"
download "https://lttng.org/files/urcu/$package.tar.bz2" "$archive"
verify_sha256 "$USERSPACE_RCU_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring Userspace RCU"
cd "$PACKAGE_BUILD"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    "$PACKAGE_SOURCE/configure" --prefix=/usr --libdir=/usr/lib --disable-static
log "Building Userspace RCU"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
merge_sysroot "$PACKAGE_STAGING"
