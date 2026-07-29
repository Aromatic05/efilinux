#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=../config.sh
source "$ROOT/config.sh"
# shellcheck source=../003-graphical/config.sh
source "$ROOT/003-graphical/config.sh"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"

sysroot="$EFILINUX_SYSROOT"
loader="$sysroot/usr/lib/ld-linux-x86-64.so.2"
library_path="$sysroot/usr/lib"

export PKG_CONFIG_SYSROOT_DIR="$sysroot"
export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"

require_file() {
    local path=$1
    [[ -e "$sysroot$path" ]] || die "graphical core artifact is missing: $path"
}

require_pkg_version() {
    local package=$1
    local expected=$2
    local actual

    actual=$(pkg-config --modversion "$package" 2>/dev/null) || \
        die "graphical core pkg-config dependency is missing: $package"
    [[ $actual == "$expected" ]] || \
        die "$package version is $actual, expected $expected"
}

require_needed() {
    local path=$1
    local library=$2

    LC_ALL=C readelf -d "$sysroot$path" | grep -Fq "Shared library: [$library]" || \
        die "$path does not depend on $library"
}

require_pkg_version libevdev "$LIBEVDEV_VERSION"
require_pkg_version libinput "$LIBINPUT_VERSION"
require_pkg_version xkeyboard-config "$XKEYBOARD_CONFIG_VERSION"
require_pkg_version xkbcommon "$LIBXKBCOMMON_VERSION"
require_pkg_version xkbcommon-x11 "$LIBXKBCOMMON_VERSION"
require_pkg_version libpng "$LIBPNG_VERSION"
require_pkg_version libjpeg "$LIBJPEG_TURBO_VERSION"
require_pkg_version fontconfig "$FONTCONFIG_VERSION"
require_pkg_version harfbuzz "$HARFBUZZ_VERSION"
require_pkg_version fribidi "$FRIBIDI_VERSION"
require_pkg_version pixman-1 "$PIXMAN_VERSION"
require_pkg_version dri "$MESA_VERSION"
require_pkg_version egl "$MESA_VERSION"
require_pkg_version gbm "$MESA_VERSION"

for path in \
    /usr/lib/libLLVM.so.22.1 \
    /usr/lib/libgallium-26.1.5.so \
    /usr/lib/libGL.so.1 \
    /usr/lib/libEGL.so.1 \
    /usr/lib/libgbm.so.1 \
    /usr/lib/libevdev.so.2 \
    /usr/lib/libinput.so.10 \
    /usr/lib/libxkbcommon.so.0 \
    /usr/lib/libxkbcommon-x11.so.0 \
    /usr/lib/libpng16.so.16 \
    /usr/lib/libjpeg.so.62 \
    /usr/lib/libfreetype.so.6 \
    /usr/lib/libfontconfig.so.1 \
    /usr/lib/libharfbuzz.so.0 \
    /usr/lib/libfribidi.so.0 \
    /usr/lib/libpixman-1.so.0 \
    /usr/share/X11/xkb/rules/evdev \
    /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
    /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf \
    /etc/fonts/fonts.conf; do
    require_file "$path"
done

for driver in \
    iris_dri.so crocus_dri.so radeonsi_dri.so nouveau_dri.so \
    virtio_gpu_dri.so swrast_dri.so kms_swrast_dri.so; do
    path="$sysroot/usr/lib/dri/$driver"
    [[ -L $path && $(readlink -- "$path") == libdril_dri.so ]] || \
        die "Mesa DRI driver link is invalid: $driver"
done

# shellcheck disable=SC2153
expected_llvm_version=$LLVM_VERSION
llvm_version=$("$loader" --library-path "$library_path" \
    "$sysroot/usr/bin/llvm-config" --version)
[[ $llvm_version == "$expected_llvm_version" ]] || \
    die "target LLVM version is $llvm_version, expected $expected_llvm_version"
llvm_targets=$("$loader" --library-path "$library_path" \
    "$sysroot/usr/bin/llvm-config" --targets-built)
[[ $llvm_targets == 'X86 AMDGPU' ]] || \
    die "target LLVM set is '$llvm_targets', expected 'X86 AMDGPU'"

require_needed /usr/lib/libinput.so.10 libudev.so.1
require_needed /usr/lib/libinput.so.10 libevdev.so.2
require_needed /usr/lib/libxkbcommon-x11.so.0 libxcb-xkb.so.1
require_needed /usr/lib/libfreetype.so.6 libharfbuzz.so.0
require_needed /usr/lib/libfontconfig.so.1 libexpat.so.1
require_needed /usr/lib/libgallium-26.1.5.so libLLVM.so.22.1

if LC_ALL=C readelf -d "$sysroot/usr/lib/libgallium-26.1.5.so" | \
    grep -Ei 'clang|SPIRV-Tools|libclc|wayland'; then
    die "build-time compiler dependency leaked into Mesa runtime"
fi
if strings "$sysroot/usr/lib/libgallium-26.1.5.so" | grep -Fq '/usr/share/clc'; then
    die "dynamic libclc path leaked into Mesa runtime"
fi
if find "$sysroot/usr/lib" -maxdepth 1 \( -type f -o -type l \) \
    \( -name 'libclang*.a' -o -name 'libclang-cpp.so*' \) \
    -print -quit | grep -q .; then
    die "Clang library leaked into the target sysroot"
fi
if find "$sysroot" -iname '*wayland*' -print -quit | grep -q .; then
    die "Wayland artifact leaked into graphical core"
fi

for path in \
    /usr/share/clc/spirv-mesa3d-.spv \
    /usr/share/clc/spirv64-mesa3d-.spv \
    /usr/lib/libLLVMSPIRVLib.a \
    /usr/lib/libSPIRV-Tools.a \
    /usr/include/clang/Config/config.h \
    /usr/lib/clang/22/include/opencl-c.h; do
    require_file "$path"
done

font_count=$(find "$sysroot/usr/share/fonts/truetype/dejavu" \
    -maxdepth 1 -type f -name '*.ttf' | wc -l)
((font_count >= 20)) || die "DejaVu font set is incomplete: $font_count files"

log "003-graphical core LLVM, Mesa, input, text, fonts, and no-Wayland contract passed"
