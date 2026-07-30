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

depends=(elfutils gcc-libs glibc libdrm llvm xorg zlib zstd)
builddepends=(clang-headers libclc spirv-tools)
makedepends=(bison flex gcc meson ninja pkg-config python3 zstd)

prepare() {
    local archive="$downloaddir/mesa-$pkgver.tar.xz"
    download "https://archive.mesa3d.org/mesa-$pkgver.tar.xz" "$archive"
    checksum sha256 79e421c7ce18cd9e790b8375920325779f10798630bf30e0b22f1a21c8617122 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local wrapper_directory="$recipework/host-wrappers"
    local system_zstd
    mkdir -p "$wrapper_directory"
    system_zstd=$(command -v zstd)
    cat > "$wrapper_directory/zstd" <<WRAPPER
#!/usr/bin/env bash
unset LD_LIBRARY_PATH
exec "$system_zstd" "\$@"
WRAPPER
    chmod 0755 "$wrapper_directory/zstd"

    PATH="$wrapper_directory:$PATH" target_meson_setup "$srcdir/source" "$builddir" \
        -Dplatforms=x11 \
        -Degl-native-platform=x11 \
        -Dgallium-drivers=iris,crocus,radeonsi,nouveau,virgl,llvmpipe,softpipe \
        -Dvulkan-drivers= \
        -Dvideo-codecs= \
        -Dllvm=enabled \
        -Dshared-llvm=enabled \
        -Ddraw-use-llvm=true \
        -Damd-use-llvm=true \
        -Dspirv-tools=enabled \
        -Dstatic-libclc=all \
        -Dmesa-clc-bundle-headers=enabled \
        -Dinstall-mesa-clc=false \
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
