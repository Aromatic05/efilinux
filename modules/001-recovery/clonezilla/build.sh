#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"
source "$ROOT/lib/recipe.sh"

pkgname=clonezilla
pkgver=5.16.25
depends=(
    bash bc bzip2 cifs-utils coreutils curl dialog dosfstools drbl-runtime e2fsprogs
    findutils gawk gptfdisk grep gzip jq lvm2 mdadm nbd nfs-utils ntfs-3g parted
    partclone procps-ng qemu-img sed smartmontools sshfs tar util-linux xfsprogs
    xz zstd
)
builddepends=()
makedepends=(make)

prepare() {
    local archive="$downloaddir/clonezilla-$pkgver.tar.gz"
    download "https://free.nchc.org.tw/drbl-core/src/stable/clonezilla-$pkgver.tar.gz" "$archive"
    checksum sha256 f8b6e4a1e31a074fc76a5ff7e66e550371b9f66b06936060a7e0dbf5d37f1684 "$archive"
    extract "$archive" "$srcdir/source"
}

build() {
    local module_root=/opt/efilinux/modules/recovery
    local share_root="$module_root/share/drbl"
    local config_root="$module_root/etc/drbl"
    local ocs_config_root="$module_root/etc/ocs"

    make -C "$srcdir/source" all

    install -d -m0755 \
        "$develdir/usr/bin" \
        "$develdir$share_root/sbin" \
        "$develdir$share_root/samples" \
        "$develdir$share_root/prerun/ocs" \
        "$develdir$share_root/postrun/ocs" \
        "$develdir$config_root" \
        "$develdir$ocs_config_root"

    cp -a "$srcdir/source/sbin/." "$develdir/usr/bin/"
    cp -a "$srcdir/source/bin/." "$develdir/usr/bin/"
    cp -a "$srcdir/source/scripts/sbin/." "$develdir$share_root/sbin/"
    cp -a "$srcdir/source/samples/." "$develdir$share_root/samples/"
    cp -a "$srcdir/source/prerun/ocs/." "$develdir$share_root/prerun/ocs/"
    cp -a "$srcdir/source/postrun/ocs/." "$develdir$share_root/postrun/ocs/"
    install -m0644 "$srcdir/source/conf/drbl-ocs.conf" \
        "$develdir$config_root/drbl-ocs.conf"

    find "$develdir/usr/bin" "$develdir$module_root" -type f -exec sed -i \
        -e "s#/usr/share/drbl#$share_root#g" \
        -e "s#/etc/drbl#$config_root#g" \
        -e "s#/etc/ocs#$ocs_config_root#g" \
        {} +

    find "$develdir/usr/bin" "$develdir$share_root" -type f -exec chmod 0755 {} +
    find "$develdir$module_root/etc" -type f -exec chmod 0644 {} +
}

devel() { :; }

package() {
    package_keep \
        /usr/bin/ \
        /opt/efilinux/modules/recovery/
}

recipe_main "$@"
