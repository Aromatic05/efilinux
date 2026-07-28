#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

"$ROOT/test/runtime.sh"
"$ROOT/test/kernel.sh"
"$ROOT/test/boot-qemu.sh"
