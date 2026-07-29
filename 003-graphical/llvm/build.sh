#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command cmake curl g++ gcc ninja sha256sum tar
ensure_directories

package="llvm-$LLVM_VERSION"
graphical_prepare_archive \
    "$package" \
    "llvm-project-$LLVM_VERSION.src.tar.xz" \
    "$LLVM_SHA256" \
    "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/llvm-project-$LLVM_VERSION.src.tar.xz"

log "Configuring LLVM X86 and AMDGPU backends"
graphical_cmake_setup "$PACKAGE_SOURCE/llvm" "$PACKAGE_BUILD" \
    -DLLVM_TARGETS_TO_BUILD="X86;AMDGPU" \
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

log "Building LLVM"
graphical_cmake_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"

[[ -e "$PACKAGE_STAGING/usr/lib/libLLVM.so" ]] || \
    die "LLVM shared library was not installed"
[[ -x "$PACKAGE_STAGING/usr/bin/llvm-config" ]] || \
    die "llvm-config was not installed"

merge_sysroot "$PACKAGE_STAGING"
