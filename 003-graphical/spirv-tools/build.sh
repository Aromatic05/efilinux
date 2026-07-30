#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"


pkgname=spirv-tools
pkgver=1.4.357.0

depends=()
builddepends=()
makedepends=(cmake gcc g++ ninja python3)

prepare() {
    local tools="$downloaddir/SPIRV-Tools-vulkan-sdk-$pkgver.tar.gz"
    local headers="$downloaddir/SPIRV-Headers-29981f65241605e08b0ede4cfeb999fe3b723c6a.tar.gz"
    download "https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/vulkan-sdk-$pkgver.tar.gz" "$tools"
    checksum sha256 d31e7109b6ef3559067e53e520870eafed7c9534d00db9728814b6df03fa4a5e "$tools"
    download "https://github.com/KhronosGroup/SPIRV-Headers/archive/29981f65241605e08b0ede4cfeb999fe3b723c6a.tar.gz" "$headers"
    checksum sha256 232899f1ad4104fb5bc377b94596c7621575eee62ad9a9e8f929b63a7dd8a7ad "$headers"
    extract "$tools" "$srcdir/source"
    extract "$headers" "$srcdir/spirv-headers"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DBUILD_SHARED_LIBS=OFF \
        -DSPIRV-Headers_SOURCE_DIR="$srcdir/spirv-headers" \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_SKIP_TESTS=ON \
        -DSPIRV_WERROR=OFF
    target_cmake_install "$builddir" "$develdir"
    rm -f \
        "$develdir/usr/lib/libSPIRV-Tools-shared.so" \
        "$develdir/usr/lib/pkgconfig/SPIRV-Tools-shared.pc" \
        "$develdir/usr/lib/libSPIRV-Tools-diff.a" \
        "$develdir/usr/lib/libSPIRV-Tools-lint.a" \
        "$develdir/usr/lib/libSPIRV-Tools-reduce.a"
    rm -rf "$develdir/usr/lib/cmake"
}

package() {
    package_keep
}

recipe_main "$@"
