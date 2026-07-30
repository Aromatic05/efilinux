#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=startup-notification
pkgver=0.12

depends=(glibc xorg)
builddepends=()
makedepends=(autoreconf gcc make pkg-config)

prepare() {
    local archive="$downloaddir/startup-notification-STARTUP_NOTIFICATION_0_12.tar.gz"
    download "https://gitlab.freedesktop.org/xdg/startup-notification/-/archive/STARTUP_NOTIFICATION_0_12/startup-notification-STARTUP_NOTIFICATION_0_12.tar.gz" "$archive"
    checksum sha256 37b727cd9fcbda4e52cdb49b8f42c9eb3381b822c6df8b1caa6969d6903c6ade "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_autotools_configure "$srcdir/source" "$builddir" --disable-static --disable-silent-rules
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libstartup-notification-1.so.0*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
