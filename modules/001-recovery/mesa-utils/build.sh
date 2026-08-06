#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=mesa-utils
pkgver=9.0.0

depends=(glibc mesa xorg)
builddepends=()
makedepends=(gcc pkg-config)

prepare() {
    local archive="$downloaddir/mesa-demos-$pkgver.tar.xz"
    download "https://archive.mesa3d.org/demos/mesa-demos-$pkgver.tar.xz" "$archive"
    checksum sha256 3046a3d26a7b051af7ebdd257a5f23bfeb160cad6ed952329cdff1e9f1ed496b "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local compiler
    local -a package_flags

    compiler=$(target_compiler_wrapper gcc)
    read -r -a package_flags <<< "$(
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            pkg-config --cflags --libs gl x11
    )"

    mkdir -p "$builddir"
    "$compiler" \
        $CFLAGS \
        -I"$srcdir/source/src/glad/include" \
        -I"$srcdir/source/src/util" \
        "$srcdir/source/src/xdemos/glxinfo.c" \
        "$srcdir/source/src/util/glinfo_common.c" \
        "$srcdir/source/src/glad/src/glad.c" \
        $LDFLAGS \
        "${package_flags[@]}" \
        -o "$builddir/glxinfo"

    install -Dm0755 "$builddir/glxinfo" "$develdir/usr/bin/glxinfo"
}

check() {
    local dynamic_section="$builddir/glxinfo.dynamic"
    [[ -x "$develdir/usr/bin/glxinfo" ]] || die "glxinfo binary is missing"
    LC_ALL=C readelf -d "$develdir/usr/bin/glxinfo" > "$dynamic_section"
    grep -Fq 'Shared library: [libGL.so.1]' "$dynamic_section" ||
        die "glxinfo is not linked to the target OpenGL runtime"
    grep -Fq 'Shared library: [libX11.so.6]' "$dynamic_section" ||
        die "glxinfo is not linked to the target X11 runtime"
}

devel() {
    strip_all "$develdir/usr/bin/glxinfo"
}

package() {
    package_keep /usr/bin/glxinfo
}

recipe_main "$@"
