#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=iso-codes
pkgver=4.20.1

depends=()
builddepends=()
makedepends=(meson ninja python3)

prepare() {
    local archive="$downloaddir/iso-codes-$pkgver.tar.gz"
    download "https://salsa.debian.org/iso-codes-team/iso-codes/-/archive/v4.20.1/iso-codes-v4.20.1.tar.gz" "$archive"
    checksum sha256 2d7d9f6084ab9ce6c534ce71a3dd5144b6e474f3c97616459a88f73f44a64bff "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_setup "$srcdir/source" "$builddir" \


    PATH="$EFILINUX_SYSROOT/usr/bin:$PATH" target_meson_install "$builddir" "$develdir"

local compact="$builddir/compact"
reset_directory "$compact"
mkdir -p "$compact/usr/share/pkgconfig" "$compact/usr/share/xml/iso-codes" "$compact/usr/share/locale/zh_CN/LC_MESSAGES"
cp "$develdir/usr/share/pkgconfig/iso-codes.pc" "$compact/usr/share/pkgconfig/"
for domain in iso_639-2 iso_3166-1; do
    cp "$develdir/usr/share/xml/iso-codes/$domain.xml" "$compact/usr/share/xml/iso-codes/"
    cp "$develdir/usr/share/locale/zh_CN/LC_MESSAGES/$domain.mo" "$compact/usr/share/locale/zh_CN/LC_MESSAGES/"
done
ln -s iso_639-2.xml "$compact/usr/share/xml/iso-codes/iso_639.xml"
ln -s iso_3166-1.xml "$compact/usr/share/xml/iso-codes/iso_3166.xml"
ln -s iso_639-2.mo "$compact/usr/share/locale/zh_CN/LC_MESSAGES/iso_639.mo"
ln -s iso_3166-1.mo "$compact/usr/share/locale/zh_CN/LC_MESSAGES/iso_3166.mo"
rm -rf "$develdir"
mv "$compact" "$develdir"
}

devel() {
    prune_translations "$develdir"
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"

}

package() {
    local -a keep=(
        /usr/share/xml/iso-codes/
        /usr/share/locale/zh_CN/
    )
    package_keep "${keep[@]}"
}

recipe_main "$@"
