#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=udev
pkgver=257.8

udev_lfs_version=20230818

depends=(acl glibc kmod libcap util-linux)
builddepends=(linux-headers)
makedepends=(awk gcc grep install make meson ninja pkg-config realpath sed)

prepare() {
    local archive="$downloaddir/systemd-$pkgver.tar.gz"
    local udev_lfs_archive="$downloaddir/udev-lfs-$udev_lfs_version.tar.xz"

    download \
        "https://github.com/systemd/systemd/archive/v$pkgver/systemd-$pkgver.tar.gz" \
        "$archive"
    checksum sha256 f280278161446fe3838bedb970c7b3998043ad107f7627735a81483218c6f6f9 "$archive"
    extract "$archive" "$srcdir/udev"

    download \
        "https://anduin.linuxfromscratch.org/LFS/udev-lfs-$udev_lfs_version.tar.xz" \
        "$udev_lfs_archive"
    checksum sha256 104cdde52a898c648ce346a9ed1fbe9297514656534636a6584132cf2d7428d9 "$udev_lfs_archive"
    extract "$udev_lfs_archive" "$srcdir/udev-lfs"
}

build() {
    local libudev_target
    local -a udev_helpers=()
    local -a generated_targets=()

    sed -e 's/GROUP="render"/GROUP="video"/' \
        -e 's/GROUP="sgx", //' \
        -i "$srcdir/udev/rules.d/50-udev-default.rules.in"
    sed -i '/systemd-sysctl/s/^/#/' "$srcdir/udev/rules.d/99-systemd.rules.in"
    sed -e '/NETWORK_DIRS/s/systemd/udev/' \
        -i "$srcdir/udev/src/libsystemd/sd-network/network-util.h"

    log "Configuring standalone Udev"
    CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        meson setup "$builddir" "$srcdir/udev" \
            --prefix=/usr \
            --libdir=lib \
            --buildtype=release \
            -Dmode=release \
            -Dauto_features=disabled \
            -Dtests=false \
            -Dfuzz-tests=false \
            -Dman=disabled \
            -Ddev-kvm-mode=0660 \
            -Dlink-udev-shared=false \
            -Dlogind=false \
            -Dvconsole=false \
            -Dutmp=false \
            -Dkmod=enabled \
            -Dblkid=enabled \
            -Dacl=enabled \
            -Dhwdb=true

    mapfile -t udev_helpers < <(
        awk -F "'" "/'name' :/ { print \$4 }" "$srcdir/udev/src/udev/meson.build" |
            grep -v '^udevadm$'
    )

    cd "$builddir"
    mapfile -t generated_targets < <(
        ninja -n |
            grep -Eo '(src/(lib)?udev|rules.d|hwdb.d)/[^ ]*' |
            sort -u
    )
    libudev_target=$(realpath libudev.so --relative-to .)

    log "Building standalone Udev"
    ninja -j"$EFILINUX_JOBS" \
        udevadm systemd-hwdb "$libudev_target" \
        "${udev_helpers[@]}" "${generated_targets[@]}"

    install -d \
        "$develdir/etc/udev/hwdb.d" \
        "$develdir/etc/udev/rules.d" \
        "$develdir/etc/udev/network" \
        "$develdir/usr/bin" \
        "$develdir/usr/include" \
        "$develdir/usr/lib/pkgconfig" \
        "$develdir/usr/lib/udev/hwdb.d" \
        "$develdir/usr/lib/udev/network" \
        "$develdir/usr/lib/udev/rules.d" \
        "$develdir/usr/share/pkgconfig"

    install -m0755 udevadm "$develdir/usr/bin/udevadm"
    install -m0755 systemd-hwdb "$develdir/usr/bin/udev-hwdb"
    ln -s udevadm "$develdir/usr/bin/udevd"
    cp -a libudev.so libudev.so.1 "$libudev_target" "$develdir/usr/lib/"
    install -m0644 "$srcdir/udev/src/libudev/libudev.h" "$develdir/usr/include/"
    install -m0644 src/libudev/*.pc "$develdir/usr/lib/pkgconfig/"
    install -m0644 src/udev/*.pc "$develdir/usr/share/pkgconfig/"
    install -m0644 "$srcdir/udev/src/udev/udev.conf" "$develdir/etc/udev/"

    install -m0644 rules.d/* "$develdir/usr/lib/udev/rules.d/"
    rm -f "$develdir/usr/lib/udev/rules.d/99-systemd.rules"
    find "$srcdir/udev/rules.d" -maxdepth 1 -type f -name '*.rules' \
        ! -name '*power-switch*' \
        ! -name '99-systemd.rules' \
        -exec install -m0644 {} "$develdir/usr/lib/udev/rules.d/" \;
    install -m0644 "$srcdir/udev/rules.d/README" "$develdir/usr/lib/udev/rules.d/"

    install -m0644 hwdb.d/* "$develdir/usr/lib/udev/hwdb.d/"
    find "$srcdir/udev/hwdb.d" -maxdepth 1 -type f -name '*.hwdb' \
        -exec install -m0644 {} "$develdir/usr/lib/udev/hwdb.d/" \;
    install -m0644 "$srcdir/udev/hwdb.d/README" "$develdir/usr/lib/udev/hwdb.d/"
    install -m0644 "$srcdir/udev/network/99-default.link" "$develdir/usr/lib/udev/network/"

    for helper in "${udev_helpers[@]}"; do
        install -m0755 "$helper" "$develdir/usr/lib/udev/$helper"
    done

    cp -a "$srcdir/udev-lfs" "$builddir/udev-lfs-$udev_lfs_version"
    make -f "$srcdir/udev-lfs/Makefile.lfs" \
        -C "$builddir" DESTDIR="$develdir" install

    env -u LD_PRELOAD -u LD_LIBRARY_PATH \
        "$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \
        --library-path "$develdir/usr/lib:$EFILINUX_SYSROOT/usr/lib" \
        "$develdir/usr/bin/udev-hwdb" \
        --root="$develdir" --strict update
}

devel() {
    rm -rf "$develdir/usr/share/doc"
    strip_all "$develdir/usr/bin" "$develdir/usr/lib"
}

package() {
    local -a keep=(
        /etc/udev/
        /usr/bin/udevadm
        /usr/bin/udev-hwdb
        /usr/bin/udevd
        /usr/lib/udev/
    )
    package_add_library_family keep 'libudev.so.1*'
    package_keep "${keep[@]}"
}

recipe_main "$@"
