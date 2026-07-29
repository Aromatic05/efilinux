#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command autoreconf curl gcc make meson ninja pkg-config python3 sha256sum tar
ensure_directories

build_autotools_component() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_autotools_configure \
        "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        --disable-static --disable-docs "$@"
    graphical_make_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    merge_sysroot "$PACKAGE_STAGING"
}

build_meson_component() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    merge_sysroot "$PACKAGE_STAGING"
}

ensure_pkg_component() {
    local dependency=$1
    shift

    if ! target_pkg_config --exists "$dependency"; then
        "$@"
    fi
}

ensure_pkg_component epoxy "$ROOT/003-graphical/libepoxy/build.sh"

ensure_pkg_component fontutil build_autotools_component \
    "font-util-$FONT_UTIL_VERSION" \
    "font-util-font-util-$FONT_UTIL_VERSION.tar.gz" \
    "$FONT_UTIL_SHA256" \
    "https://gitlab.freedesktop.org/xorg/font/util/-/archive/font-util-$FONT_UTIL_VERSION/util-font-util-$FONT_UTIL_VERSION.tar.gz"

ensure_pkg_component fontenc build_autotools_component \
    "libfontenc-$LIBFONTENC_VERSION" \
    "libfontenc-libfontenc-$LIBFONTENC_VERSION.tar.gz" \
    "$LIBFONTENC_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libfontenc/-/archive/libfontenc-$LIBFONTENC_VERSION/libfontenc-libfontenc-$LIBFONTENC_VERSION.tar.gz"

ensure_pkg_component xfont2 build_autotools_component \
    "libXfont2-$LIBXFONT2_VERSION" \
    "libXfont2-libXfont2-$LIBXFONT2_VERSION.tar.gz" \
    "$LIBXFONT2_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxfont/-/archive/libXfont2-$LIBXFONT2_VERSION/libxfont-libXfont2-$LIBXFONT2_VERSION.tar.gz"

ensure_pkg_component xkbfile build_meson_component \
    "libxkbfile-$LIBXKBFILE_VERSION" \
    "libxkbfile-libxkbfile-$LIBXKBFILE_VERSION.tar.gz" \
    "$LIBXKBFILE_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxkbfile/-/archive/libxkbfile-$LIBXKBFILE_VERSION/libxkbfile-libxkbfile-$LIBXKBFILE_VERSION.tar.gz"

ensure_pkg_component libxcvt build_meson_component \
    "libxcvt-$LIBXCVT_VERSION" \
    "libxcvt-libxcvt-$LIBXCVT_VERSION.tar.gz" \
    "$LIBXCVT_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxcvt/-/archive/libxcvt-$LIBXCVT_VERSION/libxcvt-libxcvt-$LIBXCVT_VERSION.tar.gz"

if [[ ! -x "$EFILINUX_SYSROOT/usr/bin/xkbcomp" ]]; then
    build_meson_component \
        "xkbcomp-$XKBCOMP_VERSION" \
        "xkbcomp-xkbcomp-$XKBCOMP_VERSION.tar.gz" \
        "$XKBCOMP_SHA256" \
        "https://gitlab.freedesktop.org/xorg/app/xkbcomp/-/archive/xkbcomp-$XKBCOMP_VERSION/xkbcomp-xkbcomp-$XKBCOMP_VERSION.tar.gz" \
        -Dxkb-config-root=/usr/share/X11/xkb
fi

if [[ ! -x "$EFILINUX_SYSROOT/usr/bin/Xorg" ||
      ! -e "$EFILINUX_SYSROOT/usr/include/xorg/dgaproc.h" ]]; then
    package="xorg-server-$XORG_SERVER_VERSION"
    graphical_prepare_archive \
        "$package" \
        "xorg-server-xorg-server-$XORG_SERVER_VERSION.tar.gz" \
        "$XORG_SERVER_SHA256" \
        "https://gitlab.freedesktop.org/xorg/xserver/-/archive/xorg-server-$XORG_SERVER_VERSION/xserver-xorg-server-$XORG_SERVER_VERSION.tar.gz"
    log "Configuring Xorg Server"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
    -Dxorg=true \
    -Dxephyr=false \
    -Dxnest=false \
    -Dxvfb=false \
    -Dxwin=false \
    -Dxquartz=false \
    -Dglamor=true \
    -Dglx=true \
    -Dxdmcp=false \
    -Dxdm-auth-1=false \
    -Dsecure-rpc=false \
    -Dlisten_tcp=false \
    -Dlisten_unix=true \
    -Dlisten_local=true \
    -Dint10=false \
    -Dsuid_wrapper=false \
    -Dpciaccess=true \
    -Dudev=true \
    -Dudev_kms=true \
    -Dhal=false \
    -Dsystemd_logind=false \
    -Dvgahw=false \
    -Ddpms=true \
    -Dxselinux=false \
    -Ddri1=false \
    -Ddri2=true \
    -Ddri3=true \
    -Ddrm=true \
    -Dagp=false \
    -Ddga=true \
    -Dxvmc=false \
    -Dxv=true \
    -Dsha1=libcrypto \
    -Dxf86-input-inputtest=false \
    -Ddocs=false \
    -Ddevel-docs=false \
    -Ddocs-pdf=false \
    -Dmodule_dir=xorg/modules \
    -Dlog_dir=/var/log \
    -Ddefault_font_path=/usr/share/fonts/truetype/dejavu \
    -Dxkb_dir=/usr/share/X11/xkb \
    -Dxkb_output_dir=/var/lib/xkb \
    -Dxkb_bin_dir=/usr/bin \
    -Dxkb_default_rules=evdev \
    -Dxkb_default_model=pc105 \
    -Dxkb_default_layout=us \
        -Dfallback_input_driver=libinput
    log "Building Xorg Server"
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    merge_sysroot "$PACKAGE_STAGING"
fi

rm -f "$EFILINUX_SYSROOT/usr/lib/xorg/modules/libinput_drv.so"
build_meson_component \
    "xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION" \
    "xf86-input-libinput-xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION.tar.gz" \
    "$XF86_INPUT_LIBINPUT_SHA256" \
    "https://gitlab.freedesktop.org/xorg/driver/xf86-input-libinput/-/archive/xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION/xf86-input-libinput-xf86-input-libinput-$XF86_INPUT_LIBINPUT_VERSION.tar.gz" \
    -Dsdkdir=/usr/include/xorg \
    -Dxorg-module-dir=/usr/lib/xorg/modules/input \
    -Dxorg-conf-dir=/usr/share/X11/xorg.conf.d

build_autotools_component \
    "xf86-video-fbdev-$XF86_VIDEO_FBDEV_VERSION" \
    "xf86-video-fbdev-xf86-video-fbdev-$XF86_VIDEO_FBDEV_VERSION.tar.gz" \
    "$XF86_VIDEO_FBDEV_SHA256" \
    "https://gitlab.freedesktop.org/xorg/driver/xf86-video-fbdev/-/archive/xf86-video-fbdev-$XF86_VIDEO_FBDEV_VERSION/xf86-video-fbdev-xf86-video-fbdev-$XF86_VIDEO_FBDEV_VERSION.tar.gz"

build_autotools_component \
    "xinit-$XINIT_VERSION" \
    "xinit-xinit-$XINIT_VERSION.tar.gz" \
    "$XINIT_SHA256" \
    "https://gitlab.freedesktop.org/xorg/app/xinit/-/archive/xinit-$XINIT_VERSION/xinit-xinit-$XINIT_VERSION.tar.gz" \
    --with-xinitdir=/etc/X11/xinit

build_meson_component \
    "xwininfo-$XWININFO_VERSION" \
    "xwininfo-xwininfo-$XWININFO_VERSION.tar.gz" \
    "$XWININFO_SHA256" \
    "https://gitlab.freedesktop.org/xorg/app/xwininfo/-/archive/xwininfo-$XWININFO_VERSION/xwininfo-xwininfo-$XWININFO_VERSION.tar.gz" \
    -Dxcb-errors=disabled \
    -Dxcb-icccm=disabled

for artifact in \
    usr/bin/Xorg \
    usr/bin/xinit \
    usr/bin/startx \
    usr/bin/xkbcomp \
    usr/bin/xwininfo \
    usr/lib/xorg/modules/drivers/modesetting_drv.so \
    usr/lib/xorg/modules/drivers/fbdev_drv.so \
    usr/lib/xorg/modules/input/libinput_drv.so \
    usr/lib/xorg/modules/libglamoregl.so \
    usr/lib/xorg/modules/extensions/libglx.so \
    usr/share/X11/xorg.conf.d/40-libinput.conf; do
    [[ -e "$EFILINUX_SYSROOT/$artifact" ]] || \
        die "Xorg Server artifact is missing: /$artifact"
done

for dependency in epoxy xorg-server xorg-libinput; do
    target_pkg_config --exists "$dependency" || \
        die "Xorg Server pkg-config dependency is missing: $dependency"
done

if find "$EFILINUX_SYSROOT" -iname '*Xwayland*' -print -quit | grep -q .; then
    die "Xwayland leaked into the Xorg Server sysroot"
fi
