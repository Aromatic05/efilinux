#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/005-applications/file"
run_component "$ROOT/005-applications/less"
run_component "$ROOT/005-applications/curl"
run_component "$ROOT/005-applications/rsync"
run_component "$ROOT/005-applications/sevenzip"
run_component "$ROOT/005-applications/strace"
run_component "$ROOT/005-applications/lsof"
run_component "$ROOT/005-applications/dmidecode"
run_component "$ROOT/005-applications/pciutils"
run_component "$ROOT/005-applications/ddrescue"
run_component "$ROOT/005-applications/xarchiver"
run_component "$ROOT/005-applications/image"
