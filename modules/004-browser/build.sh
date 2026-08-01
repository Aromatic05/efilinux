#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=browser
module_version=1
module_description='Lightweight GTK3 web browser'
module_max_size=$((16 * 1024 * 1024))
module_components=(netsurf)

module_main "$@"
"$MODULE_DIR/test.sh"
