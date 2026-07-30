#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

"$ROOT/test/recipe.sh"
"$ROOT/test/layer-ownership.sh"
"$ROOT/test/applications-desktop.sh"
"$ROOT/test/runtime.sh"
"$ROOT/test/runtime-tools.sh"
"$ROOT/test/system.sh"
"$ROOT/test/fsmeta-replay.sh"
"$ROOT/test/desktop-services.sh"
"$ROOT/test/packages.sh"
"$ROOT/test/graphical-core.sh"
"$ROOT/test/graphical.sh"
"$ROOT/test/qogir-theme.sh"
"$ROOT/test/desktop.sh"
"$ROOT/test/screensaver-pam.sh"
"$ROOT/test/command-closure.sh"
"$ROOT/test/kernel.sh"
"$ROOT/test/boot-qemu.sh"
"$ROOT/test/boot-zxmod-qemu.sh"
"$ROOT/test/boot-graphical-qemu.sh"
