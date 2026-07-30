#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=xorg-server
pkgver=21.1.24

depends=(glibc libdrm libepoxy libinput mesa openssl pixman udev xkeyboard-config xorg)
builddepends=()
makedepends=(autoreconf gcc g++ make meson ninja pkg-config python3)

prepare() {
    local server="$downloaddir/xorg-server-$pkgver.tar.gz"
    local input="$downloaddir/xf86-input-libinput-1.5.0.tar.gz"
    local fbdev="$downloaddir/xf86-video-fbdev-0.5.1.tar.gz"

    download "https://gitlab.freedesktop.org/xorg/xserver/-/archive/xorg-server-$pkgver/xserver-xorg-server-$pkgver.tar.gz" "$server"
    checksum sha256 5051b8a339b9497cb573b57871fa7311a2d55c39c3d1cecd051804bbfe9c18e2 "$server"
    download "https://gitlab.freedesktop.org/xorg/driver/xf86-input-libinput/-/archive/xf86-input-libinput-1.5.0/xf86-input-libinput-xf86-input-libinput-1.5.0.tar.gz" "$input"
    checksum sha256 ccb4ed40b44c9b991d5dea27f8bef58aad34d15bf590847b48fefd5982c7d45c "$input"
    download "https://gitlab.freedesktop.org/xorg/driver/xf86-video-fbdev/-/archive/xf86-video-fbdev-0.5.1/xf86-video-fbdev-xf86-video-fbdev-0.5.1.tar.gz" "$fbdev"
    checksum sha256 699f938c7abffce1676b8f3520cf01234f2a5fc2b3af7ee5d08e4980a8044b4b "$fbdev"

    extract "$server" "$srcdir/server"
    extract "$input" "$srcdir/input-libinput"
    extract "$fbdev" "$srcdir/video-fbdev"
    input_file "$recipedir/files/dri-driver-path.patch" "$srcdir/dri-driver-path.patch"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

merge_component() {
    local stage=$1
    cp -a --reflink=auto "$stage/." "$develdir/"
    cp -a --reflink=auto "$stage/." "$EFILINUX_SYSROOT/"
}

build() {
    local original_sysroot=$EFILINUX_SYSROOT
    local internal_sysroot="$builddir/sysroot"
    local server_build="$builddir/server"
    local server_stage="$builddir/server-stage"
    local input_build="$builddir/input"
    local input_stage="$builddir/input-stage"
    local fbdev_build="$builddir/fbdev"
    local fbdev_stage="$builddir/fbdev-stage"

    reset_directory "$internal_sysroot"
    cp -a --reflink=auto "$original_sysroot/." "$internal_sysroot/"
    target_rebind_sysroot "$internal_sysroot"
    mkdir -p "$develdir"

    patch -d "$srcdir/server" -p1 < "$srcdir/dri-driver-path.patch"

    reset_directory "$server_build"
    reset_directory "$server_stage"
    target_meson_setup "$srcdir/server" "$server_build"         -Dxorg=true         -Dxephyr=false         -Dxnest=false         -Dxvfb=false         -Dxwin=false         -Dxquartz=false         -Dglamor=true         -Dglx=true         -Dxdmcp=false         -Dxdm-auth-1=false         -Dsecure-rpc=false         -Dlisten_tcp=false         -Dlisten_unix=true         -Dlisten_local=true         -Dint10=false         -Dsuid_wrapper=true         -Dpciaccess=true         -Dudev=true         -Dudev_kms=true         -Dhal=false         -Dsystemd_logind=false         -Dvgahw=false         -Ddpms=true         -Dxselinux=false         -Ddri1=false         -Ddri2=true         -Ddri3=true         -Ddrm=true         -Dagp=false         -Ddga=true         -Dxvmc=false         -Dxv=true         -Dsha1=libcrypto         -Dxf86-input-inputtest=false         -Ddocs=false         -Ddevel-docs=false         -Ddocs-pdf=false         -Dmodule_dir=xorg/modules         -Dlog_dir=/var/log         -Ddefault_font_path=/usr/share/fonts/truetype/dejavu         -Dxkb_dir=/usr/share/X11/xkb         -Dxkb_output_dir=/var/lib/xkb         -Dxkb_bin_dir=/usr/bin         -Dxkb_default_rules=evdev         -Dxkb_default_model=pc105         -Dxkb_default_layout=us         -Dfallback_input_driver=libinput
    target_meson_install "$server_build" "$server_stage"
    merge_component "$server_stage"

    reset_directory "$input_build"
    reset_directory "$input_stage"
    target_meson_setup "$srcdir/input-libinput" "$input_build"         -Dsdkdir=/usr/include/xorg         -Dxorg-module-dir=/usr/lib/xorg/modules/input         -Dxorg-conf-dir=/usr/share/X11/xorg.conf.d
    target_meson_install "$input_build" "$input_stage"
    install -Dm0644 "$srcdir/input-libinput/include/libinput-properties.h"         "$input_stage/usr/include/xorg/libinput-properties.h"
    merge_component "$input_stage"

    reset_directory "$fbdev_build"
    reset_directory "$fbdev_stage"
    target_autotools_configure "$srcdir/video-fbdev" "$fbdev_build"         --disable-static --disable-docs
    target_make_install "$fbdev_build" "$fbdev_stage"
    merge_component "$fbdev_stage"

    target_rebind_sysroot "$original_sysroot"
}

devel() {
    find "$develdir/usr/lib" -type f -name '*.la' -delete 2>/dev/null || true
    strip_all "$develdir/usr/bin" "$develdir/usr/lib" "$develdir/usr/libexec"
    chmod 4755 "$develdir/usr/libexec/Xorg.wrap"
}

package() {
    local -a keep=(
        /usr/bin/Xorg
        /usr/bin/X
        /usr/libexec/Xorg
        /usr/libexec/Xorg.wrap
        /usr/lib/xorg/
        /usr/share/X11/xorg.conf.d/10-quirks.conf
        /usr/share/X11/xorg.conf.d/40-libinput.conf
    )
    package_keep "${keep[@]}"
}

recipe_main "$@"
