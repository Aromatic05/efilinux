#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/003-graphical/xorg-protocols"
run_component "$ROOT/003-graphical/xorg-libraries"
run_component "$ROOT/003-graphical/llvm"
run_component "$ROOT/003-graphical/llvm-spirv"
run_component "$ROOT/003-graphical/graphics-core"
run_component "$ROOT/003-graphical/input"
run_component "$ROOT/003-graphical/text"
run_component "$ROOT/003-graphical/xorg-server"
run_component "$ROOT/003-graphical/toolkit"
run_component "$ROOT/003-graphical/desktop-support"
run_component "$ROOT/003-graphical/xauth"
run_component "$ROOT/003-graphical/desktop-assets"
run_component "$ROOT/003-graphical/graphical-rootfs"
