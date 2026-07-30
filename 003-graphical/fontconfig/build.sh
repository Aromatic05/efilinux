#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fontconfig
pkgver=2.18.2

depends=(expat freetype glibc)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/fontconfig-2.18.2.tar.gz"

    download \
        "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.18.2.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        a84d41b57cfb015783d7973b398c26d8763a64b803f97f31fa126fd2aa5eaaca \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir"             -Ddoc=disabled             -Ddoc-txt=disabled             -Ddoc-man=disabled             -Ddoc-pdf=disabled             -Ddoc-html=disabled             -Dnls=disabled             -Dtests=disabled             -Dtests-bwrap=disabled             -Dtests-external-fonts=disabled             -Dtools=enabled             -Dcache-build=disabled             -Diconv=disabled             -Dxml-backend=expat             -Dfontations=disabled
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /usr/bin/fc-cache
        /usr/bin/fc-match
        /etc/fonts/
        /usr/share/fontconfig/
    )
    package_add_library_family keep 'libfontconfig.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
