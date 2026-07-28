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
run_component "$ROOT/002-system/expat"
run_component "$ROOT/002-system/dbus"
run_component "$ROOT/002-system/cronie"
run_component "$ROOT/002-system/iproute2"
run_component "$ROOT/002-system/iputils"
run_component "$ROOT/002-system/dhcpcd"
run_component "$ROOT/002-system/openssh"
run_component "$ROOT/002-system/system-rootfs"
