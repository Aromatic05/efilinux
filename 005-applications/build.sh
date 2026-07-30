#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

run_component "$ROOT/005-applications/libsigcxx"
run_component "$ROOT/005-applications/glibmm"
run_component "$ROOT/005-applications/cairomm"
run_component "$ROOT/005-applications/pangomm"
run_component "$ROOT/005-applications/atkmm"
run_component "$ROOT/005-applications/gtkmm"
run_component "$ROOT/005-applications/gtksourceview4"
run_component "$ROOT/005-applications/json-glib"
run_component "$ROOT/005-applications/xarchiver"
run_component "$ROOT/005-applications/mousepad"
run_component "$ROOT/005-applications/ristretto"
run_component "$ROOT/005-applications/pavucontrol"
run_component "$ROOT/005-applications/xfce4-taskmanager"
run_component "$ROOT/005-applications/xfce4-screenshooter"
run_component "$ROOT/005-applications/thunar-archive-plugin"
run_component "$ROOT/005-applications/galculator"
run_component "$ROOT/005-applications/gparted"
