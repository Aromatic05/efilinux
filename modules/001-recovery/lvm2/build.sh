#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"
source "$ROOT/lib/target-build.sh"

pkgname=lvm2
pkgver=2.03.41
depends=(device-mapper glibc libaio readline util-linux)
builddepends=(linux-headers)
makedepends=(gcc make pkg-config)

prepare() {
    local archive="$downloaddir/lvm2-$pkgver.tgz"
    download "https://sourceware.org/pub/lvm2/LVM2.$pkgver.tgz" "$archive"
    checksum sha256 d58011b845df8ec13816ca13ea6c39d4cb3d038cd2d7d387acdf5681ad7d6637 "$archive"
    extract "$archive" "$srcdir/source"
    input_shared_file "$ROOT/lib/target-build.sh" "$srcdir/target-build.sh"
}

build() {
    local config_root=/opt/efilinux/modules/recovery/etc/lvm

    target_release_configure "$srcdir/source" "$builddir" \
        --bindir=/usr/bin \
        --sbindir=/usr/bin \
        --libdir=/usr/lib \
        --disable-static_link \
        --enable-shared \
        --disable-cmirrord \
        --disable-lvmpolld \
        --disable-use-lvmpolld \
        --disable-use-lvmlockd \
        --disable-systemd-journal \
        --disable-sd-notify \
        --disable-udev_sync \
        --disable-udev_rules \
        --disable-udev-rule-exec-detection \
        --disable-dbus-service \
        --disable-notify-dbus \
        --disable-dmeventd \
        --disable-cmdlib \
        --disable-selinux \
        --disable-fsadm \
        --disable-lvmimportvdo \
        --without-systemd \
        --without-udev \
        --with-snapshots=internal \
        --with-mirrors=internal \
        --with-thin=internal \
        --with-cache=internal \
        --with-vdo=none \
        --with-writecache=internal \
        --with-integrity=internal \
        --with-default-pid-dir=/run/lvm \
        --with-default-dm-run-dir=/run \
        --with-default-run-dir=/run/lvm \
        --with-default-locking-dir=/run/lvm/lock \
        --with-confdir=/opt/efilinux/modules/recovery/etc \
        --with-default-system-dir="$config_root"
    make -C "$builddir" -j"$EFILINUX_JOBS" lib libdaemon tools
    make -C "$builddir/tools" \
        DESTDIR="$develdir" \
        install_tools_dynamic
    make -C "$builddir/conf" \
        DESTDIR="$develdir" \
        install_lvm2
}

devel() {
    find "$develdir" -type f \( -name '*.a' -o -name '*.la' \) -delete
    strip_all "$develdir/usr/bin"
}

package() {
    local -a keep=(
        /usr/bin/lvm
        /usr/bin/lvchange
        /usr/bin/lvcreate
        /usr/bin/lvdisplay
        /usr/bin/lvremove
        /usr/bin/lvscan
        /usr/bin/lvs
        /usr/bin/pvchange
        /usr/bin/pvcreate
        /usr/bin/pvdisplay
        /usr/bin/pvremove
        /usr/bin/pvscan
        /usr/bin/pvs
        /usr/bin/vgchange
        /usr/bin/vgcreate
        /usr/bin/vgdisplay
        /usr/bin/vgremove
        /usr/bin/vgscan
        /usr/bin/vgs
    )
    [[ ! -d "$pkgdir/opt/efilinux/modules/recovery/etc/lvm" ]] ||
        keep+=(/opt/efilinux/modules/recovery/etc/lvm/)
    package_keep "${keep[@]}"
}

recipe_main "$@"
