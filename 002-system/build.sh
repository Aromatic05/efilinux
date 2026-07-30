#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/002-system/openssl"
run_component "$ROOT/002-system/linux-pam"
run_component "$ROOT/002-system/shadow"
run_component "$ROOT/002-system/sysvinit"
run_component "$ROOT/002-system/sysklogd"
run_component "$ROOT/002-system/udev"
run_component "$ROOT/002-system/libgudev"
run_component "$ROOT/002-system/expat"
run_component "$ROOT/002-system/dbus"

run_component "$ROOT/002-system/elogind"
run_component "$ROOT/002-system/polkit"
run_component "$ROOT/002-system/upower"

run_component "$ROOT/002-system/cronie"
run_component "$ROOT/002-system/iproute2"
run_component "$ROOT/002-system/iputils"
run_component "$ROOT/002-system/dhcpcd"
run_component "$ROOT/002-system/openssh"
run_component "$ROOT/002-system/iwd"
run_component "$ROOT/002-system/networkmanager"

run_component "$ROOT/002-system/pulseaudio"
run_component "$ROOT/002-system/pipewire"
run_component "$ROOT/002-system/wireplumber"

run_component "$ROOT/002-system/device-mapper"
run_component "$ROOT/002-system/cryptsetup"
run_component "$ROOT/002-system/libbytesize"
run_component "$ROOT/002-system/libnvme"
run_component "$ROOT/002-system/mdadm"
run_component "$ROOT/002-system/libblockdev"
run_component "$ROOT/002-system/udisks"
run_component "$ROOT/002-system/gvfs"

run_component "$ROOT/002-system/efilinux-system-config"
run_component "$ROOT/002-system/system-init"
run_component "$ROOT/002-system/image"
