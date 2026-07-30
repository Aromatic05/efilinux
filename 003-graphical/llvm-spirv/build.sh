#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"


pkgname=llvm-spirv
pkgver=22.1.2

depends=()
builddepends=(llvm)
makedepends=(cmake gcc g++ ninja pkg-config)

prepare() {
    local translator="$downloaddir/SPIRV-LLVM-Translator-v$pkgver.tar.gz"
    local headers="$downloaddir/SPIRV-Headers-9268f3057354a2cb65991ba5f38b16d81e803692.tar.gz"
    download "https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v$pkgver.tar.gz" "$translator"
    checksum sha256 b37196b1a1a60282a24cf937ab7d6807d7d54dc718f2a37a78e211be26df57ac "$translator"
    download "https://github.com/KhronosGroup/SPIRV-Headers/archive/9268f3057354a2cb65991ba5f38b16d81e803692.tar.gz" "$headers"
    checksum sha256 045027dfcc738b6d970c49b92bae30cdb22c30a9f3e8419c3d81921355004b94 "$headers"
    extract "$translator" "$srcdir/source"
    extract "$headers" "$srcdir/spirv-headers"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    target_cmake_setup "$srcdir/source" "$builddir" \
        -DLLVM_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/llvm" \
        -DBASE_LLVM_VERSION=22.1.0 \
        -DLLVM_SPIRV_BUILD_EXTERNAL=YES \
        -DLLVM_SPIRV_INCLUDE_TESTS=OFF \
        -DLLVM_SPIRV_ENABLE_LIBSPIRV_DIS=OFF \
        -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="$srcdir/spirv-headers" \
        -DCCACHE_ALLOWED=ON
    target_cmake_install "$builddir" "$develdir"
}

package() {
    package_keep
}

recipe_main "$@"
