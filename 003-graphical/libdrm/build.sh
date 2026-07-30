#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=libdrm
pkgver=2.4.134

depends=(glibc libpciaccess)
builddepends=()
makedepends=(gcc meson ninja pkg-config python3)

prepare() {
    local archive="$downloaddir/libdrm-2.4.134.tar.gz"

    download \
        "https://gitlab.freedesktop.org/mesa/drm/-/archive/libdrm-2.4.134/drm-libdrm-2.4.134.tar.gz" \
        "$archive"
    checksum \
        sha256 \
        6b18e4834b0c061232cb5c11e98a6ecdc72ebc6bc282d124406b7a9d4e089ce2 \
        "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_meson_setup "$srcdir/source" "$builddir" \
        -Dintel=enabled \
        -Dradeon=enabled \
        -Damdgpu=enabled \
        -Dnouveau=enabled \
        -Dvmwgfx=enabled \
        -Domap=disabled \
        -Dexynos=disabled \
        -Dfreedreno=disabled \
        -Dtegra=disabled \
        -Dvc4=disabled \
        -Detnaviv=disabled \
        -Dcairo-tests=disabled \
        -Dman-pages=disabled \
        -Dvalgrind=disabled \
        -Dtests=false \
        -Dinstall-test-programs=false
    target_meson_install "$builddir" "$develdir"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    [[ ! -d "$develdir/usr/bin" ]] || strip_all "$develdir/usr/bin"
    [[ ! -d "$develdir/usr/lib" ]] || strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libdrm.so.2*'
    package_add_library_family keep 'libdrm_amdgpu.so.1*'
    package_add_library_family keep 'libdrm_intel.so.1*'
    package_add_library_family keep 'libdrm_nouveau.so.2*'
    package_add_library_family keep 'libdrm_radeon.so.1*'
    keep+=("/usr/share/libdrm/")
    package_keep "${keep[@]}"
}

recipe_main "$@"
