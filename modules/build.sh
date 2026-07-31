#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

[[ $# == 0 ]] || die "usage: $0"
shopt -s nullglob
modules=("$ROOT"/modules/[0-9][0-9][0-9]-*/build.sh)
((${#modules[@]} > 0)) || die 'no module build scripts are defined'
for module in "${modules[@]}"; do
    "$module"
done
