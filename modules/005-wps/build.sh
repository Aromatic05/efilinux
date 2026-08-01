#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# Keep the proprietary input and all derived state inside this module.
export EFILINUX_DOWNLOADS="$MODULE_DIR/build/downloads"
source "$MODULE_DIR/../lib/module.sh"

module_id=wps
module_version=10.1.0.5672-a21
module_description='Trimmed WPS Office Writer, Spreadsheets, and Presentation'
module_max_size=$((128 * 1024 * 1024))
module_components=(libpng12 wps-office)

module_main "$@"
"$MODULE_DIR/test.sh"
