#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk file readelf tar timeout zstd
ensure_directories

work="$EFILINUX_TEST/remote-desktop-packages"
loader="$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2"
packages=(
    ffmpeg-libs
    gstreamer
    gst-plugins-base
    freerdp
    libsodium
    libssh
    libvncserver
    spice-gtk
    remmina
)

[[ -x "$loader" ]] || die "target glibc loader is missing"
reset_directory "$work"

for package in "${packages[@]}"; do
    package_materialize "$package" "$work/$package"
done

remmina="$work/remmina/usr/bin/remmina"
plugin_dir="$work/remmina/usr/lib/remmina/plugins"
for required in \
    "$remmina" \
    "$plugin_dir/remmina-plugin-rdp.so" \
    "$plugin_dir/remmina-plugin-vnc.so" \
    "$plugin_dir/remmina-plugin-spice.so" \
    "$plugin_dir/remmina-plugin-secret.so"; do
    [[ -x "$required" ]] || die "Remmina executable or protocol plugin is missing: $required"
done

mapfile -t plugins < <(find "$plugin_dir" -maxdepth 1 -type f -name '*.so' -printf '%f\n' | sort)
expected_plugins=(
    remmina-plugin-rdp.so
    remmina-plugin-secret.so
    remmina-plugin-spice.so
    remmina-plugin-vnc.so
)
[[ "${plugins[*]}" == "${expected_plugins[*]}" ]] ||
    die "unexpected Remmina plugin set: ${plugins[*]}"

[[ ! -e "$work/remmina/usr/share/remmina/external_tools" ]] ||
    die "Remmina external tools leaked into the minimal runtime"
mapfile -t themes < <(find "$work/remmina/usr/share/remmina/theme" -maxdepth 1 -type f -printf '%f\n' | sort)
(( ${#themes[@]} == 8 )) || die "Remmina terminal theme set is not trimmed to eight files"

for required in \
    "$work/remmina/usr/share/applications/org.remmina.Remmina.desktop" \
    "$work/remmina/usr/share/applications/org.remmina.Remmina-file.desktop" \
    "$work/remmina/usr/share/mime/packages/org.remmina.Remmina-mime.xml" \
    "$work/remmina/usr/share/locale/zh_CN/LC_MESSAGES/remmina.mo"; do
    [[ -r "$required" ]] || die "Remmina desktop integration file is missing: $required"
done

library_path=$(find "$work" -type d -path '*/usr/lib' -printf '%p:' | sed 's/:$//')
config_home="$work/config"
mkdir -p "$work/home" "$work/data" "$work/cache" "$config_home/remmina/plugins"
cp -f "$plugin_dir/"*.so "$config_home/remmina/plugins/"

full_version=$(
    HOME="$work/home" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_DATA_HOME="$work/data" \
    XDG_CACHE_HOME="$work/cache" \
    timeout 20 "$loader" \
        --library-path "$library_path:$EFILINUX_SYSROOT/usr/lib" \
        "$remmina" --full-version 2>&1
)

for protocol in RDP VNC SPICE; do
    grep -Eq "^${protocol}[[:space:]]+Protocol" <<<"$full_version" ||
        die "Remmina did not load the $protocol protocol plugin"
done
grep -Eq '^glibsecret[[:space:]]+Secret' <<<"$full_version" ||
    die "Remmina did not load the libsecret plugin"
grep -Fq 'H.264 Yes' <<<"$full_version" ||
    die "Remmina RDP plugin lacks H.264 support"
grep -Fq 'WITH_CUPS=OFF' <<<"$full_version" ||
    die "Remmina unexpectedly enabled CUPS"
if grep -Eq 'WITH_(WWW|X2GO|PYTHONLIBS|KF5WALLET|NEWS|STATS)=ON' <<<"$full_version"; then
    die "non-core Remmina feature leaked into the build"
fi

needed_of() {
    LC_ALL=C env -u LD_LIBRARY_PATH readelf -d "$1" |
        awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }'
}

needed_of "$remmina" | grep -Fxq libssh.so.4 || die "Remmina core lacks SSH/SFTP support"
needed_of "$remmina" | grep -Fxq libvte-2.91.so.0 || die "Remmina core lacks SSH terminal support"
needed_of "$plugin_dir/remmina-plugin-rdp.so" | grep -Fxq libfreerdp-client3.so.3 ||
    die "Remmina RDP plugin is not linked to FreeRDP"
needed_of "$plugin_dir/remmina-plugin-vnc.so" | grep -Fxq libvncclient.so.1 ||
    die "Remmina VNC plugin is not linked to LibVNCClient"
if needed_of "$plugin_dir/remmina-plugin-vnc.so" | grep -Fxq libvncserver.so.1; then
    die "Remmina VNC client plugin retains the unused VNC server library"
fi
freerdp_needed=$(
    while IFS= read -r binary; do
        file -b "$binary" | grep -q ELF || continue
        needed_of "$binary"
    done < <(find "$work/freerdp" -type f -print) | LC_ALL=C sort -u
)
grep -Fxq libswscale.so.9 <<<"$freerdp_needed" ||
    die "FreeRDP lacks its required FFmpeg scaling backend"
if grep -Fxq libavdevice.so.62 <<<"$freerdp_needed"; then
    die "FreeRDP retains the unused FFmpeg device library"
fi
needed_of "$plugin_dir/remmina-plugin-spice.so" | grep -Fxq libspice-client-glib-2.0.so.8 ||
    die "Remmina SPICE plugin is not linked to spice-gtk"

while IFS= read -r binary; do
    env -u LD_LIBRARY_PATH file -b "$binary" | grep -q ELF || continue
    if LC_ALL=C env -u LD_LIBRARY_PATH readelf -d "$binary" | grep -Eq 'RPATH|RUNPATH'; then
        die "remote desktop ELF contains an RPATH or RUNPATH: $binary"
    fi
    while IFS= read -r needed; do
        [[ -e "$EFILINUX_SYSROOT/usr/lib/$needed" ]] && continue
        find "$work" -path "*/usr/lib/$needed" -print -quit | grep -q . ||
            die "remote desktop ELF dependency is unavailable: $binary needs $needed"
    done < <(needed_of "$binary")
done < <(find "$work" -type f -print)

if find "$work" -type f \( \
    -path '*/include/*' -o -path '*/pkgconfig/*' -o -name '*.a' -o -name '*.la' -o \
    -path '*/man/*' -o -path '*/doc/*' -o -path '*/info/*' \
    \) -print -quit | grep -q .; then
    die "remote desktop packages contain development or documentation payload"
fi
if find "$work" -type f -path '*/locale/*' ! -path '*/locale/zh_CN/*' -print -quit |
    grep -q .; then
    die "remote desktop packages contain non-Chinese translations"
fi

runtime_packages=(freerdp libsodium libssh libvncserver spice-gtk remmina)
declare -A limits=(
    [freerdp]=1700000
    [libsodium]=240000
    [libssh]=250000
    [libvncserver]=300000
    [spice-gtk]=450000
    [remmina]=600000
)
total=0
for package in "${runtime_packages[@]}"; do
    size=$(tar -C "$work/$package" -cf - . | zstd -q -19 -c | wc -c)
    printf '%-16s %8d bytes (limit %d)\n' "$package" "$size" "${limits[$package]}"
    (( size <= limits[$package] )) || die "$package exceeds its remote desktop size budget"
    total=$((total + size))
done
(( total <= 3300000 )) || die "remote desktop runtime exceeds the 3.3 MB aggregate budget"

printf 'Remote desktop runtime payload total: %d bytes\n' "$total"
log "Remmina RDP, VNC, SSH/SFTP, SPICE, plugin loading, ELF closure, and size budgets passed"
