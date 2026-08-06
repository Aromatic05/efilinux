#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command cmp readelf
ensure_directories

rootfs="$EFILINUX_ROOTFS"
loader="$rootfs/usr/lib/ld-linux-x86-64.so.2"
library_path="$rootfs/usr/lib"
test_directory="$EFILINUX_TEST/runtime"

[[ -x "$rootfs/usr/bin/busybox" ]] || die "BusyBox is missing from target rootfs"
[[ -x "$rootfs/usr/bin/xz" ]] || die "xz is missing from target rootfs"
[[ -x "$rootfs/usr/bin/zstd" ]] || die "zstd is missing from target rootfs"
[[ -x "$rootfs/usr/bin/locale" ]] || die "locale is missing from target rootfs"
[[ -x "$rootfs/usr/bin/tput" ]] || die "tput is missing from target rootfs"
[[ -x "$rootfs/usr/bin/infocmp" ]] || die "infocmp is missing from target rootfs"
[[ -x "$loader" ]] || die "glibc loader is missing from target rootfs"
[[ -f "$rootfs/usr/lib/locale/locale-archive" ]] || \
    die "compiled locale archive is missing from target rootfs"

assert_link() {
    local path=$1
    local expected=$2
    [[ -L "$rootfs$path" ]] || die "$path is not a symbolic link"
    [[ $(readlink "$rootfs$path") == "$expected" ]] || \
        die "$path does not point to $expected"
}

assert_link /bin usr/bin
assert_link /sbin usr/bin
assert_link /lib usr/lib
assert_link /lib64 usr/lib
assert_link /usr/sbin bin
assert_link /usr/bin/sh bash

required_applets=(
    ash cat chroot clear cp cttyhack dmesg hostname killall ls mdev mkdir mount mv
    rm sh switch_root sync udhcpc umount vi
)

busybox_applets=$(
    "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/busybox" --list
)
for applet in "${required_applets[@]}"; do
    grep -qx "$applet" <<< "$busybox_applets" || \
        die "required BusyBox applet is not enabled: $applet"
done

for replaced_applet in ip ping; do
    if grep -qx "$replaced_applet" <<< "$busybox_applets"; then
        die "BusyBox still provides replaced network applet: $replaced_applet"
    fi
done

rescue_links=(ash chroot clear cttyhack hostname killall mdev switch_root udhcpc vi)
for applet in "${rescue_links[@]}"; do
    [[ -L "$rootfs/usr/bin/$applet" ]] || die "BusyBox rescue link is missing: $applet"
    [[ $(readlink -- "$rootfs/usr/bin/$applet") == busybox ]] ||
        die "BusyBox rescue link has the wrong target: $applet"
done

"$loader" --library-path "$library_path" "$rootfs/usr/bin/sh" -c \
    'command -v realpath >/dev/null' ||
    die "/bin/sh does not provide the command builtin required by desktop scripts"
for standard_command in awk cat chmod chown cp cpio cut date dd df diff dmesg du env     expr find free grep gzip head id kill ln logger ls mkdir mkfifo mknod mount mv ps     readlink realpath rm rmdir sed setsid sleep sort stat sync tail tar tee test touch     tr true tty umount uname uniq uptime wc xargs; do
    if [[ -L "$rootfs/usr/bin/$standard_command" ]] &&
        [[ $(readlink -- "$rootfs/usr/bin/$standard_command") == busybox ]]; then
        die "standard runtime command still resolves to BusyBox: $standard_command"
    fi
done

available_locales=$(
    "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/locale" -a
)
grep -Fxiq C <<< "$available_locales" || die "required locale is missing: C"
grep -Eixq 'C\.(UTF-?8|utf8)' <<< "$available_locales" || \
    die "required locale is missing: C.UTF-8"
grep -Eixq 'en_US\.(UTF-?8|utf8)' <<< "$available_locales" || \
    die "required locale is missing: en_US.UTF-8"
grep -Eixq 'zh_CN\.(UTF-?8|utf8)' <<< "$available_locales" || \
    die "required locale is missing: zh_CN.UTF-8"

for locale_name in en_US.UTF-8 zh_CN.UTF-8; do
    LANG="$locale_name" "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/locale" charmap | grep -Fxq UTF-8 || \
        die "$locale_name does not use UTF-8"
done

for terminfo_entry in linux xterm xterm-256color screen screen-256color tmux tmux-256color; do
    TERM="$terminfo_entry" "$loader" --library-path "$library_path" \
        "$rootfs/usr/bin/infocmp" "$terminfo_entry" >/dev/null || \
        die "required terminfo entry is missing: $terminfo_entry"
done
TERM=xterm-256color "$loader" --library-path "$library_path" \
    "$rootfs/usr/bin/tput" colors | grep -Fxq 256 || \
    die "xterm-256color does not expose 256 colors"

for binary in busybox xz zstd; do
    if LC_ALL=C readelf --dynamic "$rootfs/usr/bin/$binary" |
        grep -E '(RPATH|RUNPATH)' |
        grep -F "$EFILINUX_ROOT" >/dev/null; then
        die "$binary contains a build-directory runtime path"
    fi
done

reset_directory "$test_directory"
printf 'EFI Linux runtime compression round trip\n' > "$test_directory/input"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/xz" \
    --stdout "$test_directory/input" > "$test_directory/input.xz"
"$loader" --library-path "$library_path" "$rootfs/usr/bin/xz" \
    --decompress --stdout "$test_directory/input.xz" > "$test_directory/xz.output"
cmp "$test_directory/input" "$test_directory/xz.output"

"$loader" --library-path "$library_path" "$rootfs/usr/bin/zstd" \
    --quiet --stdout "$test_directory/input" > "$test_directory/input.zst"
"$loader" --library-path "$library_path" "$rootfs/usr/bin/zstd" \
    --quiet --decompress --stdout "$test_directory/input.zst" > "$test_directory/zstd.output"
cmp "$test_directory/input" "$test_directory/zstd.output"

log "Target runtime, locales, and compression round trips passed"
