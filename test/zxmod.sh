#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
builder="$ROOT/005-utils/zxmod/files/usr/bin/zxmod-build"
command_path="$ROOT/005-utils/zxmod/files/usr/bin/zxmod"
library="$ROOT/005-utils/zxmod/files/usr/lib/zxmod/common.sh"
completion="$ROOT/001-runtime/bash-completion/files/usr/share/bash-completion/completions/zxmod"
desktop="$ROOT/005-utils/zxmod/files/usr/share/applications/zxmod-load.desktop"
mime_xml="$ROOT/005-utils/zxmod/files/usr/share/mime/packages/application-vnd.efilinux.zxm.xml"
mimeapps="$ROOT/005-utils/zxmod/files/etc/xdg/mimeapps.list"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

require_command() {
    command -v "$1" >/dev/null || {
        printf 'zxmod test requires %s\n' "$1" >&2
        exit 1
    }
}

for name in bash busybox desktop-file-validate gio mksquashfs mount umount \
    unshare unsquashfs update-desktop-database update-mime-database xdg-mime; do
    require_command "$name"
done

mkdir -p \
    "$work/sample/usr/bin" \
    "$work/sample/usr/share/applications" \
    "$work/companion/opt/companion" \
    "$work/conflict/usr"
printf '#!/bin/sh\nprintf sample-command\\n\n' > "$work/sample/usr/bin/sample-command"
chmod 0755 "$work/sample/usr/bin/sample-command"
cat > "$work/sample/usr/share/applications/sample.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Sample Module
Exec=/usr/bin/sample-command
Icon=package-x-generic
Categories=Utility;
DESKTOP
printf 'companion payload\n' > "$work/companion/opt/companion/value"
printf 'conflict\n' > "$work/conflict/usr/base-file"

"$builder" --id sample --version 1.0 --arch "$(uname -m)" \
    --description 'runtime test module' "$work/sample" "$work/sample.zxm"
"$builder" --id companion --version 1.0 --arch "$(uname -m)" \
    "$work/companion" "$work/companion.zxm"
"$builder" --id conflict --version 1.0 --arch "$(uname -m)" \
    "$work/conflict" "$work/conflict.zxm"

unsquashfs -s "$work/sample.zxm" | grep -Eq '^Compression[[:space:]]+zstd$'
manifest=$(unsquashfs -cat "$work/sample.zxm" metadata/manifest)
grep -Fxq 'format=1' <<<"$manifest"
grep -Fxq 'id=sample' <<<"$manifest"
grep -Fxq "arch=$(uname -m)" <<<"$manifest"

for unsupported in inspect list enable disable startup; do
    if ZXMOD_LIBRARY="$library" "$command_path" "$unsupported" >/dev/null 2>&1; then
        printf 'zxmod accepted removed command: %s\n' "$unsupported" >&2
        exit 1
    fi
done

mkdir -p "$work/completion/run"
printf 'sample\t/source/sample.zxm\ncompanion\t/source/companion.zxm\n' \
    > "$work/completion/run/active"
ZXMOD_RUN_ROOT="$work/completion/run" bash --noprofile --norc -c '
    set -euo pipefail
    source "$1"
    COMP_WORDS=(zxmod "")
    COMP_CWORD=1
    _zxmod
    [[ " ${COMPREPLY[*]} " == *" load "* ]]
    [[ " ${COMPREPLY[*]} " == *" unload "* ]]

    COMP_WORDS=(zxmod load "$2/sam")
    COMP_CWORD=2
    _zxmod
    [[ " ${COMPREPLY[*]} " == *"$2/sample.zxm"* ]]

    COMP_WORDS=(zxmod unload sam)
    COMP_CWORD=2
    _zxmod
    [[ " ${COMPREPLY[*]} " == *" sample "* ]]
' bash "$completion" "$work"

xdg="$work/xdg"
mkdir -p "$xdg/share/mime/packages" "$xdg/share/applications" "$xdg/config"
cp "$mime_xml" "$xdg/share/mime/packages/"
cp "$desktop" "$xdg/share/applications/"
cp "$mimeapps" "$xdg/config/mimeapps.list"
XDG_DATA_HOME="$xdg/share" XDG_DATA_DIRS="$xdg/share" \
    XDG_CONFIG_HOME="$xdg/config" update-mime-database "$xdg/share/mime"
XDG_DATA_HOME="$xdg/share" XDG_DATA_DIRS="$xdg/share" \
    XDG_CONFIG_HOME="$xdg/config" update-desktop-database "$xdg/share/applications"
desktop-file-validate "$xdg/share/applications/zxmod-load.desktop"
content_type=$(XDG_DATA_HOME="$xdg/share" XDG_DATA_DIRS="$xdg/share" \
    XDG_CONFIG_HOME="$xdg/config" gio info -a standard::content-type \
    "$work/sample.zxm" | sed -n 's/^[[:space:]]*standard::content-type: //p')
[[ $content_type == application/vnd.efilinux.zxm ]]
default_handler=$(XDG_DATA_HOME="$xdg/share" XDG_DATA_DIRS="$xdg/share" \
    XDG_CONFIG_HOME="$xdg/config" xdg-mime query default "$content_type")
[[ $default_handler == zxmod-load.desktop ]]

mkdir -p "$work/invalid/usr"
printf 'bad\n' > "$work/invalid/unexpected"
if "$builder" --id invalid --version 1 --arch "$(uname -m)" \
    "$work/invalid" "$work/invalid.zxm" >/dev/null 2>&1; then
    printf 'zxmod builder accepted content outside usr/opt\n' >&2
    exit 1
fi

if ! unshare --user --map-root-user --mount --fork true 2>/dev/null; then
    printf 'zxmod runtime test skipped: user and mount namespaces are unavailable\n' >&2
    exit 0
fi

set +e
runtime_output=$(unshare --user --map-root-user --mount --fork bash -ceu '
    root=$1
    command_path=$2
    library=$3
    mount --make-rprivate /
    mkdir -p "$root/base/usr" "$root/base/opt" "$root/run"
    printf "base file\n" > "$root/base/usr/base-file"
    mkdir "$root/squashfs-probe"
    if ! mount -t squashfs -o ro "$root/sample.zxm" "$root/squashfs-probe"; then
        exit 77
    fi
    umount "$root/squashfs-probe"
    rmdir "$root/squashfs-probe"

    run_zxmod() {
        ZXMOD_LIBRARY="$library" \
        ZXMOD_RUN_ROOT="$root/run" \
        ZXMOD_USR_TARGET="$root/base/usr" \
        ZXMOD_OPT_TARGET="$root/base/opt" \
            "$command_path" "$@"
    }

    run_zxmod load "$root/sample.zxm"
    "$root/base/usr/bin/sample-command" | grep -Fxq sample-command
    awk -F "\t" '\''$1 == "sample" { found=1 } END { exit !found }'\'' \
        "$root/run/active"

    run_zxmod load "$root/companion.zxm"
    test "$(cat "$root/base/opt/companion/value")" = "companion payload"
    awk -F "\t" '\''$1 == "companion" { found=1 } END { exit !found }'\'' \
        "$root/run/active"

    run_zxmod load "$root/conflict.zxm"
    test "$(cat "$root/base/usr/base-file")" = conflict
    run_zxmod unload conflict
    test "$(cat "$root/base/usr/base-file")" = "base file"

    run_zxmod unload companion
    test ! -e "$root/base/opt/companion/value"
    test -x "$root/base/usr/bin/sample-command"
    run_zxmod unload sample
    test ! -e "$root/base/usr/bin/sample-command"
    test ! -s "$root/run/active"
' bash "$work" "$command_path" "$library" 2>&1)
runtime_status=$?
set -e

if [[ $runtime_status -eq 77 ]]; then
    printf 'zxmod runtime test skipped: unprivileged SquashFS mounting is unavailable\n' >&2
    exit 0
fi
if [[ $runtime_status -ne 0 ]]; then
    printf '%s\n' "$runtime_output" >&2
    exit "$runtime_status"
fi

printf 'zxmod direct mount/load/unload, completion, and XDG integration passed\n'
