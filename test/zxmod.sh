#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
builder="$ROOT/005-utils/zxmod/files/usr/bin/zxmod-build"
command="$ROOT/005-utils/zxmod/files/usr/bin/zxmod"
library="$ROOT/005-utils/zxmod/files/usr/lib/zxmod/common.sh"
init_script="$ROOT/005-utils/zxmod/files/etc/rc.d/init.d/zxmod"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

[[ -x "$init_script" ]] || {
    printf 'zxmod SysVinit integration is missing\n' >&2
    exit 1
}
if ! grep -Fq '/usr/bin/zxmod startup' "$init_script"; then
    printf 'zxmod SysVinit integration does not restore enabled modules\n' >&2
    exit 1
fi

require_command() {
    command -v "$1" >/dev/null || {
        printf 'zxmod test requires %s\n' "$1" >&2
        exit 1
    }
}

for command_name in mksquashfs unsquashfs unshare mount umount; do
    require_command "$command_name"
done

mkdir -p "$work/module/usr/bin" "$work/conflict/usr"
printf 'module command\n' > "$work/module/usr/bin/module-command"
printf 'conflict\n' > "$work/conflict/usr/base-file"
chmod 0755 "$work/module/usr/bin/module-command"

"$builder" --id sample --version 1.0 --arch "$(uname -m)" \
    --description 'runtime test module' "$work/module" "$work/sample.zxm"
"$builder" --id conflict --version 1.0 --arch "$(uname -m)" \
    "$work/conflict" "$work/conflict.zxm"

inspection=$(ZXMOD_LIBRARY="$library" "$command" inspect "$work/sample.zxm")
grep -Fxq 'id=sample' <<<"$inspection"
grep -Fxq "arch=$(uname -m)" <<<"$inspection"
grep -Fxq 'version=1.0' <<<"$inspection"
unsquashfs -s "$work/sample.zxm" | grep -Eq '^Compression[[:space:]]+zstd$'
unsquashfs -cat "$work/sample.zxm" metadata/manifest | grep -Fxq 'format=1'

mkdir -p "$work/valid-hidden/usr/share"
printf 'hidden payload\n' > "$work/valid-hidden/usr/share/.zxmod-hidden"
"$builder" --id valid-hidden --version 1.0 --arch "$(uname -m)" \
    "$work/valid-hidden" "$work/valid-hidden.zxm"
unsquashfs -cat "$work/valid-hidden.zxm" root/usr/share/.zxmod-hidden | \
    grep -Fxq 'hidden payload'

assert_builder_rejects() {
    local name=$1 root=$2
    local output="$work/$name.zxm"
    if "$builder" --id "$name" --version 1.0 --arch "$(uname -m)" \
        "$root" "$output" >/dev/null 2>&1; then
        printf 'zxmod builder accepted invalid tree: %s\n' "$name" >&2
        exit 1
    fi
    [[ ! -e $output ]] || {
        printf 'zxmod builder left output for invalid tree: %s\n' "$name" >&2
        exit 1
    }
}

mkdir -p "$work/hidden-top/usr"
printf 'unexpected\n' > "$work/hidden-top/.unexpected"
assert_builder_rejects hidden-top "$work/hidden-top"

mkdir -p "$work/special-file/usr"
mkfifo "$work/special-file/usr/fifo"
assert_builder_rejects special-file "$work/special-file"

mkdir -p "$work/newline-path/usr/bin"
printf 'bad\n' > "$work/newline-path/usr/bin/bad"$'\n'"name"
assert_builder_rejects newline-path "$work/newline-path"

if ! unshare --user --map-root-user --mount --fork true 2>/dev/null; then
    printf 'zxmod runtime test skipped: user and mount namespaces are unavailable\n' >&2
    exit 0
fi

mkdir -p \
    "$work/move/base" \
    "$work/move/new" \
    "$work/move/live" \
    "$work/move/stage" \
    "$work/move/retired"
printf 'base view\n' > "$work/move/base/value"
printf 'new view\n' > "$work/move/new/value"
unshare --user --map-root-user --mount --fork bash -ceu '
    library=$1
    root=$2
    mount --make-rprivate /
    mount --bind "$root/base" "$root/live"
    mount --bind "$root/new" "$root/stage"
    . "$library"
    zxmod_move_generation_target "$root/stage" "$root/live" "$root/retired"
    test "$(cat "$root/live/value")" = "new view"
    test "$(cat "$root/retired/value")" = "base view"
    zxmod_restore_generation_target "$root/stage" "$root/live" "$root/retired"
    test "$(cat "$root/live/value")" = "base view"
    test "$(cat "$root/stage/value")" = "new view"
' bash "$library" "$work/move"

set +e
runtime_output=$(unshare --user --map-root-user --mount --fork bash -ceu '
    root=$1
    command=$2
    library=$3
    mkdir -p "$root/base/usr" "$root/base/opt" "$root/run"
    printf "base file\n" > "$root/base/usr/base-file"
    mkdir "$root/squashfs-probe"
    if ! mount -t squashfs -o ro "$root/sample.zxm" "$root/squashfs-probe"; then
        printf "ZXMOD_RUNTIME_SKIP: unprivileged SquashFS mounting is unavailable\n" >&2
        exit 77
    fi
    umount "$root/squashfs-probe"
    rmdir "$root/squashfs-probe"
    ZXMOD_LIBRARY="$library" ZXMOD_RUN_ROOT="$root/run" ZXMOD_USR_TARGET="$root/base/usr" ZXMOD_OPT_TARGET="$root/base/opt" \
        "$command" load "$root/sample.zxm"
    test "$(cat "$root/base/usr/bin/module-command")" = "module command"
    if ZXMOD_LIBRARY="$library" ZXMOD_RUN_ROOT="$root/run" ZXMOD_USR_TARGET="$root/base/usr" ZXMOD_OPT_TARGET="$root/base/opt" \
        "$command" load "$root/conflict.zxm"; then
        printf "conflicting module loaded\n" >&2
        exit 1
    fi
    ZXMOD_LIBRARY="$library" ZXMOD_RUN_ROOT="$root/run" ZXMOD_USR_TARGET="$root/base/usr" ZXMOD_OPT_TARGET="$root/base/opt" \
        "$command" unload sample
    test ! -e "$root/base/usr/bin/module-command"
' bash "$work" "$command" "$library" 2>&1)
runtime_status=$?
set -e

if [[ $runtime_status -eq 77 ]]; then
    printf '%s\n' "$runtime_output" >&2
    printf 'zxmod runtime test skipped: unprivileged SquashFS mounting is unavailable\n' >&2
    exit 0
fi
if [[ $runtime_status -ne 0 ]]; then
    printf '%s\n' "$runtime_output" >&2
    exit "$runtime_status"
fi
