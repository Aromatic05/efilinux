#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command autoreconf curl gcc make meson ninja python3 sha256sum tar
ensure_directories

build_autotools_data() {
    local package=$1
    local archive=$2
    local sha256=$3
    local url=$4
    shift 4

    graphical_prepare_archive "$package" "$archive" "$sha256" "$url"
    graphical_autotools_configure "$PACKAGE_SOURCE" "$PACKAGE_BUILD" "$@"
    graphical_make_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"
    merge_sysroot "$PACKAGE_STAGING"
}

build_autotools_data \
    "xorg-util-macros-$XORG_UTIL_MACROS_VERSION" \
    "xorg-util-macros-$XORG_UTIL_MACROS_VERSION.tar.gz" \
    "$XORG_UTIL_MACROS_SHA256" \
    "https://gitlab.freedesktop.org/xorg/util/macros/-/archive/util-macros-$XORG_UTIL_MACROS_VERSION/macros-util-macros-$XORG_UTIL_MACROS_VERSION.tar.gz"

build_autotools_data \
    "xorgproto-$XORGPROTO_VERSION" \
    "xorgproto-xorgproto-$XORGPROTO_VERSION.tar.gz" \
    "$XORGPROTO_SHA256" \
    "https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/archive/xorgproto-$XORGPROTO_VERSION/xorgproto-xorgproto-$XORGPROTO_VERSION.tar.gz" \
    --without-fop --without-xmlto

for root in "$PACKAGE_STAGING" "$EFILINUX_SYSROOT"; do
    rm -f \
        "$root/usr/include/X11/extensions/xwaylandproto.h" \
        "$root/usr/share/pkgconfig/xwaylandproto.pc" \
        "$root/usr/share/doc/xorgproto/xwaylandproto.txt"
done
if find "$EFILINUX_SYSROOT" -iname '*xwayland*' -print -quit | grep -q .; then
    die "Xwayland protocol artifacts leaked into the Stage 3 sysroot"
fi

build_autotools_data \
    "xcb-proto-$XCB_PROTO_VERSION" \
    "xcb-proto-xcb-proto-$XCB_PROTO_VERSION.tar.gz" \
    "$XCB_PROTO_SHA256" \
    "https://gitlab.freedesktop.org/xorg/proto/xcbproto/-/archive/xcb-proto-$XCB_PROTO_VERSION/xcbproto-xcb-proto-$XCB_PROTO_VERSION.tar.gz"

build_autotools_data \
    "xtrans-$XTRANS_VERSION" \
    "xtrans-xtrans-$XTRANS_VERSION.tar.gz" \
    "$XTRANS_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxtrans/-/archive/xtrans-$XTRANS_VERSION/libxtrans-xtrans-$XTRANS_VERSION.tar.gz"
