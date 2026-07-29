#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make perl sha256sum tar
ensure_directories
package="openssl-$OPENSSL_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"
download "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/$package.tar.gz" "$archive"
verify_sha256 "$OPENSSL_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
log "Configuring OpenSSL"
cd "$PACKAGE_SOURCE"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
    ./Configure linux-x86_64 --prefix=/usr --openssldir=/etc/ssl --libdir=lib \
        shared zlib no-tests no-docs
log "Building OpenSSL"
make -j"$EFILINUX_JOBS"
make DESTDIR="$PACKAGE_STAGING" install_sw install_ssldirs
find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 \( -name '*.a' -o -name '*.la' \) -delete
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
