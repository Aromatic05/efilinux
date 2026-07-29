#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

"$ROOT/test/runtime.sh"
"$ROOT/test/runtime-tools.sh"
"$ROOT/test/system.sh"
"$ROOT/test/graphical-core.sh"
"$ROOT/test/graphical.sh"
"$ROOT/test/kernel.sh"
"$ROOT/test/boot-qemu.sh"
"$ROOT/test/boot-graphical-qemu.sh"
