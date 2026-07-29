#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command find readelf strip
ensure_directories

stage() {
    printf '%s/staging/%s' "$EFILINUX_BUILD" "$1"
}

install_program() {
    local package=$1
    local name=$2
    local installed_name=${3:-$name}
    local package_root
    local candidate

    package_root=$(stage "$package")
    for candidate in \
        "$package_root/usr/bin/$name" \
        "$package_root/usr/sbin/$name" \
        "$package_root/usr/libexec/$name"; do
        if [[ -e "$candidate" || -L "$candidate" ]]; then
            install_rootfs_program "$package" "$candidate" "$installed_name"
            return
        fi
    done
    die "$package program is missing: $name"
}

install_optional_program() {
    local package=$1
    local name=$2
    local package_root

    package_root=$(stage "$package")
    if [[ -e "$package_root/usr/bin/$name" || -L "$package_root/usr/bin/$name" || \
          -e "$package_root/usr/sbin/$name" || -L "$package_root/usr/sbin/$name" || \
          -e "$package_root/usr/libexec/$name" || -L "$package_root/usr/libexec/$name" ]]; then
        install_program "$package" "$name"
    fi
}

install_soname_family() {
    local package=$1
    local pattern=$2
    install_rootfs_library_family "$package" "$(stage "$package")" "$pattern"
}

install_soname_link() {
    local package=$1
    local soname=$2
    local package_root
    local target

    package_root=$(stage "$package")
    [[ -L "$package_root/usr/lib/$soname" ]] || \
        die "$package SONAME link is missing: $soname"
    target=$(readlink -- "$package_root/usr/lib/$soname")
    [[ -f "$package_root/usr/lib/$target" ]] || \
        die "$package SONAME target is missing: $target"
    install_rootfs_file "$package" "$package_root/usr/lib/$target" "/usr/lib/$target"
    install_rootfs_file "$package" "$package_root/usr/lib/$soname" "/usr/lib/$soname"
}

log "Installing formal module, disk, and filesystem maintenance tools"

for program in getfattr setfattr; do
    install_program "attr-$ATTR_VERSION" "$program"
done
for program in chacl getfacl setfacl; do
    install_program "acl-$ACL_VERSION" "$program"
done
for program in capsh getcap getpcaps setcap; do
    install_optional_program "libcap-$LIBCAP_VERSION" "$program"
done

install_program "kmod-$KMOD_VERSION" kmod
for program in depmod insmod lsmod modinfo modprobe rmmod; do
    install_program "kmod-$KMOD_VERSION" "$program"
done

for program in \
    blockdev blkid fdisk findmnt fsck hwclock losetup lsblk \
    mkfs mkswap mount mountpoint partx rfkill sfdisk \
    swapoff swapon umount wipefs; do
    install_program "util-linux-$UTIL_LINUX_VERSION" "$program"
done

for program in \
    dumpe2fs e2fsck e2image e2label mke2fs resize2fs tune2fs \
    fsck.ext2 fsck.ext3 fsck.ext4 mkfs.ext2 mkfs.ext3 mkfs.ext4; do
    install_program "e2fsprogs-$E2FSPROGS_VERSION" "$program"
done

for program in dumpkeys kbd_mode loadkeys setfont showkey; do
    install_program "kbd-$KBD_VERSION" "$program"
done

for program in btrfs btrfs-find-root btrfs-image btrfstune fsck.btrfs mkfs.btrfs; do
    install_program "btrfs-progs-v$BTRFS_PROGS_VERSION" "$program"
done

for program in \
    fsck.xfs mkfs.xfs xfs_admin xfs_db xfs_growfs xfs_info \
    xfs_io xfs_logprint xfs_mdrestore xfs_metadump xfs_repair; do
    install_program "xfsprogs-$XFS_PROGS_VERSION" "$program"
done

for program in fatlabel fsck.fat mkfs.fat; do
    install_program "dosfstools-$DOSFSTOOLS_VERSION" "$program"
done
for program in exfatlabel fsck.exfat mkfs.exfat tune.exfat; do
    install_program "exfatprogs-$EXFATPROGS_VERSION" "$program"
done
for program in \
    mkntfs ntfsclone ntfsfix ntfsinfo ntfslabel ntfsresize ntfsundelete; do
    install_program "ntfs-3g-$NTFS_3G_VERSION" "$program"
done
install_optional_program "ntfs-3g-$NTFS_3G_VERSION" mkfs.ntfs

log "Installing runtime shared-library closure"
install_rootfs_file \
    "gcc-runtime-$GCC_RUNTIME_VERSION" \
    "$(stage "gcc-runtime-$GCC_RUNTIME_VERSION")/usr/lib/libgcc_s.so.1" \
    /usr/lib/libgcc_s.so.1
install_soname_link "gcc-runtime-$GCC_RUNTIME_VERSION" libstdc++.so.6
install_soname_family "libffi-$LIBFFI_VERSION" 'libffi.so.8*'
install_soname_family "pcre2-$PCRE2_VERSION" 'libpcre2-8.so.0*'
install_soname_family "attr-$ATTR_VERSION" 'libattr.so.*'
install_soname_family "acl-$ACL_VERSION" 'libacl.so.*'
install_soname_family "libcap-$LIBCAP_VERSION" 'libcap.so.*'
install_soname_family "libxcrypt-$LIBXCRYPT_VERSION" 'libcrypt.so.*'
install_soname_family "lzo-$LZO_VERSION" 'liblzo2.so.*'
install_soname_family "kmod-$KMOD_VERSION" 'libkmod.so.*'
for library in libblkid libfdisk libmount libsmartcols libuuid; do
    install_soname_family "util-linux-$UTIL_LINUX_VERSION" "$library.so.*"
done
for library in libcom_err libe2p libext2fs libss; do
    install_soname_family "e2fsprogs-$E2FSPROGS_VERSION" "$library.so.*"
done
install_soname_family "btrfs-progs-v$BTRFS_PROGS_VERSION" 'libbtrfs.so.*'
install_soname_family "btrfs-progs-v$BTRFS_PROGS_VERSION" 'libbtrfsutil.so.*'
install_soname_family "inih-$INIH_VERSION" 'libinih.so.*'
for library in liburcu liburcu-bp liburcu-cds liburcu-common liburcu-mb liburcu-memb liburcu-qsbr; do
    install_soname_family "userspace-rcu-$USERSPACE_RCU_VERSION" "$library.so.*"
done
install_soname_family "xfsprogs-$XFS_PROGS_VERSION" 'libhandle.so.*'
install_soname_family "ntfs-3g-$NTFS_3G_VERSION" 'libntfs-3g.so.*'

log "Installing console and system data"
install_rootfs_file \
    "iana-etc-$IANA_ETC_VERSION" \
    "$(stage "iana-etc-$IANA_ETC_VERSION")/etc/protocols" \
    /etc/protocols
install_rootfs_file \
    "iana-etc-$IANA_ETC_VERSION" \
    "$(stage "iana-etc-$IANA_ETC_VERSION")/etc/services" \
    /etc/services
install_rootfs_tree \
    "tzdata-$TZDATA_VERSION" \
    "$(stage "tzdata-$TZDATA_VERSION")/usr/share/zoneinfo" \
    /usr/share/zoneinfo

for data_directory in keymaps consolefonts consoletrans unimaps; do
    source_directory="$(stage "kbd-$KBD_VERSION")/usr/share/$data_directory"
    if [[ -d "$source_directory" ]]; then
        install_rootfs_tree "kbd-$KBD_VERSION" "$source_directory" "/usr/share/$data_directory"
    fi
done

if [[ -f "$(stage "e2fsprogs-$E2FSPROGS_VERSION")/etc/mke2fs.conf" ]]; then
    install_rootfs_file \
        "e2fsprogs-$E2FSPROGS_VERSION" \
        "$(stage "e2fsprogs-$E2FSPROGS_VERSION")/etc/mke2fs.conf" \
        /etc/mke2fs.conf
fi

prepare_rootfs_destination tzdata /etc/localtime
ln -s /usr/share/zoneinfo/UTC "$EFILINUX_ROOTFS/etc/localtime"
record_rootfs_owner tzdata /etc/localtime

strip_rootfs_elf
