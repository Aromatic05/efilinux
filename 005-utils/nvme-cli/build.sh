#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"
pkgname=nvme-cli
pkgver=2.16
depends=(glibc json-c libnvme)
builddepends=(linux-headers)
makedepends=(gcc meson ninja pkg-config)
prepare() {
    local archive="$downloaddir/nvme-cli-$pkgver.tar.gz"
    download "https://github.com/linux-nvme/nvme-cli/archive/refs/tags/v$pkgver.tar.gz" "$archive"
    checksum sha256 989682ed7b250a2c7a8127e362ffc5d29f5c370127abe405be09c73216da2b97 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/trim-vendor-plugins.patch" \
        "$srcdir/trim-vendor-plugins.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch --batch -d "$srcdir/source" -p1 < "$srcdir/trim-vendor-plugins.patch"
}
build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        --sbindir=bin \
        -Ddocs=false \
        -Ddocs-build=false \
        -Dnvme-tests=false \
        -Djson-c=enabled \
        -Dversion-tag="$pkgver"
    target_meson_install "$builddir" "$develdir"
}
devel() { strip_all "$develdir/usr/bin"; }
package() {
    local -a keep=(/usr/bin/nvme)
    [[ ! -f "$pkgdir/usr/share/bash-completion/completions/nvme" ]] || \
        keep+=(/usr/share/bash-completion/completions/nvme)
    package_keep "${keep[@]}"
}
recipe_main "$@"
