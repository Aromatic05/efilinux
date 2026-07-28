#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk curl gcc grep install make meson ninja pkg-config realpath sed sha256sum tar
ensure_directories

package="systemd-$UDEV_SYSTEMD_VERSION"
archive="$EFILINUX_DOWNLOADS/$package.tar.gz"
udev_lfs="udev-lfs-$UDEV_LFS_VERSION"
udev_lfs_archive="$EFILINUX_DOWNLOADS/$udev_lfs.tar.xz"

prepare_package "$package"
download "https://github.com/systemd/systemd/archive/v$UDEV_SYSTEMD_VERSION/$package.tar.gz" "$archive"
download "https://anduin.linuxfromscratch.org/LFS/$udev_lfs.tar.xz" "$udev_lfs_archive"
verify_sha256 "$UDEV_SYSTEMD_SHA256" "$archive"
verify_sha256 "$UDEV_LFS_SHA256" "$udev_lfs_archive"
extract_source "$archive" "$PACKAGE_SOURCE"

sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //' \
    -i "$PACKAGE_SOURCE/rules.d/50-udev-default.rules.in"
sed -i '/systemd-sysctl/s/^/#/' "$PACKAGE_SOURCE/rules.d/99-systemd.rules.in"
sed -e '/NETWORK_DIRS/s/systemd/udev/' \
    -i "$PACKAGE_SOURCE/src/libsystemd/sd-network/network-util.h"

log "Configuring standalone Udev"
CC=gcc CFLAGS="$(target_cflags)" LDFLAGS="$(target_ldflags)" \
PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
    meson setup "$PACKAGE_BUILD" "$PACKAGE_SOURCE" \
        --prefix=/usr --libdir=lib --buildtype=release \
        -Dmode=release -Dauto_features=disabled \
        -Dtests=false -Dfuzz-tests=false -Dman=disabled \
        -Ddev-kvm-mode=0660 -Dlink-udev-shared=false \
        -Dlogind=false -Dvconsole=false -Dutmp=false \
        -Dkmod=enabled -Dblkid=enabled -Dacl=enabled -Dhwdb=true

mapfile -t udev_helpers < <(
    awk -F "'" "/'name' :/ { print \$4 }" "$PACKAGE_SOURCE/src/udev/meson.build" |
        grep -v '^udevadm$'
)

cd "$PACKAGE_BUILD"
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
    "$PACKAGE_STAGING/etc/udev/hwdb.d" \
    "$PACKAGE_STAGING/etc/udev/rules.d" \
    "$PACKAGE_STAGING/etc/udev/network" \
    "$PACKAGE_STAGING/usr/bin" \
    "$PACKAGE_STAGING/usr/include" \
    "$PACKAGE_STAGING/usr/lib/pkgconfig" \
    "$PACKAGE_STAGING/usr/lib/udev/hwdb.d" \
    "$PACKAGE_STAGING/usr/lib/udev/network" \
    "$PACKAGE_STAGING/usr/lib/udev/rules.d" \
    "$PACKAGE_STAGING/usr/sbin" \
    "$PACKAGE_STAGING/usr/share/pkgconfig"

install -m755 udevadm "$PACKAGE_STAGING/usr/bin/udevadm"
install -m755 systemd-hwdb "$PACKAGE_STAGING/usr/bin/udev-hwdb"
ln -s ../bin/udevadm "$PACKAGE_STAGING/usr/sbin/udevd"
cp -a libudev.so libudev.so.1 "$libudev_target" "$PACKAGE_STAGING/usr/lib/"
install -m644 "$PACKAGE_SOURCE/src/libudev/libudev.h" "$PACKAGE_STAGING/usr/include/"
install -m644 src/libudev/*.pc "$PACKAGE_STAGING/usr/lib/pkgconfig/"
install -m644 src/udev/*.pc "$PACKAGE_STAGING/usr/share/pkgconfig/"
install -m644 "$PACKAGE_SOURCE/src/udev/udev.conf" "$PACKAGE_STAGING/etc/udev/"

install -m644 rules.d/* "$PACKAGE_STAGING/usr/lib/udev/rules.d/"
rm -f "$PACKAGE_STAGING/usr/lib/udev/rules.d/99-systemd.rules"
find "$PACKAGE_SOURCE/rules.d" -maxdepth 1 -type f -name '*.rules' \
    ! -name '*power-switch*' \
    ! -name '99-systemd.rules' \
    -exec install -m644 {} "$PACKAGE_STAGING/usr/lib/udev/rules.d/" \;
install -m644 "$PACKAGE_SOURCE/rules.d/README" "$PACKAGE_STAGING/usr/lib/udev/rules.d/"

install -m644 hwdb.d/* "$PACKAGE_STAGING/usr/lib/udev/hwdb.d/"
find "$PACKAGE_SOURCE/hwdb.d" -maxdepth 1 -type f -name '*.hwdb' \
    -exec install -m644 {} "$PACKAGE_STAGING/usr/lib/udev/hwdb.d/" \;
install -m644 "$PACKAGE_SOURCE/hwdb.d/README" "$PACKAGE_STAGING/usr/lib/udev/hwdb.d/"
install -m644 "$PACKAGE_SOURCE/network/99-default.link" "$PACKAGE_STAGING/usr/lib/udev/network/"

for helper in "${udev_helpers[@]}"; do
    install -m755 "$helper" "$PACKAGE_STAGING/usr/lib/udev/$helper"
done

tar -xf "$udev_lfs_archive" -C "$PACKAGE_BUILD"
make -f "$PACKAGE_BUILD/$udev_lfs/Makefile.lfs" \
    -C "$PACKAGE_BUILD" DESTDIR="$PACKAGE_STAGING" install

"$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \
    --library-path "$EFILINUX_SYSROOT/usr/lib" \
    "$PACKAGE_STAGING/usr/bin/udev-hwdb" \
    --root="$PACKAGE_STAGING" --strict update

merge_sysroot "$PACKAGE_STAGING"
