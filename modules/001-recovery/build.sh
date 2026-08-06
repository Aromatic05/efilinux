#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=recovery
module_version=2
module_description='Interactive local disk recovery, imaging, diagnostics, and UEFI maintenance'
module_max_size=$((128 * 1024 * 1024))
module_relocate_usr=true
module_components=(
    bzip2
    lz4
    lzop
    pigz
    pbzip2
    lzip
    lzlib
    plzip
    fsarchiver
    partclone
    foremost
    fuse2
    mbedtls2
    perl-runtime
    sleuthkit
    wimlib
    libldm
    dislocker
    sshfs
    chntpw
    libmd
    libbsd
    talloc
    krb5
    cifs-utils
    qemu-img
    nbd
    libevent
    libnl
    libtirpc
    rpcbind
    nfs-utils
    glibc-libmvec
    libaio
    fio
    lvm2
    bc
    dialog
    jq
    netcat-traditional
    wget
    coreutils-sha512sum
    drbl-runtime
    clonezilla
    grub
    ms-sys
    libburn
    libisofs
    libisoburn
    udftools
    flashrom
    xcb-util-image
    xcb-util-keysyms
    xcb-util-renderutil
    xcb-util-wm
    xcb-util-cursor
    libxkbcommon-x11
    qt6-base
    testdisk
    efibooteditor
    kdiskmark
    uefitool
    gsmartcontrol
    mesa-utils
    hardinfo2
    gtkhash
    gigolo
    usbimager
    btop
    mc
    ncdu
    libconfig
    ncurses-panelw
    nwipe
    grsync-gtk3
    slang
    newt
    networkmanager-nmtui
    recovery-launchers
)

module_main "$@"
"$MODULE_DIR/test.sh"
