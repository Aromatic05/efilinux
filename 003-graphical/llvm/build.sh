#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"


pkgname=llvm
pkgver=22.1.8

depends=(gcc-libs glibc libffi zlib zstd)
builddepends=()
makedepends=(cmake gcc g++ ninja python3)

prepare() {
    local archive="$downloaddir/llvm-project-$pkgver.src.tar.xz"
    download "https://github.com/llvm/llvm-project/releases/download/llvmorg-$pkgver/llvm-project-$pkgver.src.tar.xz" "$archive"
    checksum sha256 922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    CFLAGS+=" -ffunction-sections -fdata-sections"
    CXXFLAGS+=" -ffunction-sections -fdata-sections"
    export CFLAGS CXXFLAGS

    target_cmake_setup "$srcdir/source/llvm" "$builddir" \
        -DLLVM_TARGETS_TO_BUILD='X86;AMDGPU' \
        -DLLVM_BUILD_LLVM_DYLIB=ON \
        -DLLVM_LINK_LLVM_DYLIB=ON \
        -DLLVM_DYLIB_COMPONENTS=all \
        -DLLVM_ENABLE_RTTI=ON \
        -DLLVM_ENABLE_FFI=ON \
        -DLLVM_ENABLE_ZLIB=ON \
        -DLLVM_ENABLE_ZSTD=ON \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_ENABLE_CURL=OFF \
        -DLLVM_ENABLE_HTTPLIB=OFF \
        -DLLVM_ENABLE_BINDINGS=OFF \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_BUILD_TESTS=OFF \
        -DLLVM_BUILD_BENCHMARKS=OFF \
        -DLLVM_BUILD_EXAMPLES=OFF \
        -DLLVM_BUILD_TOOLS=ON \
        -DLLVM_BUILD_UTILS=OFF \
        -DLLVM_INSTALL_UTILS=ON
    target_cmake_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=()
    package_add_library_family keep 'libLLVM.so*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
