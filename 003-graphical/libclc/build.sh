#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"


pkgname=libclc
pkgver=22.1.8

depends=()
builddepends=(clang-headers llvm llvm-spirv)
makedepends=(clang cmake llvm-config ninja)

prepare() {
    local archive="$downloaddir/llvm-project-$pkgver.src.tar.xz"
    download "https://github.com/llvm/llvm-project/releases/download/llvmorg-$pkgver/llvm-project-$pkgver.src.tar.xz" "$archive"
    checksum sha256 922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888 "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local llvm_spirv

    [[ $(llvm-config --version) == "$pkgver" ]] || die "host llvm-config version does not match $pkgver"
    [[ $(clang --version | sed -n '1s/^clang version \([^ ]*\).*/\1/p') == "$pkgver" ]] || die "host clang version does not match $pkgver"
    llvm_spirv=$(target_program_wrapper llvm-spirv /usr/bin/llvm-spirv)
    "$llvm_spirv" --version | grep -Fq "LLVM version $pkgver" || \
        die "target llvm-spirv does not match LLVM $pkgver"

    cmake -S "$srcdir/source/libclc" -B "$builddir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_DATADIR=share \
        -DLLVM_DIR="$(llvm-config --cmakedir)" \
        -DLIBCLC_USE_SPIRV_BACKEND=OFF \
        -DLLVM_SPIRV="$llvm_spirv" \
        '-DLIBCLC_TARGETS_TO_BUILD=spirv-mesa3d-;spirv64-mesa3d-'
    cmake --build "$builddir" -j "$EFILINUX_JOBS"
    DESTDIR="$develdir" cmake --install "$builddir"
}

package() {
    package_keep
}

recipe_main "$@"
