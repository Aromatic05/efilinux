#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=qogir-icon-theme
pkgver=2025-02-15
sysroot=false

depends=(hicolor-icon-theme)
builddepends=()
makedepends=(bash find python3)

prepare() {
    local archive="$downloaddir/qogir-icon-theme-$pkgver.tar.gz"
    download "https://github.com/vinceliuice/Qogir-icon-theme/archive/refs/tags/$pkgver.tar.gz" "$archive"
    checksum sha256 b0d07cad5601e0341a53a62df0ed111823b75fc38741d435486620a59fb239ee "$archive"
    extract "$archive" "$srcdir/source"
    input_file "$recipedir/files/prune-theme.py" "$srcdir/prune-theme.py"
    input_file "$recipedir/files/applications.allow" "$srcdir/applications.allow"
    input_file "$recipedir/files/actions.allow" "$srcdir/actions.allow"
    input_file "$recipedir/files/panel.allow" "$srcdir/panel.allow"
}

build() {
    mkdir -p "$develdir/usr/share/icons"
    (
        cd "$srcdir/source"
        bash ./install.sh --dest "$develdir/usr/share/icons" --theme default --color standard
    )
    rm -rf "$develdir/usr/share/icons/Qogir/cursors_scalable"
    PYTHONDONTWRITEBYTECODE=1 python3 "$srcdir/prune-theme.py" \
        --theme "$develdir/usr/share/icons/Qogir" \
        --applications "$srcdir/applications.allow" \
        --actions "$srcdir/actions.allow" \
        --panel "$srcdir/panel.allow"
    if find -L "$develdir/usr/share/icons/Qogir" -type l -print -quit | grep -q .; then
        die "Qogir icon package contains broken symbolic links"
    fi
    [[ -e "$develdir/usr/share/icons/Qogir/cursors/left_ptr" ]] || die "Qogir cursor payload is incomplete"
}

devel() {
    find "$develdir/usr/share/icons" -type f -name icon-theme.cache -delete
}

package() { :; }

recipe_main "$@"
