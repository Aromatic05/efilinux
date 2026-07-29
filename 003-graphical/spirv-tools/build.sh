#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command cmake curl ninja python3 sha256sum tar
ensure_directories

package="spirv-tools-$SPIRV_TOOLS_VERSION"
prepare_package "$package"
headers_source="$EFILINUX_BUILD/sources/spirv-tools-headers-$SPIRV_TOOLS_HEADERS_COMMIT"
reset_directory "$headers_source"

archive="SPIRV-Tools-vulkan-sdk-$SPIRV_TOOLS_VERSION.tar.gz"
download \
    "https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/vulkan-sdk-$SPIRV_TOOLS_VERSION.tar.gz" \
    "$EFILINUX_DOWNLOADS/$archive"
verify_sha256 "$SPIRV_TOOLS_SHA256" "$EFILINUX_DOWNLOADS/$archive"
extract_source "$EFILINUX_DOWNLOADS/$archive" "$PACKAGE_SOURCE"

headers_archive="SPIRV-Headers-$SPIRV_TOOLS_HEADERS_COMMIT.tar.gz"
download \
    "https://github.com/KhronosGroup/SPIRV-Headers/archive/$SPIRV_TOOLS_HEADERS_COMMIT.tar.gz" \
    "$EFILINUX_DOWNLOADS/$headers_archive"
verify_sha256 "$SPIRV_TOOLS_HEADERS_SHA256" "$EFILINUX_DOWNLOADS/$headers_archive"
extract_source "$EFILINUX_DOWNLOADS/$headers_archive" "$headers_source"

log "Configuring target SPIRV-Tools libraries"
graphical_cmake_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
    -DBUILD_SHARED_LIBS=OFF \
    -DSPIRV-Headers_SOURCE_DIR="$headers_source" \
    -DSPIRV_TOOLS_BUILD_STATIC=ON \
    -DSPIRV_SKIP_EXECUTABLES=ON \
    -DSPIRV_SKIP_TESTS=ON \
    -DSPIRV_WERROR=OFF

log "Building target SPIRV-Tools libraries"
graphical_cmake_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"

rm -f \
    "$PACKAGE_STAGING/usr/lib/libSPIRV-Tools-shared.so" \
    "$PACKAGE_STAGING/usr/lib/pkgconfig/SPIRV-Tools-shared.pc" \
    "$PACKAGE_STAGING/usr/lib/libSPIRV-Tools-diff.a" \
    "$PACKAGE_STAGING/usr/lib/libSPIRV-Tools-lint.a" \
    "$PACKAGE_STAGING/usr/lib/libSPIRV-Tools-reduce.a"
rm -rf "$PACKAGE_STAGING/usr/lib/cmake"

for artifact in \
    usr/lib/libSPIRV-Tools.a \
    usr/lib/libSPIRV-Tools-opt.a \
    usr/lib/libSPIRV-Tools-link.a \
    usr/lib/pkgconfig/SPIRV-Tools.pc \
    usr/include/spirv-tools/libspirv.h \
    usr/include/spirv-tools/libspirv.hpp \
    usr/include/spirv-tools/optimizer.hpp \
    usr/include/spirv-tools/linker.hpp; do
    [[ -s "$PACKAGE_STAGING/$artifact" ]] || \
        die "target SPIRV-Tools artifact is missing: /$artifact"
done
if find "$PACKAGE_STAGING/usr/lib" -maxdepth 1 -type f \
    ! -name 'libSPIRV-Tools.a' \
    ! -name 'libSPIRV-Tools-opt.a' \
    ! -name 'libSPIRV-Tools-link.a' -print -quit | grep -q .; then
    die "unexpected SPIRV-Tools library leaked into target staging"
fi

merge_sysroot "$PACKAGE_STAGING"
