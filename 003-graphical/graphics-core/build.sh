#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command bison curl flex gcc make meson ninja pkg-config python3 sha256sum tar zstd
ensure_directories

if [[ ! -s "$EFILINUX_SYSROOT/usr/share/clc/spirv-mesa3d-.spv" ||
      ! -s "$EFILINUX_SYSROOT/usr/share/clc/spirv64-mesa3d-.spv" ||
      ! -s "$EFILINUX_SYSROOT/usr/share/pkgconfig/libclc.pc" ]]; then
    "$ROOT/003-graphical/libclc/build.sh"
fi

if [[ ! -s "$EFILINUX_SYSROOT/usr/lib/libSPIRV-Tools.a" ||
      ! -s "$EFILINUX_SYSROOT/usr/lib/libSPIRV-Tools-opt.a" ||
      ! -s "$EFILINUX_SYSROOT/usr/lib/libSPIRV-Tools-link.a" ||
      ! -s "$EFILINUX_SYSROOT/usr/lib/pkgconfig/SPIRV-Tools.pc" ]]; then
    "$ROOT/003-graphical/spirv-tools/build.sh"
fi

clang_headers_missing=0
for artifact in \
    usr/include/clang/Config/config.h \
    usr/include/clang/Driver/Driver.h \
    usr/lib/clang/22/include/opencl-c-base.h \
    usr/lib/clang/22/include/opencl-c.h; do
    [[ -s "$EFILINUX_SYSROOT/$artifact" ]] || clang_headers_missing=1
done
if ((clang_headers_missing)); then
    "$ROOT/003-graphical/clang/build.sh"
fi

build_meson_package() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    if graphical_binary_package_restore "$package"; then
        return
    fi
    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
}

build_meson_package \
    "libpciaccess-$LIBPCIACCESS_VERSION" \
    "libpciaccess-$LIBPCIACCESS_VERSION.tar.gz" \
    "$LIBPCIACCESS_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libpciaccess/-/archive/libpciaccess-$LIBPCIACCESS_VERSION/libpciaccess-libpciaccess-$LIBPCIACCESS_VERSION.tar.gz" \
    -Dzlib=enabled \
    -Dlinux-rom-fallback=false \
    -Dinstall-scanpci=false

build_meson_package \
    "libdrm-$LIBDRM_VERSION" \
    "libdrm-$LIBDRM_VERSION.tar.gz" \
    "$LIBDRM_SHA256" \
    "https://gitlab.freedesktop.org/mesa/drm/-/archive/libdrm-$LIBDRM_VERSION/drm-libdrm-$LIBDRM_VERSION.tar.gz" \
    -Dintel=enabled \
    -Dradeon=enabled \
    -Damdgpu=enabled \
    -Dnouveau=enabled \
    -Dvmwgfx=enabled \
    -Domap=disabled \
    -Dexynos=disabled \
    -Dfreedreno=disabled \
    -Dtegra=disabled \
    -Dvc4=disabled \
    -Detnaviv=disabled \
    -Dcairo-tests=disabled \
    -Dman-pages=disabled \
    -Dvalgrind=disabled \
    -Dtests=false \
    -Dinstall-test-programs=false

package="elfutils-$ELFUTILS_VERSION"
if ! graphical_binary_package_restore "$package"; then
    graphical_prepare_archive \
        "$package" \
        "elfutils-$ELFUTILS_VERSION.tar.bz2" \
        "$ELFUTILS_SHA256" \
        "https://sourceware.org/elfutils/ftp/$ELFUTILS_VERSION/elfutils-$ELFUTILS_VERSION.tar.bz2"
    log "Configuring libelf"
    graphical_release_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-debuginfod \
        --disable-libdebuginfod \
        --disable-nls \
        --disable-demangler \
        --without-bzlib \
        --without-lzma \
        --with-zstd
    log "Building libelf"
    graphical_make_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    graphical_binary_package_publish "$package"
fi

package="mesa-$MESA_VERSION"
if ! graphical_binary_package_restore "$package"; then
    graphical_prepare_archive \
        "$package" \
        "mesa-$MESA_VERSION.tar.xz" \
        "$MESA_SHA256" \
        "https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz"

    mesa_host_tools="$EFILINUX_BUILD/host-tools/$package"
    reset_directory "$mesa_host_tools"
    system_zstd=$(command -v zstd)
    cat > "$mesa_host_tools/zstd" <<EOF
#!/bin/sh
unset LD_LIBRARY_PATH
exec "$system_zstd" "\$@"
EOF
    chmod 0755 "$mesa_host_tools/zstd"
    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib" \
        "$mesa_host_tools/zstd" --version >/dev/null

    log "Configuring Mesa X11-only desktop drivers"
    PATH="$mesa_host_tools:$PATH" \
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
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
    log "Building Mesa"
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"

    if find "$PACKAGE_STAGING" -iname '*wayland*' -print -quit | grep -q .; then
        die "Wayland artifacts leaked into the Mesa staging tree"
    fi
    for driver in iris crocus radeonsi nouveau virtio_gpu swrast; do
        [[ -e "$PACKAGE_STAGING/usr/lib/dri/${driver}_dri.so" ]] || \
            die "Mesa driver is missing: ${driver}_dri.so"
    done

    graphical_binary_package_publish "$package"
fi
