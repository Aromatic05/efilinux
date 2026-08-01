#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=netcat-traditional
pkgver=1.10-50
depends=(glibc)
builddepends=()
makedepends=(gcc make patch)

prepare() {
    local source_archive="$downloaddir/netcat_1.10.orig.tar.bz2"
    local debian_archive="$downloaddir/netcat_1.10-50.debian.tar.xz"
    local patch_name

    download \
        "https://deb.debian.org/debian/pool/main/n/netcat/netcat_1.10.orig.tar.bz2" \
        "$source_archive"
    checksum sha256 \
        64913dc3f0b4a96c3ab04d062d84f28ba6854152c94344e3985458b2aebca3d5 \
        "$source_archive"
    download \
        "https://deb.debian.org/debian/pool/main/n/netcat/netcat_1.10-50.debian.tar.xz" \
        "$debian_archive"
    checksum sha256 \
        9a622c09f542f598094f696c7c1148e54029f1793f4cb9a1573bb7e2e0c07d5d \
        "$debian_archive"

    extract "$source_archive" "$srcdir/source"
    extract "$debian_archive" "$srcdir/debian-source"
    input_file "$recipedir/gcc16-signal-handlers.patch" \
        "$srcdir/gcc16-signal-handlers.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
    [[ "$RECIPE_INPUT_MODE" == metadata ]] && return

    cp -a "$srcdir/debian-source" "$srcdir/source/debian"
    while IFS= read -r patch_name; do
        [[ -n "$patch_name" && $patch_name != \#* ]] || continue
        patch -d "$srcdir/source" -Np1 \
            -i "$srcdir/source/debian/patches/$patch_name"
    done < "$srcdir/source/debian/patches/series"
    patch -d "$srcdir/source" -Np1 -i "$srcdir/gcc16-signal-handlers.patch"
}

build() {
    local compiler
    compiler=$(target_compiler_wrapper gcc)

    "$compiler" \
        $CFLAGS $CPPFLAGS \
        -Wall \
        -DLINUX \
        -DTELNET \
        -DGAPING_SECURITY_HOLE \
        -DIP_TOS \
        '-DDEBIAN_VERSION="1.10-50"' \
        "$srcdir/source/netcat.c" \
        $LDFLAGS \
        -o "$srcdir/source/nc"
    install -Dm0755 "$srcdir/source/nc" "$develdir/usr/bin/nc.traditional"
}

devel() {
    strip_all "$develdir/usr/bin/nc.traditional"
}

package() {
    package_keep /usr/bin/nc.traditional
}

recipe_main "$@"
