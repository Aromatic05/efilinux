#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command awk chroot cut gcc grep install mktemp openssl unshare

pam_service="$EFILINUX_ROOTFS/etc/pam.d/xfce4-screensaver"
[[ -f "$pam_service" ]] || die "XFCE screensaver PAM service is missing"
grep -Fqx 'auth include system-auth' "$pam_service" || \
    die "XFCE screensaver PAM service does not use system-auth"

user_hash=$(awk -F: '$1 == "user" { print $2 }' "$EFILINUX_ROOTFS/etc/shadow")
[[ -n "$user_hash" ]] || die "desktop user shadow entry is missing"
salt=$(printf '%s' "$user_hash" | cut -d'$' -f3)
[[ $(openssl passwd -6 -salt "$salt" user) == "$user_hash" ]] || \
    die "desktop user password is not the documented default"

work=$(mktemp -d)
helper="$EFILINUX_ROOTFS/tmp/.efilinux-pam-auth-test"
cleanup() {
    rm -f -- "$helper"
    rm -rf -- "$work"
}
trap cleanup EXIT

cat > "$work/pam-auth-test.c" <<'EOF'
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int converse(int count, const struct pam_message **messages,
                    struct pam_response **responses_out, void *data) {
    const char *password = data;
    struct pam_response *responses = calloc((size_t)count, sizeof(*responses));
    if (responses == NULL) return PAM_BUF_ERR;
    for (int i = 0; i < count; ++i) {
        if (messages[i]->msg_style == PAM_PROMPT_ECHO_OFF ||
            messages[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            responses[i].resp = strdup(password);
            if (responses[i].resp == NULL) return PAM_BUF_ERR;
        }
    }
    *responses_out = responses;
    return PAM_SUCCESS;
}

int main(int argc, char **argv) {
    pam_handle_t *handle = NULL;
    if (argc != 3) return 64;
    struct pam_conv conversation = { converse, argv[2] };
    int result = pam_start("xfce4-screensaver", argv[1], &conversation, &handle);
    if (result == PAM_SUCCESS) result = pam_authenticate(handle, 0);
    if (handle != NULL) pam_end(handle, result);
    return result == PAM_SUCCESS ? 0 : 1;
}
EOF

gcc --sysroot="$EFILINUX_SYSROOT" -O2 -Wall -Wextra -Werror \
    "$work/pam-auth-test.c" \
    -L"$EFILINUX_SYSROOT/usr/lib" \
    -Wl,-rpath-link,"$EFILINUX_SYSROOT/usr/lib" \
    -lpam -o "$work/pam-auth-test"
install -m0755 "$work/pam-auth-test" "$helper"

unshare --user --map-root-user --mount --pid --fork \
    chroot "$EFILINUX_ROOTFS" /tmp/.efilinux-pam-auth-test user user
if unshare --user --map-root-user --mount --pid --fork \
    chroot "$EFILINUX_ROOTFS" /tmp/.efilinux-pam-auth-test user wrong-password; then
    die "XFCE screensaver PAM service accepted an invalid password"
fi

log "XFCE screensaver PAM service accepts the desktop password and rejects an invalid password"
