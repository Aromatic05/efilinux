#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
source "$ROOT/config.sh"

clean_packages=false

case ${1:-} in
    '') ;;
    --packages) clean_packages=true ;;
    *) printf 'usage: %s [--packages]\n' "$0" >&2; exit 2 ;;
esac

rm -rf -- "$EFILINUX_BUILD" "$EFILINUX_TARGET"
if [[ $clean_packages == true ]]; then
    rm -rf -- "$EFILINUX_PACKAGES"
fi
