#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

ensure_directories

producer="$ROOT/003-graphical/llvm-spirv/build.sh"
target_package="llvm-spirv-$LLVM_SPIRV_TRANSLATOR_VERSION"
host_package="llvm-spirv-host-$LLVM_SPIRV_TRANSLATOR_VERSION"
host_install="$EFILINUX_BUILD/host-tools/$target_package"
target_cached=false
host_cached=false

if graphical_binary_package_restore "$target_package" "$producer"; then
    target_cached=true
fi
if binary_package_extract \
    "$host_package" "$host_install" "$producer" \
    "$ROOT/003-graphical/config.sh" \
    "$ROOT/003-graphical/lib/build.sh"; then
    host_cached=true
    log "Using binary package $(basename -- "$PACKAGE_ARCHIVE")"
fi

translator="$host_install/bin/llvm-spirv"
if [[ $target_cached == true && $host_cached == true ]]; then
    [[ -x $translator ]] || die "cached host llvm-spirv translator is missing"
    printf '%s\n' "$translator"
    exit 0
fi

require_command cmake curl llvm-config ninja pkg-config sha256sum tar
host_llvm_version=$(llvm-config --version)
[[ $host_llvm_version == "$LLVM_VERSION" ]] || \
    die "host LLVM $host_llvm_version does not match required LLVM $LLVM_VERSION"

prepare_package "$target_package"
headers_source="$PACKAGE_SOURCE/spirv-headers"
host_build="$PACKAGE_BUILD/host"
target_build="$PACKAGE_BUILD/target"
reset_directory "$headers_source"
reset_directory "$host_build"
reset_directory "$target_build"

translator_archive="SPIRV-LLVM-Translator-v$LLVM_SPIRV_TRANSLATOR_VERSION.tar.gz"
translator_url="https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v$LLVM_SPIRV_TRANSLATOR_VERSION.tar.gz"
download "$translator_url" "$EFILINUX_DOWNLOADS/$translator_archive"
verify_sha256 "$LLVM_SPIRV_TRANSLATOR_SHA256" "$EFILINUX_DOWNLOADS/$translator_archive"
extract_source "$EFILINUX_DOWNLOADS/$translator_archive" "$PACKAGE_SOURCE"

headers_archive="SPIRV-Headers-$SPIRV_HEADERS_COMMIT.tar.gz"
headers_url="https://github.com/KhronosGroup/SPIRV-Headers/archive/$SPIRV_HEADERS_COMMIT.tar.gz"
download "$headers_url" "$EFILINUX_DOWNLOADS/$headers_archive"
verify_sha256 "$SPIRV_HEADERS_SHA256" "$EFILINUX_DOWNLOADS/$headers_archive"
extract_source "$EFILINUX_DOWNLOADS/$headers_archive" "$headers_source"

common_options=(
    -DBASE_LLVM_VERSION=22.1.0
    -DLLVM_SPIRV_BUILD_EXTERNAL=YES
    -DLLVM_SPIRV_INCLUDE_TESTS=OFF
    -DLLVM_SPIRV_ENABLE_LIBSPIRV_DIS=OFF
    -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="$headers_source"
    -DCCACHE_ALLOWED=ON
)

if [[ $host_cached == false ]]; then
    reset_directory "$host_install"
    log "Configuring host LLVM-SPIRV translator"
    cmake -S "$PACKAGE_SOURCE" -B "$host_build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$host_install" \
        -DLLVM_DIR="$(llvm-config --cmakedir)" \
        "${common_options[@]}"

    log "Building host LLVM-SPIRV translator"
    cmake --build "$host_build" -j "$EFILINUX_JOBS"
    cmake --install "$host_build"

    translator="$host_install/bin/llvm-spirv"
    [[ -x $translator ]] || die "llvm-spirv was not installed"
    "$translator" --version | grep -Fq "LLVM version $LLVM_VERSION" || \
        die "llvm-spirv is not linked against LLVM $LLVM_VERSION"
    binary_package_create \
        "$host_package" "$host_install" "$producer" \
        "$ROOT/003-graphical/config.sh" \
        "$ROOT/003-graphical/lib/build.sh"
fi

translator="$host_install/bin/llvm-spirv"
[[ -x $translator ]] || die "host llvm-spirv translator is missing"

if [[ $target_cached == false ]]; then
    log "Configuring target LLVM-SPIRV library"
    graphical_cmake_setup "$PACKAGE_SOURCE" "$target_build" \
        -DLLVM_DIR="$EFILINUX_SYSROOT/usr/lib/cmake/llvm" \
        "${common_options[@]}"

    log "Building target LLVM-SPIRV library"
    graphical_cmake_install "$target_build" "$PACKAGE_STAGING"
    rm -f "$PACKAGE_STAGING/usr/bin/llvm-spirv"

    for artifact in \
        usr/lib/libLLVMSPIRVLib.a \
        usr/lib/pkgconfig/LLVMSPIRVLib.pc \
        usr/include/LLVMSPIRVLib/LLVMSPIRVLib.h \
        usr/include/LLVMSPIRVLib/LLVMSPIRVOpts.h \
        usr/include/LLVMSPIRVLib/LLVMSPIRVExtensions.inc; do
        [[ -s "$PACKAGE_STAGING/$artifact" ]] || \
            die "target LLVM-SPIRV artifact is missing: /$artifact"
    done
    [[ ! -e "$PACKAGE_STAGING/usr/bin/llvm-spirv" ]] || \
        die "host llvm-spirv leaked into target staging"

    graphical_binary_package_publish "$target_package" "$producer"
else
    rm -rf -- "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$PACKAGE_STAGING"
fi

printf '%s\n' "$translator"
