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

package="libepoxy-$LIBEPOXY_VERSION"
if ! graphical_binary_package_restore "$package"; then
    graphical_prepare_archive \
        "$package" \
        "libepoxy-$LIBEPOXY_VERSION.tar.gz" \
        "$LIBEPOXY_SHA256" \
        "https://github.com/anholt/libepoxy/archive/refs/tags/$LIBEPOXY_VERSION.tar.gz"
    graphical_meson_setup "$PACKAGE_SOURCE" "$PACKAGE_BUILD" \
        -Ddocs=false \
        -Dtests=false \
        -Dglx=yes \
        -Degl=yes \
        -Dx11=true
    graphical_meson_install "$PACKAGE_BUILD" "$PACKAGE_STAGING"

    for artifact in \
        usr/lib/libepoxy.so.0 \
        usr/lib/pkgconfig/epoxy.pc \
        usr/include/epoxy/gl.h \
        usr/include/epoxy/egl.h; do
        [[ -e "$PACKAGE_STAGING/$artifact" ]] || \
            die "libepoxy artifact is missing: /$artifact"
    done

    graphical_binary_package_publish "$package"
fi
