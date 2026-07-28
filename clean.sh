#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
source "$ROOT/config.sh"

rm -rf -- "$EFILINUX_BUILD" "$EFILINUX_TARGET"
