#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/005-utils/squashfs-tools"
run_component "$ROOT/005-utils/zxmod"
run_component "$ROOT/005-utils/file"
run_component "$ROOT/005-utils/less"
run_component "$ROOT/005-utils/curl"
run_component "$ROOT/005-utils/rsync"
run_component "$ROOT/005-utils/sevenzip"
run_component "$ROOT/005-utils/strace"
run_component "$ROOT/005-utils/lsof"
run_component "$ROOT/005-utils/dmidecode"
run_component "$ROOT/005-utils/pciutils"
run_component "$ROOT/005-utils/libusb"
run_component "$ROOT/005-utils/usbutils"
run_component "$ROOT/005-utils/lm-sensors"
run_component "$ROOT/005-utils/efivar"
run_component "$ROOT/005-utils/efibootmgr"
run_component "$ROOT/005-utils/gptfdisk"
run_component "$ROOT/005-utils/smartmontools"
run_component "$ROOT/005-utils/nvme-cli"
run_component "$ROOT/005-utils/hdparm"
run_component "$ROOT/005-utils/ddrescue"
run_component "$ROOT/005-utils/parted"
run_component "$ROOT/005-utils/image"
