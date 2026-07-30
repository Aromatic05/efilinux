#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"


pkgname=clang-headers
pkgver=22.1.8

depends=()
builddepends=(llvm)
makedepends=(clang cmake gcc g++ llvm-config llvm-tblgen ninja readelf)

prepare() {
    local archive="$downloaddir/llvm-project-$pkgver.src.tar.xz"
    download "https://github.com/llvm/llvm-project/releases/download/llvmorg-$pkgver/llvm-project-$pkgver.src.tar.xz" "$archive"
    checksum sha256 922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    [[ $(llvm-config --version) == "$pkgver" ]] || die "host llvm-config version does not match $pkgver"
    [[ $(clang --version | sed -n '1s/^clang version \([^ ]*\).*/\1/p') == "$pkgver" ]] || die "host clang version does not match $pkgver"
    [[ $(llvm-tblgen --version | sed -n 's/^  LLVM version //p') == "$pkgver" ]] || die "host llvm-tblgen version does not match $pkgver"

    target_cmake_setup "$srcdir/source/clang" "$builddir" \
        -DLLVM_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/llvm" \
        -DLLVM_TABLEGEN_EXE="$(command -v llvm-tblgen)" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCLANG_BUILD_TOOLS=OFF \
        -DCLANG_INCLUDE_TESTS=OFF \
        -DCLANG_INCLUDE_DOCS=OFF \
        -DCLANG_BUILD_EXAMPLES=OFF \
        -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
        -DCLANG_ENABLE_OBJC_REWRITER=OFF \
        -DCLANG_ENABLE_HLSL=OFF \
        -DCLANG_LINK_CLANG_DYLIB=OFF \
        -DLLVM_INCLUDE_TESTS=OFF
    cmake --build "$builddir" --target clang-headers clang-resource-headers -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" cmake --build "$builddir" \
        --target install-clang-headers install-clang-resource-headers \
        -j "$EFILINUX_JOBS"
}

package() {
    package_keep
}

recipe_main "$@"
