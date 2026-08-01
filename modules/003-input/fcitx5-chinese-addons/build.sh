#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fcitx5-chinese-addons
pkgver=5.1.8
depends=(fcitx5 glibc libime opencc)
builddepends=(extra-cmake-modules fcitx5 libime opencc)
makedepends=(cmake gcc g++ gettext ninja pkg-config)

prepare() {
    local archive="$downloaddir/fcitx5-chinese-addons-$pkgver.tar.gz"
    download "https://github.com/fcitx/fcitx5-chinese-addons/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 0182025f7451adb2df488812b31b900dfb59fb264a6b485fa2339e8ecd63bb41 "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/fmt-runtime.patch" "$srcdir/fmt-runtime.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return
    patch -d "$srcdir/source" -p1 < "$srcdir/fmt-runtime.patch"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DENABLE_TEST=OFF \
        -DENABLE_GUI=OFF \
        -DENABLE_BROWSER=OFF \
        -DENABLE_CLOUDPINYIN=OFF \
        -DENABLE_OPENCC=ON \
        -DENABLE_DATA=ON
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    prune_translations "$develdir"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/lib/fcitx5"
}

package() {
    package_keep \
        /usr/lib/fcitx5/libchttrans.so \
        /usr/lib/fcitx5/libfullwidth.so \
        /usr/lib/fcitx5/libpinyinhelper.so \
        /usr/lib/fcitx5/libpinyin.so \
        /usr/lib/fcitx5/libpunctuation.so \
        /usr/lib/fcitx5/libtable.so \
        /usr/share/fcitx5/addon/ \
        /usr/share/fcitx5/chttrans/ \
        /usr/share/fcitx5/inputmethod/ \
        /usr/share/fcitx5/pinyin/ \
        /usr/share/fcitx5/pinyinhelper/ \
        /usr/share/fcitx5/punctuation/ \
        /usr/share/icons/hicolor/
}

recipe_main "$@"
