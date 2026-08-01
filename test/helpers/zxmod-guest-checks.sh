#!/usr/bin/sh

set -eu

fail() {
    printf 'EFILINUX_ZXMOD_FAIL:%s\n' "$1"
    poweroff -f
    exit 1
}

module_loop_is_present() {
    /usr/bin/losetup --associated /mnt/sample.zxm 2>/dev/null |
        /usr/bin/grep -q .
}

wait_for_module_loop_release() {
    zxmod_wait=0
    while module_loop_is_present; do
        [ "$zxmod_wait" -lt 10 ] || fail module-loop-leaked
        sleep 1
        zxmod_wait=$((zxmod_wait + 1))
    done
}

module_mount_count() {
    /usr/bin/awk '
        $5 == "/usr" || $5 == "/opt" || index($5, "/run/zxmod/") == 1 {
            count++
        }
        END { print count + 0 }
    ' /proc/self/mountinfo
}

assert_runtime_is_clean() {
    wait_for_module_loop_release
    test -d /run/zxmod/retired || fail retired-root-missing
    test -z "$(/usr/bin/find /run/zxmod/retired -mindepth 1 -print -quit)" ||
        fail retired-generation-leaked
    test "$(/usr/bin/find /run/zxmod/generations \
        -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l)" = 1 ||
        fail generation-directory-leaked
}

test "$(id -u)" = 0 || fail not-root

if ! zxmod load /mnt/sample.zxm; then
    /usr/bin/findmnt -R /run/zxmod 2>/dev/null || true
    /usr/bin/losetup --all 2>/dev/null || true
    fail module-load
fi
test -x /usr/bin/zxmod-module-command || fail module-command-missing
test "$(/usr/bin/zxmod-module-command)" = zxmod-module-command ||
    fail module-command-output
/usr/bin/awk -F '\t' '$1 == "sample" { found=1 } END { exit !found }'     /run/zxmod/active || fail module-active-record
touch /usr/share/zxmod-test/must-not-write 2>/dev/null && fail usr-view-writable
exec 3</usr/share/zxmod-test/held.txt || fail held-fd-open
if zxmod load /mnt/conflict.zxm; then
    fail conflicting-module-loaded
fi
zxmod unload sample || fail module-unload
test ! -e /usr/bin/zxmod-module-command || fail module-path-remains-after-unload
IFS= read -r held_payload <&3 || fail held-fd-read
test "$held_payload" = 'held module payload' || fail held-fd-content
exec 3<&-
assert_runtime_is_clean
unloaded_mount_count=$(module_mount_count)

for unsupported in inspect list enable disable startup; do
    if zxmod "$unsupported" >/dev/null 2>&1; then
        fail "unsupported-command:$unsupported"
    fi
done

printf 'EFILINUX_ZXMOD_MOUNT_COUNT=%s\n' "$unloaded_mount_count"
printf 'EFILINUX_ZXMOD_OK\n'
poweroff -f
