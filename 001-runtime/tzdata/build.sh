#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
require_command curl gcc make sha256sum tar
ensure_directories
package="tzdata-$TZDATA_VERSION"
if binary_package_restore_sysroot "$package" "${BASH_SOURCE[0]}"; then
    exit 0
fi
data_archive="$EFILINUX_DOWNLOADS/tzdata$TZDATA_VERSION.tar.gz"
code_archive="$EFILINUX_DOWNLOADS/tzcode$TZDATA_VERSION.tar.gz"
prepare_package "$package"
download "https://data.iana.org/time-zones/releases/tzdata$TZDATA_VERSION.tar.gz" "$data_archive"
download "https://data.iana.org/time-zones/releases/tzcode$TZDATA_VERSION.tar.gz" "$code_archive"
verify_sha256 "$TZDATA_SHA256" "$data_archive"
verify_sha256 "$TZCODE_SHA256" "$code_archive"
tar -xf "$data_archive" -C "$PACKAGE_SOURCE"
tar -xf "$code_archive" -C "$PACKAGE_SOURCE"
log "Building IANA zic"
make -C "$PACKAGE_SOURCE" -j"$EFILINUX_JOBS" CC=gcc CFLAGS='-O2' zic
zoneinfo="$PACKAGE_STAGING/usr/share/zoneinfo"
mkdir -p "$zoneinfo"
for source in africa antarctica asia australasia europe northamerica southamerica etcetera backward; do
    "$PACKAGE_SOURCE/zic" -L /dev/null -d "$zoneinfo" "$PACKAGE_SOURCE/$source"
done
install -m 0644 "$PACKAGE_SOURCE/iso3166.tab" "$zoneinfo/iso3166.tab"
install -m 0644 "$PACKAGE_SOURCE/zone.tab" "$zoneinfo/zone.tab"
install -m 0644 "$PACKAGE_SOURCE/zone1970.tab" "$zoneinfo/zone1970.tab"
install -m 0644 "$PACKAGE_SOURCE/zonenow.tab" "$zoneinfo/zonenow.tab"
binary_package_publish_sysroot "$package" "${BASH_SOURCE[0]}"
