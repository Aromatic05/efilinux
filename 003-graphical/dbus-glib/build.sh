#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=dbus-glib
pkgver=0.114

depends=(dbus glib glibc)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/dbus-glib-$pkgver.tar.gz"
    download "https://dbus.freedesktop.org/releases/dbus-glib/dbus-glib-$pkgver.tar.gz" "$archive"
    checksum sha256 c09c5c085b2a0e391b8ee7d783a1d63fe444e96717cc1814d61b5e8fc2827a7c "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_release_configure "$srcdir/source" "$builddir" --disable-static --disable-silent-rules --disable-gtk-doc --disable-tests
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/lib"; }

package() {
    local -a keep=()
    package_add_library_family keep 'libdbus-glib-1.so.2*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
