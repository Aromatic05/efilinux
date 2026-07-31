#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

cli_recipes=(file less curl rsync sevenzip strace lsof dmidecode pciutils ddrescue parted)
gui_recipes=(xarchiver mousepad ristretto pavucontrol xfce4-taskmanager xfce4-screenshooter thunar-archive-plugin galculator gparted)

for recipe in "${cli_recipes[@]}"; do
    [[ -f "$ROOT/005-utils/$recipe/build.sh" ]] || {
        printf 'utility recipe is missing from 005-utils: %s\n' "$recipe" >&2
        exit 1
    }
    [[ ! -e "$ROOT/005-applications/$recipe" ]] || {
        printf 'CLI maintenance recipe remains in 005-applications: %s\n' "$recipe" >&2
        exit 1
    }
done

for recipe in "${gui_recipes[@]}"; do
    [[ -f "$ROOT/005-applications/$recipe/build.sh" ]] || {
        printf 'GUI recipe is missing from 005-applications: %s\n' "$recipe" >&2
        exit 1
    }
    [[ ! -e "$ROOT/005-utils/$recipe" ]] || {
        printf 'GUI recipe is incorrectly present in 005-utils: %s\n' "$recipe" >&2
        exit 1
    }
done

stale_layer="005-""zxmod"
stale_profile="applications-gui-maintenance|maintenance-image"
if rg -n --glob '!test/layer-ownership.sh' "$stale_layer|$stale_profile" \
    "$ROOT/build.sh" "$ROOT/005-utils" "$ROOT/005-applications" \
    "$ROOT/docs" "$ROOT/profiles" "$ROOT/test" "$ROOT/README.md"; then
    printf 'stale utility layer reference found\n' >&2
    exit 1
fi

printf 'Utility/application layer ownership is valid\n'
