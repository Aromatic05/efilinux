#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/package.sh"

require_command awk file gcc pkg-config readelf tar zstd
ensure_directories

work="$EFILINUX_TEST/pdf-viewer-packages"
loader="$EFILINUX_SYSROOT/usr/lib/ld-linux-x86-64.so.2"
reset_directory "$work"

for package in openjpeg poppler epdfview; do
    package_materialize "$package" "$work/$package"
done

[[ -e "$work/openjpeg/usr/lib/libopenjp2.so.7" ]] || die "OpenJPEG runtime library is missing"
find "$work/poppler/usr/lib" -maxdepth 1 -name 'libpoppler.so.*' -print -quit |
    grep -q . || die "Poppler core runtime library is missing"
[[ -e "$work/poppler/usr/lib/libpoppler-glib.so.8" ]] || die "Poppler GLib runtime library is missing"
[[ -x "$work/epdfview/usr/bin/epdfview" ]] || die "ePDFView executable is missing"
[[ -r "$work/epdfview/usr/share/applications/epdfview.desktop" ]] ||
    die "ePDFView desktop entry is missing"
[[ -r "$work/epdfview/usr/share/locale/zh_CN/LC_MESSAGES/epdfview.mo" ]] ||
    die "ePDFView Chinese translation is missing"

if find "$work/poppler/usr" -type f \( \
    -name 'pdftotext' -o -name 'pdfinfo' -o -name 'pdftocairo' -o \
    -name 'libpoppler-cpp.so*' -o -name 'libpoppler-qt*.so*' \
    \) -print -quit | grep -q .; then
    die "Poppler optional utilities or wrappers leaked into the runtime package"
fi

for package in openjpeg poppler epdfview; do
    if find "$work/$package" -type f \( \
        -path '*/include/*' -o -path '*/pkgconfig/*' -o -name '*.a' -o -name '*.la' -o \
        -path '*/man/*' -o -path '*/doc/*' -o -path '*/info/*' \
        \) -print -quit | grep -q .; then
        die "$package contains development or documentation payload"
    fi
done

probe="$work/poppler-render-probe"
pdf="$work/test1.pdf"
tar -xOf "$EFILINUX_DOWNLOADS/epdfview-gtk3-20200814.tar.xz" \
    epdfview-gtk3-20200814/tests/test1.pdf > "$pdf"

(
    source "$ROOT/profiles/makepkg.conf"
    PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
    PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
        gcc $CFLAGS "$ROOT/test/helpers/poppler-render-probe.c" -o "$probe" \
        $LDFLAGS \
        $(PKG_CONFIG_SYSROOT_DIR="$EFILINUX_SYSROOT" \
          PKG_CONFIG_LIBDIR="$EFILINUX_SYSROOT/usr/lib/pkgconfig:$EFILINUX_SYSROOT/usr/share/pkgconfig" \
          pkg-config --cflags --libs poppler-glib cairo)
)

probe_output=$(
    "$loader" \
        --library-path "$work/openjpeg/usr/lib:$work/poppler/usr/lib:$EFILINUX_SYSROOT/usr/lib" \
        "$probe" "$pdf"
)
grep -Eq '^EFILINUX_POPPLER_PAGES=[1-9][0-9]*$' <<<"$probe_output" ||
    die "Poppler probe did not open the test document"
grep -Eq '^EFILINUX_POPPLER_RENDER=[1-9][0-9]*$' <<<"$probe_output" ||
    die "Poppler probe did not render the test document"

while IFS= read -r binary; do
    file -b "$binary" | grep -q ELF || continue
    while IFS= read -r needed; do
        [[ -e "$work/openjpeg/usr/lib/$needed" || -e "$work/poppler/usr/lib/$needed" ||
           -e "$EFILINUX_SYSROOT/usr/lib/$needed" ]] ||
            die "PDF viewer dependency is unavailable: $binary needs $needed"
    done < <(LC_ALL=C readelf -d "$binary" |
        awk '/NEEDED/ { gsub(/\[|\]/, "", $NF); print $NF }')
done < <(find "$work/openjpeg" "$work/poppler" "$work/epdfview" -type f -print; printf '%s\n' "$probe")

declare -A limits=(
    [openjpeg]=230000
    [poppler]=1650000
    [epdfview]=90000
)
total=0
for package in openjpeg poppler epdfview; do
    size=$(tar -C "$work/$package" -cf - . | zstd -q -19 -c | wc -c)
    printf '%-10s %8d bytes (limit %d)\n' "$package" "$size" "${limits[$package]}"
    (( size <= limits[$package] )) || die "$package runtime payload exceeds its size budget"
    total=$((total + size))
done
(( total <= 1900000 )) || die "PDF viewer stack exceeds the 1.9 MB aggregate budget"
printf '%s\n' "$probe_output"
printf 'PDF viewer package payload total: %d bytes\n' "$total"
log "Poppler rendering and ePDFView package payloads passed"
