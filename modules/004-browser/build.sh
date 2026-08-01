#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=browser
module_version=117.0.5938.149
module_description='Trimmed ungoogled Chromium 117 with Manifest V2 support and no bundled AI model service'
module_max_size=$((128 * 1024 * 1024))
module_components=(nspr nss libcups ungoogled-chromium)

module_main "$@"
"$MODULE_DIR/test.sh"
