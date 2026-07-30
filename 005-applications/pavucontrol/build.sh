#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=pavucontrol
pkgver=5.0
depends=(glib glibc gtkmm json-glib libcanberra pulseaudio)
builddepends=()
makedepends=(autoreconf automake autopoint gcc g++ intltool-extract intltool-merge intltool-update libtool make msgfmt pkg-config)

prepare() {
    local archive="$downloaddir/pavucontrol-v$pkgver.tar.gz"
    download "https://gitlab.freedesktop.org/pulseaudio/pavucontrol/-/archive/v$pkgver/pavucontrol-v$pkgver.tar.gz" "$archive"
    checksum sha256 93e975be01425babcbf697c98dfd7dc1beaa2c9cf30d69d3351ca06d991f8f35 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_autotools_configure "$srcdir/source" "$builddir"
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin"; }

package() {
    package_keep /usr/bin/pavucontrol /usr/share/applications/ /usr/share/pavucontrol/
}

recipe_main "$@"
