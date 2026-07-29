#!/usr/bin/env bash

set -euo pipefail

export GRAPHICAL_ACLOCAL_PATH="$EFILINUX_SYSROOT/usr/share/aclocal"

graphical_binary_package_restore() {
    local package=$1
    local producer=${2:-${BASH_SOURCE[1]}}

    binary_package_restore_sysroot \
        "$package" "$producer" \
        "$ROOT/003-graphical/config.sh" \
        "$ROOT/003-graphical/lib/build.sh"
}

graphical_binary_package_publish() {
    local package=$1
    local producer=${2:-${BASH_SOURCE[1]}}

    binary_package_publish_sysroot \
        "$package" "$producer" \
        "$ROOT/003-graphical/config.sh" \
        "$ROOT/003-graphical/lib/build.sh"
}

_graphical_python_path() {
    find "$EFILINUX_SYSROOT/usr/lib" -type d -path '*/site-packages' -print 2>/dev/null |
        paste -sd: -
}

graphical_prepare_archive() {
    local package=$1
    local archive_name=$2
    local sha256=$3
    local url=$4

    prepare_package "$package"
    download "$url" "$EFILINUX_DOWNLOADS/$archive_name"
    verify_sha256 "$sha256" "$EFILINUX_DOWNLOADS/$archive_name"
    extract_source "$EFILINUX_DOWNLOADS/$archive_name" "$PACKAGE_SOURCE"
}

graphical_meson_setup() {
    local source=$1
    local build=$2
    shift 2

    CC=gcc \
    CXX=g++ \
    CFLAGS="$(target_cflags)" \
    CXXFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    PYTHONPATH="$(_graphical_python_path)" \
        meson setup "$build" "$source" \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        --wrap-mode=nodownload \
        "$@"
}

graphical_meson_install() {
    local build=$1
    local staging=$2

    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        meson compile -C "$build" -j "$EFILINUX_JOBS"
    DESTDIR="$staging" \
    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        meson install -C "$build"
    graphical_normalize_pkg_config "$staging"
}

graphical_normalize_pkg_config() {
    local staging=$1
    local metadata

    while IFS= read -r -d '' metadata; do
        sed -i \
            -e "s# -I$EFILINUX_SYSROOT/usr/include##g" \
            -e "s# -L$EFILINUX_SYSROOT/usr/lib##g" \
            "$metadata"
    done < <(find "$staging/usr" -type f -name '*.pc' -print0 2>/dev/null)
}

graphical_autotools_configure() {
    local source=$1
    local build=$2
    shift 2

    cd "$source"
    ACLOCAL_PATH="$GRAPHICAL_ACLOCAL_PATH" autoreconf -fi
    cd "$build"
    CC=gcc \
    CXX=g++ \
    CFLAGS="$(target_cflags)" \
    CXXFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PYTHON=/usr/bin/python3 \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    PYTHONPATH="$(_graphical_python_path)" \
    ACLOCAL_PATH="$GRAPHICAL_ACLOCAL_PATH" \
        "$source/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        "$@"
}

graphical_release_configure() {
    local source=$1
    local build=$2
    shift 2

    cd "$build"
    CC=gcc \
    CXX=g++ \
    CFLAGS="$(target_cflags)" \
    CXXFLAGS="$(target_cflags)" \
    LDFLAGS="$(target_ldflags)" \
    PYTHON=/usr/bin/python3 \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    PYTHONPATH="$(_graphical_python_path)" \
        "$source/configure" \
        --prefix=/usr \
        --libdir=/usr/lib \
        "$@"
}

graphical_make_install() {
    local build=$1
    local staging=$2

    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        make -C "$build" -j"$EFILINUX_JOBS"
    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        make -C "$build" DESTDIR="$staging" install
    find "$staging/usr/lib" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
    graphical_normalize_pkg_config "$staging"
}

graphical_cmake_setup() {
    local source=$1
    local build=$2
    shift 2

    cmake -S "$source" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_SYSROOT="$EFILINUX_SYSROOT" \
        -DCMAKE_C_FLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
        -DCMAKE_CXX_FLAGS="-O2 -march=$EFILINUX_X86_64_LEVEL -mtune=generic" \
        -DCMAKE_EXE_LINKER_FLAGS="-B$EFILINUX_SYSROOT/usr/lib -Wl,-rpath-link,$EFILINUX_SYSROOT/usr/lib" \
        -DCMAKE_SHARED_LINKER_FLAGS="-B$EFILINUX_SYSROOT/usr/lib -Wl,-rpath-link,$EFILINUX_SYSROOT/usr/lib" \
        -DCMAKE_FIND_ROOT_PATH="$EFILINUX_SYSROOT" \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        "$@"
}

graphical_cmake_install() {
    local build=$1
    local staging=$2

    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        cmake --build "$build" -j "$EFILINUX_JOBS"
    DESTDIR="$staging" \
    LD_LIBRARY_PATH="$EFILINUX_SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        cmake --install "$build"
    graphical_normalize_pkg_config "$staging"
}
