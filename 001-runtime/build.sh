#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

ensure_directories
run_component "$ROOT/001-runtime/linux-headers"
run_component "$ROOT/001-runtime/glibc"
run_component "$ROOT/001-runtime/zlib"
run_component "$ROOT/001-runtime/xz"
run_component "$ROOT/001-runtime/zstd"
run_component "$ROOT/001-runtime/attr"
run_component "$ROOT/001-runtime/acl"
run_component "$ROOT/001-runtime/libcap"
run_component "$ROOT/001-runtime/libxcrypt"
run_component "$ROOT/001-runtime/lzo"
run_component "$ROOT/001-runtime/kmod"
run_component "$ROOT/001-runtime/busybox"
run_component "$ROOT/001-runtime/rootfs"
