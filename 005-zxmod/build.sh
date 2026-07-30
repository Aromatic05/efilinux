#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/005-zxmod/squashfs-tools"
run_component "$ROOT/005-zxmod/zxmod"
run_component "$ROOT/005-zxmod/image"
