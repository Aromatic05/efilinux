#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command qemu-system-x86_64 timeout
ensure_directories

qemu_cpu=${QEMU_CPU:-Nehalem}
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars_template=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
ovmf_vars="$EFILINUX_TEST/OVMF_VARS.graphical.fd"
boot_log="$EFILINUX_LOGS/qemu-graphical-boot.log"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"

[[ -f "$efi_binary" ]] || die "EFI binary is missing: $efi_binary"
[[ -f "$ovmf_code" ]] || die "OVMF code image is missing: $ovmf_code"
[[ -f "$ovmf_vars_template" ]] || \
    die "OVMF variables image is missing: $ovmf_vars_template"

cp "$ovmf_vars_template" "$ovmf_vars"

log "Booting graphical EFI Linux with VirtIO-GPU"
set +e
{
    sleep 100
    cat <<'GUEST_CHECKS'
ok=1
test "$(cat /run/efilinux/runlevel 2>/dev/null)" = 5 || { echo FAIL:runlevel; ok=0; }
test -S /tmp/.X11-unix/X0 || { echo FAIL:x11-socket; ok=0; }
test -s /run/efilinux/graphical.pid || { echo FAIL:graphical-pidfile; ok=0; }
test "$ok" = 0 || kill -0 "$(cat /run/efilinux/graphical.pid)" || { echo FAIL:graphical-wrapper; ok=0; }
test -s /etc/xdg/menus/xfce-applications.menu || { echo FAIL:applications-menu; ok=0; }
pidof Xorg >/dev/null || { echo FAIL:Xorg; ok=0; }
pidof xfce4-session >/dev/null || { echo FAIL:xfce4-session; ok=0; }
pidof xfsettingsd >/dev/null || { echo FAIL:xfsettingsd; ok=0; }
pidof xfwm4 >/dev/null || { echo FAIL:xfwm4; ok=0; }
pidof xfce4-panel >/dev/null || { echo FAIL:xfce4-panel; ok=0; }
pidof xfdesktop >/dev/null || { echo FAIL:xfdesktop; ok=0; }
pidof xfce4-notifyd >/dev/null || { echo FAIL:xfce4-notifyd; ok=0; }
xorg_log=/var/log/Xorg.0.log
test -f "$xorg_log" || { echo FAIL:xorg-log; ok=0; }
grep -Fq "Using input driver 'libinput' for 'AT Translated Set 2 keyboard'" "$xorg_log" || { echo FAIL:keyboard-libinput; ok=0; }
grep -Fq "Using input driver 'libinput' for 'QEMU QEMU USB Tablet'" "$xorg_log" || { echo FAIL:tablet-libinput; ok=0; }
! grep -Fq 'No input driver specified, ignoring this device.' "$xorg_log" || { echo FAIL:ignored-input-device; ok=0; }
! grep -Fq 'AIGLX error:' "$xorg_log" || { echo FAIL:aiglx; ok=0; }
! grep -Fq '/tmp/efilinux' "$xorg_log" || { echo FAIL:xorg-host-path; ok=0; }
notification_wrapper=
for cmdline in /proc/[0-9]*/cmdline; do
    if tr '\0' '\n' <"$cmdline" | grep -Fxq notification-plugin; then
        wrapper_path=${cmdline#/proc/}
        notification_wrapper=${wrapper_path%/cmdline}
        break
    fi
done
test -n "$notification_wrapper" || { echo FAIL:notification-wrapper-missing; ok=0; }
test -z "$notification_wrapper" || kill -0 "$notification_wrapper" || { echo FAIL:notification-wrapper-dead; ok=0; }
! grep -qi 'failed to load applications menu' /var/log/graphical.log || { echo FAIL:menu-load; ok=0; }
test -x /usr/bin/dbus-update-activation-environment || { echo FAIL:dbus-update-tool; ok=0; }
test -f /usr/share/defaults/at-spi2/accessibility.conf || { echo FAIL:atspi-config; ok=0; }
pidof at-spi-bus-launcher >/dev/null || { echo FAIL:atspi-launcher; ok=0; }
pidof at-spi2-registryd >/dev/null || { echo FAIL:atspi-registry; ok=0; }
pidof pipewire >/dev/null || { echo FAIL:pipewire; ok=0; }
pidof pipewire-pulse >/dev/null || { echo FAIL:pipewire-pulse; ok=0; }
pidof wireplumber >/dev/null || { echo FAIL:wireplumber; ok=0; }
test -S /run/user/1000/pipewire-0 || { echo FAIL:pipewire-socket; ok=0; }
test -S /run/user/1000/pulse/native || { echo FAIL:pulse-socket; ok=0; }
su -s /usr/bin/sh user -c 'XDG_RUNTIME_DIR=/run/user/1000 pactl info >/dev/null 2>&1' || { echo FAIL:pactl; ok=0; }
! grep -Fq 'Failed to start message bus: Failed to open "/usr/share/defaults/at-spi2/accessibility.conf"' /var/log/graphical.log || { echo FAIL:atspi-bus-log; ok=0; }
! grep -Fq 'dbus-update-activation-environment' /var/log/graphical.log || { echo FAIL:dbus-env-log; ok=0; }
! grep -Fq 'pa_context_connect() failed: Access denied' /var/log/graphical.log || { echo FAIL:pulse-access; ok=0; }
settings_pid=$(pidof xfsettingsd 2>/dev/null || true)
test -n "$settings_pid" || { echo FAIL:settings-pid; ok=0; }
bus=
test -z "$settings_pid" || bus=$(tr '\0' '\n' </proc/$settings_pid/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
test -n "$bus" || { echo FAIL:session-bus; ok=0; }
gtk_theme=
test -z "$bus" || gtk_theme=$(su -s /usr/bin/sh user -c "DBUS_SESSION_BUS_ADDRESS='$bus' xfconf-query -c xsettings -p /Net/ThemeName")
test "$gtk_theme" = Qogir || { echo FAIL:gtk-theme; ok=0; }
icon_theme=
test -z "$bus" || icon_theme=$(su -s /usr/bin/sh user -c "DBUS_SESSION_BUS_ADDRESS='$bus' xfconf-query -c xsettings -p /Net/IconThemeName")
test "$icon_theme" = Qogir || { echo FAIL:icon-theme; ok=0; }
cursor_theme=
test -z "$bus" || cursor_theme=$(su -s /usr/bin/sh user -c "DBUS_SESSION_BUS_ADDRESS='$bus' xfconf-query -c xsettings -p /Gtk/CursorThemeName")
test "$cursor_theme" = Qogir || { echo FAIL:cursor-theme; ok=0; }
xfwm_theme=
test -z "$bus" || xfwm_theme=$(su -s /usr/bin/sh user -c "DBUS_SESSION_BUS_ADDRESS='$bus' xfconf-query -c xfwm4 -p /general/theme")
test "$xfwm_theme" = Qogir || { echo FAIL:xfwm-theme; ok=0; }
su -s /usr/bin/sh user -c 'DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority xwininfo -root >/dev/null' || { echo FAIL:xwininfo; ok=0; }
test "$ok" = 1 && echo EFILINUX_XFCE_OK
echo EFILINUX_XFCE_CHECK_DONE
poweroff -f
GUEST_CHECKS
} | timeout --signal=TERM 180s qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -cpu "$qemu_cpu" \
    -m 3G \
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
    -drive if=pflash,format=raw,file="$ovmf_vars" \
    -drive format=raw,file=fat:rw:"$EFILINUX_EFI_DIR" \
    -vga none \
    -device virtio-vga \
    -device qemu-xhci,id=xhci \
    -device usb-tablet,bus=xhci.0 \
    -display none \
    -serial stdio \
    -monitor none \
    -no-reboot \
    > "$boot_log" 2>&1
qemu_status=$?
set -e

if [[ "$qemu_status" -ne 0 && "$qemu_status" -ne 124 ]]; then
    tail -n 100 "$boot_log" >&2
    die "graphical QEMU exited unexpectedly with status $qemu_status"
fi

if grep -q 'Kernel panic' "$boot_log"; then
    tail -n 100 "$boot_log" >&2
    die "kernel panic detected during graphical boot"
fi

normalized_log="$EFILINUX_TEST/qemu-graphical-boot.normalized.log"
tr -d '\r' < "$boot_log" > "$normalized_log"
if grep -q '^FAIL:' "$normalized_log"; then
    tail -n 200 "$boot_log" >&2
    die "graphical guest checks reported a failure"
fi
if ! grep -Fxq 'EFILINUX_XFCE_OK' "$normalized_log"; then
    tail -n 200 "$boot_log" >&2
    die "Xorg and the XFCE desktop did not become operational on VirtIO-GPU"
fi

log "OVMF boot reached a live XFCE 4.18 session on Xorg and VirtIO-GPU"
printf 'Boot log: %s\n' "$boot_log"
