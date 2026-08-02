#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=efilinux-live-manager
pkgver=1

depends=(efilinux-live glib glibc gtk3 polkit squashfs-tools zxmod)
builddepends=()
makedepends=(gcc pkg-config)

prepare() {
    input_file "$recipedir/src/main.c" "$srcdir/main.c"
    input_tree "$recipedir/files" "$srcdir/files"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local cc
    local -a gtk_flags
    cc=$(target_compiler_wrapper gcc)
    read -r -a gtk_flags <<< "$(
        PKG_CONFIG_PATH='' \
        PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
        PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
            pkg-config --cflags --libs gtk+-3.0 gio-2.0
    )"
    install -d -m0755 "$develdir/usr/bin"
    "$cc" \
        $CFLAGS $CPPFLAGS \
        -std=gnu17 -Wall -Wextra -Werror \
        "$srcdir/main.c" \
        -o "$develdir/usr/bin/efilinux-live-manager" \
        "${gtk_flags[@]}" \
        $LDFLAGS
    cp -a "$srcdir/files/." "$develdir/"
    chmod 0644 \
        "$develdir/usr/share/applications/efilinux-live-manager.desktop" \
        "$develdir/usr/share/icons/hicolor/scalable/apps/efilinux-live-manager.svg" \
        "$develdir/usr/share/polkit-1/actions/org.efilinux.live-manager.policy"
}

check() {
    local output
    output=$(
        env -u LD_PRELOAD -u LD_LIBRARY_PATH \
            "$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \
            --library-path "$EFILINUX_SYSROOT/usr/lib" \
            "$develdir/usr/bin/efilinux-live-manager" \
            --self-test
    )
    [[ $output == EFILINUX_LIVE_MANAGER_SELF_TEST_OK ]] ||
        die 'EFI Linux Live Manager model self-test failed'
}

devel() {
    strip_all "$develdir/usr/bin/efilinux-live-manager"
}

package() {
    package_keep \
        /usr/bin/efilinux-live-manager \
        /usr/share/applications/efilinux-live-manager.desktop \
        /usr/share/icons/hicolor/scalable/apps/efilinux-live-manager.svg \
        /usr/share/polkit-1/actions/org.efilinux.live-manager.policy
}

recipe_main "$@"
