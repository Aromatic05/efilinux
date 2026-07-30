#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

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

require_text "$ROOT/005-applications/xfce4-screenshooter/build.sh" '0001-disable-imgur-upload.patch'
require_text "$ROOT/005-applications/thunar-archive-plugin/build.sh" 'xarchiver'
require_text "$ROOT/005-applications/gparted/build.sh" 'parted'
require_text "$ROOT/005-applications/gparted/build.sh" 'polkit'
require_text "$ROOT/005-applications/pavucontrol/build.sh" 'gtkmm'
require_text "$ROOT/005-applications/pavucontrol/build.sh" '0001-disable-event-sounds.patch'
require_text "$ROOT/005-applications/galculator/build.sh" '0001-fix-duplicate-preferences-definition.patch'
require_text "$ROOT/005-applications/galculator/build.sh" '/usr/share/galculator/ui/'
require_text "$ROOT/005-applications/galculator/build.sh" '-std=gnu17'
if grep -Eq 'depends=\([^)]*libcanberra|005-applications/libcanberra' \
    "$ROOT/005-applications/pavucontrol/build.sh" "$ROOT/005-applications/build.sh"; then
    printf 'Pavucontrol still pulls the optional libcanberra event-sound stack\n' >&2
    exit 1
fi
require_text "$ROOT/005-applications/mousepad/build.sh" 'gtksourceview4'
require_text "$ROOT/005-applications/mousepad/build.sh" '0001-use-target-gsettings-schema-path.patch'

require_command readelf tar
pavucontrol_archive=$(awk -F '\t' '$1 == "pavucontrol" { print $5; exit }' "$EFILINUX_PACKAGE_INDEX")
[[ -n "$pavucontrol_archive" ]] || die "pavucontrol package is missing from the package index"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
tar -xf "$EFILINUX_PACKAGES/$pavucontrol_archive" -C "$work" devel/usr/bin/pavucontrol
if readelf -d "$work/devel/usr/bin/pavucontrol" | grep -Fq 'libcanberra'; then
    die "pavucontrol package links the optional libcanberra event-sound stack"
fi

mousepad_archive=$(awk -F '\t' '$1 == "mousepad" { print $5; exit }' "$EFILINUX_PACKAGE_INDEX")
[[ -n "$mousepad_archive" ]] || die "mousepad package is missing from the package index"
mousepad_members="$work/mousepad.members"
tar -tf "$EFILINUX_PACKAGES/$mousepad_archive" > "$mousepad_members"
grep -Fxq 'devel/usr/share/glib-2.0/schemas/org.xfce.mousepad.gschema.xml' "$mousepad_members" || \
    die "mousepad package does not install its GSettings schema in the target path"
if grep -Eq '^devel/(home|tmp)/|/build/sysroot/' "$mousepad_members"; then
    die "mousepad package contains a build-host installation path"
fi

screenshooter_archive=$(awk -F '\t' '$1 == "xfce4-screenshooter" { print $5; exit }' "$EFILINUX_PACKAGE_INDEX")
[[ -n "$screenshooter_archive" ]] || die "xfce4-screenshooter package is missing from the package index"
tar -xf "$EFILINUX_PACKAGES/$screenshooter_archive" -C "$work" \
    devel/usr/bin/xfce4-screenshooter \
    devel/usr/lib/xfce4/panel/plugins/libscreenshooterplugin.so
for executable in \
    "$work/devel/usr/bin/xfce4-screenshooter" \
    "$work/devel/usr/lib/xfce4/panel/plugins/libscreenshooterplugin.so"; do
    if readelf -d "$executable" | grep -Eqi 'libsoup'; then
        die "xfce4-screenshooter package links the disabled libsoup upload stack"
    fi
done
screenshooter_help="$work/screenshooter.help"
"$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \
    --library-path "$work/devel/usr/lib:$EFILINUX_SYSROOT/usr/lib" \
    "$work/devel/usr/bin/xfce4-screenshooter" --help > "$screenshooter_help" 2>&1
if grep -Eqi 'imgur|upload' "$screenshooter_help"; then
    die "xfce4-screenshooter still exposes the disabled upload interface"
fi
screenshooter_install="$work/screenshooter.install"
tar -xOf "$EFILINUX_PACKAGES/$screenshooter_archive" .INSTALL > "$screenshooter_install"
for path in \
    /usr/bin/xfce4-screenshooter \
    /usr/lib/xfce4/panel/plugins/libscreenshooterplugin.so \
    /usr/share/applications/xfce4-screenshooter.desktop; do
    grep -Fxq "$path" "$screenshooter_install" || \
        die "xfce4-screenshooter install subset is missing $path"
done
if grep -Eqi 'imgur|libsoup|\.la$' "$screenshooter_install"; then
    die "xfce4-screenshooter install subset contains disabled or development payload"
fi
screenshooter_members="$work/screenshooter.members"
tar -tf "$EFILINUX_PACKAGES/$screenshooter_archive" > "$screenshooter_members"
if grep -Eqi 'imgur|libsoup|\.la$' "$screenshooter_members"; then
    die "xfce4-screenshooter devel archive contains disabled or libtool payload"
fi

galculator_archive=$(awk -F '\t' '$1 == "galculator" { print $5; exit }' "$EFILINUX_PACKAGE_INDEX")
[[ -n "$galculator_archive" ]] || die "galculator package is missing from the package index"
galculator_members="$work/galculator.members"
tar -tf "$EFILINUX_PACKAGES/$galculator_archive" > "$galculator_members"
for member in \
    devel/usr/bin/galculator \
    devel/usr/share/applications/galculator.desktop \
    devel/usr/share/galculator/ui/main_frame.ui \
    devel/usr/share/galculator/ui/basic_buttons_gtk3.ui \
    devel/usr/share/galculator/ui/scientific_buttons_gtk3.ui \
    devel/usr/share/galculator/ui/prefs_gtk3.ui; do
    grep -Fxq "$member" "$galculator_members" || die "galculator package is missing $member"
done
galculator_install="$work/galculator.install"
tar -xOf "$EFILINUX_PACKAGES/$galculator_archive" .INSTALL > "$galculator_install"
if grep -Eq 'galculator/ui/.*(gtk2|hildon|ume)' "$galculator_install"; then
    die "galculator runtime subset retains unused legacy UI definitions"
fi
for path in \
    /usr/share/galculator/ui/main_frame.ui \
    /usr/share/galculator/ui/basic_buttons_gtk3.ui \
    /usr/share/galculator/ui/scientific_buttons_gtk3.ui \
    /usr/share/galculator/ui/prefs_gtk3.ui; do
    grep -Fxq "$path" "$galculator_install" || die "galculator runtime subset is missing $path"
done
tar -xf "$EFILINUX_PACKAGES/$galculator_archive" -C "$work" devel/usr/bin/galculator
galculator_help="$work/galculator.help"
"$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2" \
    --library-path "$work/devel/usr/lib:$EFILINUX_SYSROOT/usr/lib" \
    "$work/devel/usr/bin/galculator" --help > "$galculator_help"
grep -Fq 'galculator v2.1.4' "$galculator_help" || die "galculator target binary did not execute"

parted_archive=$(awk -F '\t' '$1 == "parted" { print $5; exit }' "$EFILINUX_PACKAGE_INDEX")
[[ -n "$parted_archive" ]] || die "parted package is missing from the package index"
parted_install="$work/parted.install"
tar -xOf "$EFILINUX_PACKAGES/$parted_archive" .INSTALL > "$parted_install"
for path in \
    /usr/bin/parted \
    /usr/bin/partprobe \
    /usr/lib/libparted.so.2 \
    /usr/lib/libparted-fs-resize.so.0; do
    grep -Fxq "$path" "$parted_install" || die "parted runtime subset is missing $path"
done
