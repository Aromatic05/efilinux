#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"

require_formal_program() {
    local name=$1
    local path="$rootfs/usr/bin/$name"

    [[ -x "$path" ]] || die "runtime tool is missing: $name"
    if [[ -L "$path" && $(readlink -- "$path") == busybox ]]; then
        die "BusyBox still owns formal runtime tool: $name"
    fi
}

for program in \
    depmod insmod lsmod modinfo modprobe rmmod \
    mount umount findmnt lsblk blkid hwclock swapon swapoff \
    fdisk sfdisk wipefs rfkill \
    e2fsck mke2fs mkfs.ext4 resize2fs tune2fs dumpe2fs \
    loadkeys setfont \
    btrfs mkfs.btrfs \
    xfs_repair mkfs.xfs \
    fsck.fat mkfs.fat \
    fsck.exfat mkfs.exfat \
    ntfsfix mkntfs ntfsresize; do
    require_formal_program "$program"
done

for library in \
    libattr.so.1 libacl.so.1 libcap.so.2 libcrypt.so.2 libkmod.so.2 \
    libblkid.so.1 libmount.so.1 libuuid.so.1 liblzo2.so.2; do
    [[ -e "$rootfs/usr/lib/$library" ]] || die "runtime library is missing: $library"
done

for data_file in \
    /etc/protocols \
    /etc/services \
    /usr/share/zoneinfo/UTC; do
    [[ -f "$rootfs$data_file" ]] || die "runtime data is missing: $data_file"
done

[[ -L "$rootfs/etc/localtime" ]] || die "/etc/localtime is not a symbolic link"
[[ $(readlink -- "$rootfs/etc/localtime") == /usr/share/zoneinfo/UTC ]] || \
    die "/etc/localtime does not default to UTC"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/modinfo" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/findmnt" --version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/btrfs" version >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/xfs_repair" -V >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/mkfs.exfat" -V >/dev/null
"$loader" --library-path "$library_path" "$rootfs/usr/bin/ntfsfix" --help >/dev/null 2>&1 || true

log "001-runtime maintenance tools and filesystem policy passed"
