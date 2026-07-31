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
    input_file "$recipedir/files/static-llvmpipe-components.patch" "$srcdir/static-llvmpipe-components.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

create_target_llvm_config_wrapper() {
    local wrapper_directory=$1
    local wrapper="$wrapper_directory/llvm-config"

    mkdir -p "$wrapper_directory"
    cat > "$wrapper" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

: "${EFILINUX_SYSROOT:?}"

target_prefix="$EFILINUX_SYSROOT/usr"
loader="$target_prefix/lib/ld-linux-x86-64.so.2"
program="$target_prefix/bin/llvm-config"

run_llvm_config() {
    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$loader" \
        --library-path "$target_prefix/lib" \
        "$program" "$@"
}

reported_prefix=$(run_llvm_config --prefix)
output=$(run_llvm_config "$@")
output=${output//"$reported_prefix"/"$target_prefix"}

case " $* " in
    *" --cppflags "*)
        output=${output//"-I$target_prefix/include"/}
        output=$(printf '%s\n' "$output" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
        ;;
esac

printf '%s\n' "$output"
WRAPPER
    chmod 0755 "$wrapper"
    TARGET_LLVM_CONFIG=$wrapper
}

build_mesa_clc_tools() {
    local wrapper_directory=$1
    local tools_build="$recipework/mesa-clc-build"
    local tools_directory="$recipework/host-tools"
    local mesa_clc vtn_bindgen2

    reset_directory "$tools_build"
    reset_directory "$tools_directory"

    LLVM_CONFIG="$TARGET_LLVM_CONFIG" \
    PATH="$wrapper_directory:$PATH" target_meson_setup "$srcdir/source" "$tools_build" \
        -Dplatforms=x11 \
        -Dgallium-drivers=iris,crocus \
        -Dvulkan-drivers= \
        -Dllvm=enabled \
        -Dshared-llvm=enabled \
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
    LLVM_CONFIG="$TARGET_LLVM_CONFIG" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    PYTHONPATH="$(target_python_path)" \
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
    create_target_llvm_config_wrapper "$wrapper_directory"
    LLVM_CONFIG=$TARGET_LLVM_CONFIG
    export LLVM_CONFIG
    build_mesa_clc_tools "$wrapper_directory"
    mesa_clc_tools=$MESA_CLC_TOOLS

    patch -d "$srcdir/source" -p1 < "$srcdir/static-llvmpipe-components.patch"

    CFLAGS+=" -ffunction-sections -fdata-sections"
    CXXFLAGS+=" -ffunction-sections -fdata-sections"
    LDFLAGS+=" -Wl,--gc-sections"
    export CFLAGS CXXFLAGS LDFLAGS

    PATH="$mesa_clc_tools:$wrapper_directory:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dplatforms=x11 \
        -Degl-native-platform=x11 \
        -Dgallium-drivers=iris,crocus,radeonsi,nouveau,virgl,llvmpipe,softpipe \
        -Dvulkan-drivers= \
        -Dvideo-codecs= \
        -Dllvm=enabled \
        -Dshared-llvm=disabled \
        -Ddraw-use-llvm=true \
        -Dllvm-orcjit=false \
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
