#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=fcitx5-table-extra
pkgver=5.1.8
depends=(fcitx5 libime)
builddepends=(extra-cmake-modules fcitx5 libime)
makedepends=(cmake gettext ninja pkg-config)

prepare() {
    local archive="$downloaddir/fcitx5-table-extra-$pkgver.tar.gz"
    download "https://github.com/fcitx/fcitx5-table-extra/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 39577ac6ff74f559f0c7b8ba64100458bd56fac34b62d9aff64575dd3a0f2805 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir"
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    local opt_root="$develdir/opt/fcitx5/share/fcitx5"
    local name dictionary
    local -a methods=(cangjie5 jyutping-table quick5 wubi98)

    prune_translations "$develdir"
    install -d -m0755 "$opt_root/inputmethod" "$opt_root/table"
    for name in "${methods[@]}"; do
        install -m0644 \
            "$develdir/usr/share/fcitx5/inputmethod/$name.conf" \
            "$opt_root/inputmethod/$name.conf"
        dictionary=$(sed -n 's/^File=table\///p' \
            "$develdir/usr/share/fcitx5/inputmethod/$name.conf" | head -n 1)
        [[ -n "$dictionary" ]] || die "missing table dictionary for $name"
        install -m0644 \
            "$develdir/usr/share/fcitx5/table/$dictionary" \
            "$opt_root/table/$dictionary"
    done
}

package() {
    local path
    local -a keep=(/opt/fcitx5/share/fcitx5/)

    while IFS= read -r path; do
        keep+=("${path#$develdir}")
    done < <(find "$develdir/usr/share/icons/hicolor" -type f \
        \( -name 'org.fcitx.Fcitx5.fcitx_jyutping_table.png' \
        -o -name 'org.fcitx.Fcitx5.fcitx_quick5.png' \) -print)
    package_keep "${keep[@]}"
}

recipe_main "$@"
