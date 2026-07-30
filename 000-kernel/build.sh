#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/000-kernel/linux"
run_component "$ROOT/000-kernel/linux-firmware"
run_component "$ROOT/000-kernel/sof-firmware"
run_component "$ROOT/000-kernel/wireless-regdb"
run_component "$ROOT/000-kernel/image"
