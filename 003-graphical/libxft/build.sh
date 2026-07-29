#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/003-graphical/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/003-graphical/lib/build.sh"

require_command curl gcc meson ninja pkg-config sha256sum tar
ensure_directories

for dependency in fontconfig freetype2 x11 xrender; do
    target_pkg_config --exists "$dependency" || \
        die "libXft dependency is missing: $dependency"
done

package="libXft-$LIBXFT_VERSION"
graphical_prepare_archive \
    "$package" \
    "libXft-libXft-$LIBXFT_VERSION.tar.gz" \
    "$LIBXFT_SHA256" \
    "https://gitlab.freedesktop.org/xorg/lib/libxft/-/archive/libXft-$LIBXFT_VERSION/libxft-libXft-$LIBXFT_VERSION.tar.gz"
graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD"
graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"

for artifact in \
    usr/lib/libXft.so.2 \
    usr/lib/pkgconfig/xft.pc \
    usr/include/X11/Xft/Xft.h; do
    [[ -e "$PACKAGE_STAGING/$artifact" ]] || \
        die "libXft artifact is missing: /$artifact"
done

merge_sysroot "$PACKAGE_STAGING"
