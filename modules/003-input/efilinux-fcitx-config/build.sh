#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=efilinux-fcitx-config
pkgver=1
depends=(fcitx5 glib gtk3)
builddepends=()
makedepends=(gcc pkg-config)

prepare() {
    input_tree "$recipedir/files" "$srcdir/files"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local compiler
    local -a flags
    compiler=$(target_compiler_wrapper gcc)
    mapfile -t flags < <(
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            pkg-config --cflags --libs gtk+-3.0 | xargs -n1
    )
    install -d -m0755 "$develdir/opt/fcitx5/bin" "$develdir/opt/fcitx5/share/efilinux"
    "$compiler" --sysroot="$EFILINUX_SYSROOT" $CFLAGS $CPPFLAGS \
        "$srcdir/files/fcitx-config.c" -o "$develdir/opt/fcitx5/bin/fcitx5-configtool" \
        "${flags[@]}" $LDFLAGS
    install -m0644 "$srcdir/files/profile" "$develdir/opt/fcitx5/share/efilinux/profile"
    install -d -m0755 "$develdir/usr/bin"
    cat > "$develdir/usr/bin/fcitx5-configtool" <<'WRAPPER'
#!/bin/sh
export LD_LIBRARY_PATH=/opt/fcitx5/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec /opt/fcitx5/bin/fcitx5-configtool "$@"
WRAPPER
    chmod 0755 "$develdir/usr/bin/fcitx5-configtool"
}

devel() {
    strip_all "$develdir/opt/fcitx5/bin"
}

package() {
    package_keep \
        /opt/fcitx5/bin/fcitx5-configtool \
        /opt/fcitx5/share/efilinux/profile \
        /usr/bin/fcitx5-configtool
}

recipe_main "$@"
