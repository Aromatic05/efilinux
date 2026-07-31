#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=recovery
module_version=1
module_description='Disk imaging, filesystem recovery, Windows recovery, and forensic utilities'
module_max_size=$((64 * 1024 * 1024))
module_components=(
    bzip2
    lz4
    testdisk
    fsarchiver
    partclone
    foremost
    fuse2
    mbedtls2
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
)

module_main "$@"
"$MODULE_DIR/test.sh"
