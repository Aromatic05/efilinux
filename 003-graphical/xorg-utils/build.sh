#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xorg-utils
pkgver=1.2.3
sysroot=false

depends=(glibc xorg)
builddepends=()
makedepends=(gcc make pkg-config)

prepare() {
    local xrdb="$downloaddir/xrdb-1.2.3.tar.xz"
    local xmodmap="$downloaddir/xmodmap-1.0.12.tar.xz"
    download "https://www.x.org/releases/individual/app/xrdb-1.2.3.tar.xz" "$xrdb"
    checksum sha256 c88f560243278c896ce4fc92ae5a45a2b505a316ffa427fe55b02e5d5914c4e4 "$xrdb"
    download "https://www.x.org/releases/individual/app/xmodmap-1.0.12.tar.xz" "$xmodmap"
    checksum sha256 fc54b9b5bbf2ae58ba8f9d42bd051c41c7438377400c42c17d7496d19e1bb3ce "$xmodmap"
    extract "$xrdb" "$srcdir/xrdb"
    extract "$xmodmap" "$srcdir/xmodmap"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build_component() {
    local name=$1
    shift
    local component_build="$builddir/$name"
    mkdir -p "$component_build"
    target_release_configure "$srcdir/$name" "$component_build" "$@"
    target_make_install "$component_build" "$develdir"
}

build() {
    build_component xrdb --with-cpp=/usr/bin/false
    build_component xmodmap
}

devel() {
    strip_all "$develdir/usr/bin/xrdb" "$develdir/usr/bin/xmodmap"
}

package() {
    package_keep /usr/bin/xrdb /usr/bin/xmodmap
}

recipe_main "$@"
