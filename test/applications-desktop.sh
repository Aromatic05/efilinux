#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)

require_text() {
    local file=$1 text=$2
    grep -Fq -- "$text" "$file" || {
        printf 'missing desktop application metadata: %s in %s\n' "$text" "$file" >&2
        exit 1
    }
}

desktop_profile="$ROOT/profiles/applications-desktop.packages"
gui_maintenance_profile="$ROOT/profiles/applications-gui-maintenance.packages"

for package in mousepad ristretto pavucontrol xfce4-taskmanager xfce4-screenshooter thunar-archive-plugin xarchiver galculator; do
    require_text "$desktop_profile" "$package"
done
if grep -Eq '^(gparted|parted)$' "$desktop_profile"; then
    printf 'destructive partition tools leaked into applications-desktop\n' >&2
    exit 1
fi
require_text "$gui_maintenance_profile" '@include applications-desktop.packages'
require_text "$gui_maintenance_profile" 'gparted'

while IFS=$'\t' read -r package desktop_entry icon_data; do
    recipe="$ROOT/005-applications/$package/build.sh"
    [[ -x "$recipe" ]] || {
        printf 'desktop application recipe is missing: %s\n' "$package" >&2
        exit 1
    }
    metadata=$("$recipe" --print-metadata)
    grep -Fq "\"pkgname\":\"$package\"" <<<"$metadata" || exit 1
    grep -Eq 'checksum sha256 [0-9a-f]{64} ' "$recipe" || exit 1
    require_text "$recipe" "$desktop_entry"
    require_text "$recipe" "$icon_data"
done <<'APPLICATIONS'
mousepad	/usr/share/applications/	/usr/share/icons/hicolor/
ristretto	/usr/share/applications/	/usr/share/icons/hicolor/
pavucontrol	/usr/share/applications/	/usr/share/pavucontrol/
xfce4-taskmanager	/usr/share/applications/	/usr/share/icons/hicolor/
xfce4-screenshooter	/usr/share/applications/	/usr/share/icons/hicolor/
thunar-archive-plugin	/usr/lib/thunarx-3/	/usr/share/icons/hicolor/
xarchiver	/usr/share/applications/xarchiver.desktop	/usr/share/icons/hicolor/
galculator	/usr/share/applications/	/usr/share/pixmaps
gparted	/usr/share/polkit-1/actions/	/usr/libexec/gpartedbin
APPLICATIONS

require_text "$ROOT/005-applications/thunar-archive-plugin/build.sh" 'xarchiver'
require_text "$ROOT/005-applications/gparted/build.sh" 'parted'
require_text "$ROOT/005-applications/gparted/build.sh" 'polkit'
require_text "$ROOT/005-applications/pavucontrol/build.sh" 'gtkmm'
require_text "$ROOT/005-applications/mousepad/build.sh" 'gtksourceview4'
