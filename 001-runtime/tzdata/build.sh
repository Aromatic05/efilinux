#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=tzdata
pkgver=2026c

depends=()
builddepends=()
makedepends=(
    install
    zic
)

prepare() {
    local archive="$downloaddir/tzdata$pkgver.tar.gz"

    download \
        "https://data.iana.org/time-zones/releases/tzdata$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        e4a178a4477f3d0ea77cc31828ff72aa38feff8d61aa13e7e99e142e9d902be4 \
        "$archive"
    extract_contents "$archive" "$srcdir/tzdata"
}

build() {
    local zoneinfo="$develdir/usr/share/zoneinfo"
    local source

    mkdir -p "$zoneinfo"
    for source in \
        africa \
        antarctica \
        asia \
        australasia \
        europe \
        northamerica \
        southamerica \
        etcetera \
        backward; do
        zic -L /dev/null -d "$zoneinfo" "$srcdir/tzdata/$source"
    done
    install -m0644 "$srcdir/tzdata/iso3166.tab" "$zoneinfo/iso3166.tab"
    install -m0644 "$srcdir/tzdata/zone.tab" "$zoneinfo/zone.tab"
    install -m0644 "$srcdir/tzdata/zone1970.tab" "$zoneinfo/zone1970.tab"
    install -m0644 "$srcdir/tzdata/zonenow.tab" "$zoneinfo/zonenow.tab"
    install -d "$develdir/etc"
    ln -s /usr/share/zoneinfo/UTC "$develdir/etc/localtime"
}

package() {
    :
}

recipe_main "$@"
