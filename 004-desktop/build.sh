#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/004-desktop/xfce"
run_component "$ROOT/004-desktop/libnma"
run_component "$ROOT/004-desktop/network-manager-applet"
run_component "$ROOT/004-desktop/efilinux-xfce-config"
run_component "$ROOT/004-desktop/image"
