#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"


pkgname=mesa
pkgver=26.1.5

depends=(elfutils gcc-libs glibc libdrm xorg zlib zstd)
builddepends=(clang-headers libclc llvm spirv-tools)
makedepends=(bison flex gcc meson ninja pkg-config python3 zstd)

prepare() {
    local archive="$downloaddir/mesa-$pkgver.tar.xz"
    download "https://archive.mesa3d.org/mesa-$pkgver.tar.xz" "$archive"
    checksum sha256 79e421c7ce18cd9e790b8375920325779f10798630bf30e0b22f1a21c8617122 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build_mesa_clc_tools() {
    local wrapper_directory=$1
    local tools_build="$recipework/mesa-clc-build"
    local tools_directory="$recipework/host-tools"
    local mesa_clc vtn_bindgen2

    PATH="$wrapper_directory:$PATH" target_meson_setup "$srcdir/source" "$tools_build" \
        -Dplatforms=x11 \
        -Dgallium-drivers=iris,crocus \
        -Dvulkan-drivers= \
        -Dllvm=enabled \
        -Dmesa-clc=enabled \
        -Dspirv-tools=enabled \
        -Dstatic-libclc=all \
        -Dglx=disabled \
        -Degl=disabled \
        -Dgbm=disabled \
        -Dopengl=false \
        -Dgallium-va=disabled \
        -Dbuild-tests=false \
        -Denable-glcpp-tests=false \
        -Dtools=
    PATH="$wrapper_directory:$PATH" \
        meson compile -C "$tools_build" -j "$EFILINUX_JOBS" mesa_clc vtn_bindgen2

    mesa_clc="$tools_build/src/compiler/clc/mesa_clc"
    vtn_bindgen2="$tools_build/src/compiler/spirv/vtn_bindgen2"
    [[ -x $mesa_clc ]] || die "Mesa CLC tool is missing: $mesa_clc"
    [[ -x $vtn_bindgen2 ]] || die "Mesa SPIR-V tool is missing: $vtn_bindgen2"

    mkdir -p "$tools_directory"
    for tool in mesa_clc vtn_bindgen2; do
        cat > "$tools_directory/$tool" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH \\
    "$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \\
    --library-path "$EFILINUX_SYSROOT/usr/lib" \\
    "$([[ $tool == mesa_clc ]] && printf '%s' "$mesa_clc" || printf '%s' "$vtn_bindgen2")" "\$@"
WRAPPER
        chmod 0755 "$tools_directory/$tool"
    done
    MESA_CLC_TOOLS=$tools_directory
}

build() {
    local wrapper_directory="$recipework/host-wrappers"
    local mesa_clc_tools system_zstd
    mkdir -p "$wrapper_directory"
    system_zstd=$(command -v zstd)
    cat > "$wrapper_directory/zstd" <<WRAPPER
#!/usr/bin/env bash
unset LD_PRELOAD LD_LIBRARY_PATH
exec "$system_zstd" "\$@"
WRAPPER
    chmod 0755 "$wrapper_directory/zstd"
    build_mesa_clc_tools "$wrapper_directory"
    mesa_clc_tools=$MESA_CLC_TOOLS

    PATH="$mesa_clc_tools:$wrapper_directory:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dplatforms=x11 \
        -Degl-native-platform=x11 \
        -Dgallium-drivers=iris,crocus,radeonsi,nouveau,virgl,softpipe \
        -Dvulkan-drivers= \
        -Dvideo-codecs= \
        -Dllvm=disabled \
        -Ddraw-use-llvm=false \
        -Damd-use-llvm=false \
        -Dmesa-clc=system \
        -Dspirv-tools=disabled \
        -Dglx=dri \
        -Degl=enabled \
        -Dgbm=enabled \
        -Dopengl=true \
        -Dgles1=disabled \
        -Dgles2=disabled \
        -Dglvnd=disabled \
        -Dgallium-va=disabled \
        -Dvalgrind=disabled \
        -Dlibunwind=disabled \
        -Dlmsensors=disabled \
        -Dselinux=false \
        -Dbuild-tests=false \
        -Denable-glcpp-tests=false \
        -Dtools=
    target_meson_install "$builddir" "$develdir"
}

devel() {
    strip_all "$develdir/usr/lib"
}

package() {
    local -a keep=(/usr/lib/dri/ /usr/lib/gbm/ /usr/share/drirc.d/)
    package_add_library_family keep 'libEGL.so.*'
    package_add_library_family keep 'libGL.so.*'
    package_add_library_family keep 'libgbm.so.*'
    package_add_library_family keep 'libgallium-*.so'
    package_keep "${keep[@]}"
}

recipe_main "$@"
