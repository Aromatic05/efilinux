#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=busybox
pkgver=1.37.0

depends=(
    glibc
)
builddepends=(
    linux-headers
)
makedepends=(
    awk
    gcc
    make
    readelf
)

prepare() {
    local archive="$downloaddir/busybox-$pkgver.tar.bz2"

    download \
        "https://busybox.net/downloads/busybox-$pkgver.tar.bz2" \
        "$archive"
    checksum \
        sha256 \
        3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4 \
        "$archive"
    extract "$archive" "$srcdir/busybox"
    input_file "$recipedir/minimal.config" "$srcdir/minimal.config"
}

build() {
    local config_entry config_name

    log "Configuring BusyBox"
    make -C "$srcdir/busybox" O="$builddir" allnoconfig

    while IFS= read -r config_entry; do
        [[ -z "$config_entry" ]] && continue

        config_name=${config_entry%%=*}
        awk \
            -v name="$config_name" \
            -v entry="$config_entry" \
            '
                BEGIN {
                    disabled = "# " name " is not set"
                    prefix = name "="
                    replaced = 0
                }
                $0 == disabled || index($0, prefix) == 1 {
                    if (!replaced) {
                        print entry
                        replaced = 1
                    }
                    next
                }
                { print }
                END {
                    if (!replaced)
                        print entry
                }
            ' \
            "$builddir/.config" \
            > "$builddir/.config.tmp"
        mv "$builddir/.config.tmp" "$builddir/.config"
    done < "$srcdir/minimal.config"

    sed -i \
        "s@^CONFIG_SYSROOT=.*@CONFIG_SYSROOT=\"$EFILINUX_SYSROOT\"@" \
        "$builddir/.config"
    sed -i \
        "s@^CONFIG_EXTRA_CFLAGS=.*@CONFIG_EXTRA_CFLAGS=\"-B$EFILINUX_SYSROOT/usr/lib/ -march=$EFILINUX_X86_64_LEVEL -mtune=generic\"@" \
        "$builddir/.config"

    sleep 1
    make -C "$srcdir/busybox" O="$builddir" oldconfig < <(yes '')

    grep -qx 'CONFIG_FEATURE_MODUTILS_ALIAS=y' "$builddir/.config" || \
        die "BusyBox module alias support is disabled"
    grep -qx 'CONFIG_TEST1=y' "$builddir/.config" || \
        die "BusyBox [ applet is disabled"
    grep -qx 'CONFIG_DEFAULT_MODULES_DIR="/lib/modules"' "$builddir/.config" || \
        die "BusyBox default module directory is incorrect"
    grep -qx 'CONFIG_DEFAULT_DEPMOD_FILE="modules.dep"' "$builddir/.config" || \
        die "BusyBox depmod filename is incorrect"

    log "Building dynamically linked BusyBox against project glibc"
    make -C "$srcdir/busybox" \
        O="$builddir" \
        -j"$EFILINUX_JOBS" \
        CC="$CC" \
        HOSTCC=gcc

    make -C "$srcdir/busybox" \
        O="$builddir" \
        CONFIG_PREFIX="$develdir" \
        install
}

check() {
    LC_ALL=C readelf --program-headers "$develdir/bin/busybox" |
        grep -q 'Requesting program interpreter' || \
        die "BusyBox is not dynamically linked"
}

devel() {
    local applet
    local busybox_binary="$develdir/bin/busybox"

    install -d "$develdir/usr/bin"
    mv "$busybox_binary" "$develdir/usr/bin/busybox"
    rm -rf "$develdir/bin" "$develdir/sbin"
    find "$develdir/usr/bin" -type l -delete

    while IFS= read -r applet; do
        [[ "$applet" == busybox ]] && continue
        ln -s busybox "$develdir/usr/bin/$applet"
    done < <(env -u LD_PRELOAD -u LD_LIBRARY_PATH "$develdir/usr/bin/busybox" --list)

    strip_all "$develdir/usr/bin/busybox"
}

package() {
    package_keep \
        /usr/bin/busybox \
        /usr/bin/ash \
        /usr/bin/sh \
        /usr/bin/clear \
        /usr/bin/chroot \
        /usr/bin/cttyhack \
        /usr/bin/hostname \
        /usr/bin/killall \
        /usr/bin/mdev \
        /usr/bin/switch_root \
        /usr/bin/udhcpc \
        /usr/bin/vi
}

recipe_main "$@"
