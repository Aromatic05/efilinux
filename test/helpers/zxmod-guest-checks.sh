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
test ! -e /run/zxmod/startup.failed || fail startup-failed-without-config
printf 'persist_root=/mnt\n' > /etc/zxmod.conf
zxmod enable /mnt/sample.zxm || fail module-enable
test -f /mnt/zxmod/enabled/sample || fail module-enable-record

if ! zxmod load /mnt/sample.zxm; then
    /usr/bin/findmnt -R /run/zxmod 2>/dev/null || true
    /usr/bin/losetup --all 2>/dev/null || true
    fail module-load
fi
test -x /usr/bin/zxmod-module-command || fail module-command-missing
test "$(/usr/bin/zxmod-module-command)" = zxmod-module-command ||
    fail module-command-output
zxmod list | /usr/bin/grep -Eq '^sample[[:space:]]' || fail module-list-after-load
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
first_unloaded_mount_count=$(module_mount_count)

zxmod startup || fail module-startup
test -x /usr/bin/zxmod-module-command || fail startup-command-missing
zxmod disable sample || fail module-disable
zxmod unload sample || fail startup-module-unload
test ! -e /mnt/zxmod/enabled/sample || fail module-disable-record
if zxmod list | /usr/bin/grep -Eq '^sample[[:space:]]'; then
    fail module-list-remains-after-unload
fi
assert_runtime_is_clean
second_unloaded_mount_count=$(module_mount_count)
test "$second_unloaded_mount_count" = "$first_unloaded_mount_count" ||
    fail mount-count-grew

printf 'EFILINUX_ZXMOD_MOUNT_COUNT=%s\n' "$second_unloaded_mount_count"
printf 'EFILINUX_ZXMOD_OK\n'
poweroff -f
