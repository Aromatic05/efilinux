#!/usr/bin/env bash

set -euo pipefail

MODULE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
source "$MODULE_DIR/../lib/module.sh"

module_id=input
module_version=1
module_description='Fcitx5 Chinese input methods with Pinyin and table engines'
module_max_size=$((48 * 1024 * 1024))
module_post_load=hooks/post-load
module_pre_unload=hooks/pre-unload
module_components=(
    libuv
    iso-codes
    xcb-util-keysyms
    xcb-util-wm
    xcb-imdkit
    fmt
    libxkbcommon-x11-runtime
    fcitx5
    efilinux-fcitx-config
    boost
    libime
    opencc
    fcitx5-chinese-addons
    fcitx5-table-extra
)

module_main "$@"
"$MODULE_DIR/test.sh"
