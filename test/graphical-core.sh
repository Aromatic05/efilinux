#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

sysroot="$EFILINUX_SYSROOT"
loader="$sysroot/usr/lib/ld-linux-x86-64.so.2"
library_path="$sysroot/usr/lib"

export PKG_CONFIG_SYSROOT_DIR="$sysroot"
export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"

recipe_version() {
    local recipe=$1
    "$recipe" --print-metadata | \
        python3 -c 'import json,sys; print(json.load(sys.stdin)["pkgver"])'
}

libevdev_version=$(recipe_version "$ROOT/003-graphical/libevdev/build.sh")
libinput_version=$(recipe_version "$ROOT/003-graphical/libinput/build.sh")
xkeyboard_config_version=$(recipe_version "$ROOT/003-graphical/xkeyboard-config/build.sh")
libxkbcommon_version=$(recipe_version "$ROOT/003-graphical/libxkbcommon/build.sh")
libpng_version=$(recipe_version "$ROOT/003-graphical/libpng/build.sh")
libjpeg_turbo_version=$(recipe_version "$ROOT/003-graphical/libjpeg-turbo/build.sh")
fontconfig_version=$(recipe_version "$ROOT/003-graphical/fontconfig/build.sh")
harfbuzz_version=$(recipe_version "$ROOT/003-graphical/harfbuzz/build.sh")
fribidi_version=$(recipe_version "$ROOT/003-graphical/fribidi/build.sh")
pixman_version=$(recipe_version "$ROOT/003-graphical/pixman/build.sh")
mesa_version=$(recipe_version "$ROOT/003-graphical/mesa/build.sh")
llvm_version_expected=$(recipe_version "$ROOT/003-graphical/llvm/build.sh")

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

require_pkg_version libevdev "$libevdev_version"
require_pkg_version libinput "$libinput_version"
require_pkg_version xkeyboard-config "$xkeyboard_config_version"
require_pkg_version xkbcommon "$libxkbcommon_version"
require_pkg_version xkbcommon-x11 "$libxkbcommon_version"
require_pkg_version libpng "$libpng_version"
require_pkg_version libjpeg "$libjpeg_turbo_version"
require_pkg_version fontconfig "$fontconfig_version"
require_pkg_version harfbuzz "$harfbuzz_version"
require_pkg_version fribidi "$fribidi_version"
require_pkg_version pixman-1 "$pixman_version"
require_pkg_version dri "$mesa_version"
require_pkg_version egl "$mesa_version"
require_pkg_version gbm "$mesa_version"

for path in \
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

llvm_library=$(find "$sysroot/usr/lib" -maxdepth 1 -type f -name 'libLLVM.so.*' -print -quit)
gallium_library=$(find "$sysroot/usr/lib" -maxdepth 1 -type f -name 'libgallium-*.so' -print -quit)
[[ -n "$llvm_library" ]] || die "target LLVM shared library is missing"
[[ -n "$gallium_library" ]] || die "Mesa Gallium shared library is missing"

dri_entry="$sysroot/usr/lib/dri/libdril_dri.so"
[[ -f $dri_entry ]] || die "Mesa DRI entry library is missing"
for driver in \
    iris_dri.so crocus_dri.so radeonsi_dri.so nouveau_dri.so \
    virtio_gpu_dri.so swrast_dri.so kms_swrast_dri.so; do
    path="$sysroot/usr/lib/dri/$driver"
    [[ -L $path ]] || die "Mesa DRI driver is not a symbolic link: $driver"
    [[ $(readlink -f -- "$path") == "$dri_entry" ]] || \
        die "Mesa DRI driver does not resolve to libdril: $driver"
done

llvm_version=$("$loader" --library-path "$library_path" \
    "$sysroot/usr/bin/llvm-config" --version)
[[ $llvm_version == "$llvm_version_expected" ]] || \
    die "target LLVM version is $llvm_version, expected $llvm_version_expected"
llvm_targets=$("$loader" --library-path "$library_path" \
    "$sysroot/usr/bin/llvm-config" --targets-built)
[[ $llvm_targets == 'X86 AMDGPU' ]] || \
    die "target LLVM set is '$llvm_targets', expected 'X86 AMDGPU'"

require_needed /usr/lib/libinput.so.10 libudev.so.1
require_needed /usr/lib/libinput.so.10 libevdev.so.2
require_needed /usr/lib/libxkbcommon-x11.so.0 libxcb-xkb.so.1
require_needed /usr/lib/libharfbuzz.so.0 libfreetype.so.6
require_needed /usr/lib/libfontconfig.so.1 libexpat.so.1
require_needed "${gallium_library#$sysroot}" "$(basename -- "$llvm_library")"

if LC_ALL=C readelf -d "$gallium_library" | \
    grep -Ei 'clang|SPIRV-Tools|libclc|wayland'; then
    die "build-time compiler dependency leaked into Mesa runtime"
fi
if strings "$gallium_library" | grep -Fq '/usr/share/clc'; then
    die "dynamic libclc path leaked into Mesa runtime"
fi
if find "$sysroot/usr/lib" -maxdepth 1 \( -type f -o -type l \) \
    \( -name 'libclang*.a' -o -name 'libclang-cpp.so*' \) \
    -print -quit | grep -q .; then
    die "Clang library leaked into the target sysroot"
fi
if find "$sysroot" \
    \( -name 'libwayland-*.so*' \
       -o -name 'wayland-*.pc' \
       -o -name 'wayland-*.h' \
       -o -name Xwayland \
       -o -path '*/wayland-protocols/*' \) \
    -print -quit | grep -q .; then
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
