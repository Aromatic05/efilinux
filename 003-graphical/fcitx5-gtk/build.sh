#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fcitx5-gtk
pkgver=5.1.4
depends=(glib gtk3 libxkbcommon xorg)
builddepends=(extra-cmake-modules)
makedepends=(cmake gcc g++ ninja pkg-config)

prepare() {
    local archive="$downloaddir/fcitx5-gtk-$pkgver.tar.gz"
    download "https://github.com/fcitx/fcitx5-gtk/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 73f63d10078c62e5b6d82e6b16fcb03d2038cc204fc00052a34ab7962b0b7815 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DENABLE_GIR=OFF \
        -DENABLE_GTK2_IM_MODULE=OFF \
        -DENABLE_GTK3_IM_MODULE=ON \
        -DENABLE_GTK4_IM_MODULE=OFF \
        -DENABLE_SNOOPER=ON \
        -DBUILD_ONLY_PLUGIN=ON \
        -DGTK3_IM_MODULEDIR=/usr/lib/gtk-3.0/3.0.0/immodules
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    local module cache query
    module=$(find "$develdir/usr/lib/gtk-3.0" -type f -name 'im-fcitx5*.so' -print -quit)
    [[ -n $module ]] || die 'fcitx5 GTK3 input method module was not installed'
    strip_all "$(dirname -- "$module")"

    install -d -m0755 "$develdir/usr/lib/gtk-3.0/3.0.0"
    cache="$develdir/usr/lib/gtk-3.0/3.0.0/immodules.cache"
    query=$(target_program_wrapper gtk-query-immodules-3.0 /usr/bin/gtk-query-immodules-3.0)
    "$query" "$module" > "$cache"
    sed -i "s#$develdir##g" "$cache"
    grep -Fq '/usr/lib/gtk-3.0/3.0.0/immodules/' "$cache" || \
        die 'fcitx5 GTK3 input method cache does not reference the runtime module'
}

package() {
    package_keep \
        /usr/lib/gtk-3.0/3.0.0/immodules/ \
        /usr/lib/gtk-3.0/3.0.0/immodules.cache
}

recipe_main "$@"
