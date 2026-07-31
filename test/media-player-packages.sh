#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk file readelf sha256sum tar timeout zstd
ensure_directories

work="$EFILINUX_TEST/media-player-packages"
loader="$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2"
packages=(
    ffmpeg-libs
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-libav
    parole
)

[[ -x "$loader" ]] || die "target glibc loader is missing"
reset_directory "$work"

for package in "${packages[@]}"; do
    package_materialize "$package" "$work/$package"
done

for required in \
    "$work/gstreamer/usr/bin/gst-inspect-1.0" \
    "$work/gstreamer/usr/bin/gst-launch-1.0" \
    "$work/gstreamer/usr/libexec/gstreamer-1.0/gst-plugin-scanner" \
    "$work/gst-libav/usr/lib/gstreamer-1.0/libgstlibav.so" \
    "$work/gst-plugins-bad/usr/lib/gstreamer-1.0/libgstvideoparsersbad.so" \
    "$work/parole/usr/bin/parole"; do
    [[ -x "$required" ]] || die "media runtime executable or plugin is missing: $required"
done

for required in \
    "$work/parole/usr/share/applications/org.xfce.Parole.desktop" \
    "$work/parole/usr/share/locale/zh_CN/LC_MESSAGES/parole.mo"; do
    [[ -r "$required" ]] || die "Parole integration file is missing: $required"
done

if find "$work" -type f \( \
    -path '*/include/*' -o -path '*/pkgconfig/*' -o -name '*.a' -o -name '*.la' -o \
    -path '*/man/*' -o -path '*/doc/*' -o -path '*/info/*' \
    \) -print -quit | grep -q .; then
    die "media packages contain development or documentation payload"
fi
if find "$work" -type f -path '*/locale/*' ! -path '*/locale/zh_CN/*' -print -quit |
    grep -q .; then
    die "media packages contain non-Chinese translation payload"
fi

library_path="$work/ffmpeg-libs/usr/lib:$work/gstreamer/usr/lib:$work/gst-plugins-base/usr/lib:$work/gst-plugins-bad/usr/lib:$EFILINUX_SYSROOT/usr/lib"
plugin_path="$work/gstreamer/usr/lib/gstreamer-1.0:$work/gst-plugins-base/usr/lib/gstreamer-1.0:$work/gst-plugins-good/usr/lib/gstreamer-1.0:$work/gst-plugins-bad/usr/lib/gstreamer-1.0:$work/gst-libav/usr/lib/gstreamer-1.0"
scanner="$work/gstreamer/usr/libexec/gstreamer-1.0/gst-plugin-scanner"
registry="$work/registry.bin"

mkdir -p "$work/home" "$work/cache" "$work/logs"
export HOME="$work/home"
export XDG_CACHE_HOME="$work/cache"
export LD_LIBRARY_PATH="$library_path"
export GST_PLUGIN_SYSTEM_PATH_1_0=
export GST_PLUGIN_PATH_1_0="$plugin_path"
export GST_PLUGIN_SCANNER="$scanner"
export GST_REGISTRY="$registry"

run_gst() {
    timeout 20 "$loader" --library-path "$library_path" \
        "$work/gstreamer/usr/bin/$1" "${@:2}"
}

for element in \
    playbin decodebin3 ximagesink alsasink pulsesink \
    h264parse h265parse av1parse vp9parse \
    aacparse flacparse mpegaudioparse \
    avdec_h264 avdec_h265 avdec_aac avdec_mp3 avdec_flac; do
    run_gst gst-inspect-1.0 "$element" >/dev/null ||
        die "required GStreamer element is unavailable: $element"
done

if run_gst gst-inspect-1.0 souphttpsrc >/dev/null 2>&1; then
    die "network streaming plugin leaked into the base media stack"
fi

sha256sum -c <<EOF
${MEDIA_FIXTURE_AAC_SHA256:-d3f1c15e24003a9dce69cfc53c31aaaba3b9d212c63e7932172a94ce74feedf1}  $ROOT/test/fixtures/media/sample.aac
${MEDIA_FIXTURE_FLAC_SHA256:-c5f1ecf0eca2953c4e7c1bfab5a7d19d31b4663104de5aa4cfe12202947e117f}  $ROOT/test/fixtures/media/sample.flac
${MEDIA_FIXTURE_H264_SHA256:-298379c407495b5595bdf9e236ef6028d2cec902f472b0cb492c3313719d50b3}  $ROOT/test/fixtures/media/sample.h264
${MEDIA_FIXTURE_MP3_SHA256:-dd5fb7250bb7fe62d5616229ce8db1d7b0449c892542e13f6f7cec1c697151c7}  $ROOT/test/fixtures/media/sample.mp3
EOF

run_pipeline() {
    local name=$1
    shift
    if ! run_gst gst-launch-1.0 -q "$@" >"$work/logs/$name.log" 2>&1; then
        cat "$work/logs/$name.log" >&2
        die "media decode pipeline failed: $name"
    fi
}

run_pipeline h264 \
    filesrc location="$ROOT/test/fixtures/media/sample.h264" ! \
    h264parse ! avdec_h264 ! fakesink
run_pipeline aac \
    filesrc location="$ROOT/test/fixtures/media/sample.aac" ! \
    aacparse ! avdec_aac ! fakesink
run_pipeline flac \
    filesrc location="$ROOT/test/fixtures/media/sample.flac" ! \
    flacparse ! avdec_flac ! fakesink
run_pipeline mp3 \
    filesrc location="$ROOT/test/fixtures/media/sample.mp3" ! \
    mpegaudioparse ! avdec_mp3 ! fakesink

parole_version=$(
    "$loader" --library-path "$library_path" \
        "$work/parole/usr/bin/parole" --version 2>&1
)
grep -Fq 'Parole Media Player 4.20.0' <<<"$parole_version" ||
    die "Parole version probe failed"

while IFS= read -r binary; do
    env -u LD_LIBRARY_PATH file -b "$binary" | grep -q ELF || continue
    while IFS= read -r needed; do
        if [[ -e "$EFILINUX_SYSROOT/usr/lib/$needed" ]]; then
            continue
        fi
        find "$work" -path "*/usr/lib/$needed" -print -quit | grep -q . ||
            die "media ELF dependency is unavailable: $binary needs $needed"
    done < <(LC_ALL=C env -u LD_LIBRARY_PATH readelf -d "$binary" |
        awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')
done < <(find "$work" -type f -print)

declare -A limits=(
    [ffmpeg-libs]=2400000
    [gstreamer]=800000
    [gst-plugins-base]=1100000
    [gst-plugins-good]=650000
    [gst-plugins-bad]=400000
    [gst-libav]=120000
    [parole]=260000
)

total=0
for package in "${packages[@]}"; do
    size=$(
        env -u LD_LIBRARY_PATH tar -C "$work/$package" -cf - . |
            env -u LD_LIBRARY_PATH zstd -q -19 -c |
            wc -c
    )
    printf '%-18s %8d bytes (limit %d)\n' "$package" "$size" "${limits[$package]}"
    (( size <= limits[$package] )) || die "$package runtime payload exceeds its size budget"
    total=$((total + size))
done
(( total <= 5600000 )) || die "media player stack exceeds the 5.6 MB aggregate budget"

printf 'Media player package payload total: %d bytes\n' "$total"
log "Parole, GStreamer elements, codec parsers, real decode pipelines, and size budgets passed"
