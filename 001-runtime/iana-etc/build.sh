#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl sha256sum tar
ensure_directories
package="iana-etc-$IANA_ETC_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
prepare_package "$package"
download "https://github.com/Mic92/iana-etc/releases/download/$IANA_ETC_VERSION/$package.tar.gz" "$archive"
verify_sha256 "$IANA_ETC_SHA256" "$archive"
extract_source "$archive" "$PACKAGE_SOURCE"
mkdir -p "$PACKAGE_STAGING/etc"
install -m 0644 "$PACKAGE_SOURCE/protocols" "$PACKAGE_STAGING/etc/protocols"
install -m 0644 "$PACKAGE_SOURCE/services" "$PACKAGE_STAGING/etc/services"
merge_sysroot "$PACKAGE_STAGING"
