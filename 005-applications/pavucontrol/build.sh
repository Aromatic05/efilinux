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
depends=(glib glibc gtkmm json-glib pulseaudio)
builddepends=()
makedepends=(autoreconf automake autopoint gcc g++ intltool-extract intltool-merge intltool-update libtool make msgfmt patch pkg-config)

prepare() {
    local archive="$downloaddir/pavucontrol-v$pkgver.tar.gz"
    download "https://gitlab.freedesktop.org/pulseaudio/pavucontrol/-/archive/v$pkgver/pavucontrol-v$pkgver.tar.gz" "$archive"
    checksum sha256 93e975be01425babcbf697c98dfd7dc1beaa2c9cf30d69d3351ca06d991f8f35 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/patches/0001-disable-event-sounds.patch" \
        "$srcdir/disable-event-sounds.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    patch -d "$srcdir/source" -Np1 < "$srcdir/disable-event-sounds.patch"
    target_autotools_configure "$srcdir/source" "$builddir"
    target_make_install "$builddir" "$develdir"
}

devel() { strip_all "$develdir/usr/bin"; }

package() {
    package_keep /usr/bin/pavucontrol /usr/share/applications/ /usr/share/pavucontrol/
}

recipe_main "$@"
