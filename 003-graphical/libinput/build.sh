#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libinput
pkgver=1.31.3

depends=(glibc libevdev udev)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libinput-1.31.3.tar.gz"

    download \
        "https://gitlab.freedesktop.org/libinput/libinput/-/archive/1.31.3/libinput-1.31.3.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        b6749bf6f1890f6631c0a70a027c35fec9d2e096a39f720548896e41474a9854 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dlibwacom=false \
        -Dmtdev=false \
        -Ddebug-gui=false \
        -Dtests=false \
        -Dinstall-tests=false \
        -Ddocumentation=false \
        -Dzshcompletiondir=no \
        -Dlua-plugins=disabled \
        -Dinternal-event-debugging=false \
        -Dautoload-plugins=false
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libinput.so.10*'
    keep+=("/usr/share/libinput/")
    keep+=("/usr/lib/udev/")
    package_keep "${keep[@]}"
}

recipe_main "$@"
