#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=sof-firmware
pkgver=2025.12.2
sysroot=false

depends=()
builddepends=()
makedepends=(find install)

prepare() {
    local archive="$downloaddir/sof-bin-$pkgver.tar.gz"

    download \
        "https://github.com/thesofproject/sof-bin/releases/download/v$pkgver/sof-bin-$pkgver.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        533f63e3a6d94c09ce05a782657b675fa683ff20787c0979226cf563ec79f517 \
        "$archive"
    extract "$archive" "$srcdir/sof-bin"
}

build() {
    local firmware_staging="$develdir/usr/lib/firmware/intel"
    local directory

    mkdir -p "$firmware_staging"
    for directory in sof sof-ipc4 sof-ipc4-lib sof-ipc4-tplg sof-tplg; do
        [[ -d "$srcdir/sof-bin/$directory" ]] || \
            die "SOF archive is missing directory: $directory"
        cp -a "$srcdir/sof-bin/$directory" "$firmware_staging/$directory"
    done

    find "$firmware_staging" -type d -name community -prune -exec rm -rf -- {} +
    find "$firmware_staging" -type f -name '*.ldc' -delete
    find -L "$firmware_staging" -type l -delete
    ln -s sof-ipc4-tplg "$firmware_staging/sof-ace-tplg"
}

package() {
    :
}

recipe_main "$@"
