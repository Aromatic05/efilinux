#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command clang cmake curl llvm-config ninja sha256sum tar
ensure_directories

host_llvm_version=$(llvm-config --version)
[[ $host_llvm_version == "$LLVM_VERSION" ]] || \
    die "host LLVM $host_llvm_version does not match required LLVM $LLVM_VERSION"
host_clang_version=$(clang --version | sed -n '1s/^clang version \([^ ]*\).*/\1/p')
[[ $host_clang_version == "$LLVM_VERSION" ]] || \
    die "host Clang $host_clang_version does not match required LLVM $LLVM_VERSION"

translator="$EFILINUX_BUILD/host-tools/llvm-spirv-$LLVM_SPIRV_TRANSLATOR_VERSION/bin/llvm-spirv"
if [[ ! -x $translator ]]; then
    "$ROOT/003-graphical/llvm-spirv/build.sh" >/dev/null
fi
[[ -x $translator ]] || die "host llvm-spirv translator is missing"

package="libclc-$LLVM_VERSION"
prepare_package "$package"
archive="llvm-project-$LLVM_VERSION.src.tar.xz"
download \
    "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/$archive" \
    "$EFILINUX_DOWNLOADS/$archive"
verify_sha256 "$LLVM_SHA256" "$EFILINUX_DOWNLOADS/$archive"
extract_source "$EFILINUX_DOWNLOADS/$archive" "$PACKAGE_SOURCE"

log "Configuring Mesa libclc SPIR-V data"
cmake -S "$PACKAGE_SOURCE/libclc" -B "$PACKAGE_BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_DATADIR=share \
    -DLLVM_DIR="$(llvm-config --cmakedir)" \
    -DLIBCLC_USE_SPIRV_BACKEND=OFF \
    -DLLVM_SPIRV="$translator" \
    '-DLIBCLC_TARGETS_TO_BUILD=spirv-mesa3d-;spirv64-mesa3d-'

log "Building Mesa libclc SPIR-V data"
cmake --build "$PACKAGE_BUILD" -j "$EFILINUX_JOBS"
DESTDIR="$PACKAGE_STAGING" cmake --install "$PACKAGE_BUILD"

for artifact in \
    usr/share/clc/spirv-mesa3d-.spv \
    usr/share/clc/spirv64-mesa3d-.spv \
    usr/share/pkgconfig/libclc.pc; do
    [[ -s "$PACKAGE_STAGING/$artifact" ]] || \
        die "libclc artifact is missing: /$artifact"
done
if find "$PACKAGE_STAGING" -type f ! -path '*/usr/share/clc/*.spv' \
    ! -path '*/usr/share/pkgconfig/libclc.pc' -print -quit | grep -q .; then
    die "unexpected files were installed by the minimal libclc build"
fi

merge_sysroot "$PACKAGE_STAGING"
