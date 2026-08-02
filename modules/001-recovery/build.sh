#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=recovery
module_version=1
module_description='Disk imaging, filesystem recovery, Windows recovery, and forensic utilities'
module_max_size=$((64 * 1024 * 1024))
module_relocate_usr=true
module_components=(
    bzip2
    lz4
    testdisk
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
    libaio
    lvm2
    bc
    dialog
    jq
    netcat-traditional
    wget
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
    qt6-base
    uefitool
    recovery-launchers
)

module_main "$@"
"$MODULE_DIR/test.sh"
