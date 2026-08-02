#!/usr/bin/sh

ok=1
/usr/bin/bash -c 'set -o pipefail; values=(alpha beta); [[ ${values[1]} == beta ]]' || { echo FAIL:bash-runtime; ok=0; }
test "$(/usr/bin/readlink -f /usr/bin/sh)" = /usr/bin/busybox || { echo FAIL:gnu-readlink; ok=0; }
/usr/bin/find /usr -mindepth 1 -maxdepth 1 -print0 >/dev/null || { echo FAIL:gnu-find; ok=0; }
/usr/bin/stat -c %s /usr/bin/bash >/dev/null || { echo FAIL:gnu-stat; ok=0; }
echo EFILINUX_GNU_RUNTIME_OK
test "$(cat /run/efilinux/runlevel 2>/dev/null)" = 5 || { echo FAIL:runlevel; ok=0; }
test -S /tmp/.X11-unix/X0 || { echo FAIL:x11-socket; ok=0; }
desktop_session=$(loginctl list-sessions --no-legend --no-pager | awk '$2 == 1000 && $3 == "user" { print $1; exit }')
test -n "$desktop_session" || { echo FAIL:desktop-login-session; ok=0; }
if test -n "$desktop_session"; then
    test "$(loginctl show-session "$desktop_session" -p Seat --value)" = seat0 || { echo FAIL:desktop-seat; ok=0; }
    test "$(loginctl show-session "$desktop_session" -p TTY --value)" = tty7 || { echo FAIL:desktop-tty; ok=0; }
    test "$(loginctl show-session "$desktop_session" -p Active --value)" = yes || { echo FAIL:desktop-active; ok=0; }
    test "$(loginctl show-session "$desktop_session" -p Remote --value)" = no || { echo FAIL:desktop-remote; ok=0; }
fi
test -d /run/user/1000 || { echo FAIL:user-runtime-directory; ok=0; }
su -s /usr/bin/sh user -c 'test -r /run/user/1000 && test -w /run/user/1000 && test -x /run/user/1000' || { echo FAIL:user-runtime-access; ok=0; }
test -s /etc/xdg/menus/xfce-applications.menu || { echo FAIL:applications-menu; ok=0; }
pidof Xorg >/dev/null || { echo FAIL:Xorg; ok=0; }
desktop_pid=$(pidof xfce4-session | awk '{ print $1 }')
test -n "$desktop_pid" || { echo FAIL:xfce4-session; ok=0; }
if test -n "$desktop_pid"; then
    tr '\0' '\n' < "/proc/$desktop_pid/environ" | \
        grep -Fxq 'XDG_RUNTIME_DIR=/run/user/1000' || { echo FAIL:desktop-runtime-environment; ok=0; }
    pkcheck --action-id org.freedesktop.login1.power-off --process "$desktop_pid" || { echo FAIL:poweroff-authorization; ok=0; }
    pkcheck --action-id org.freedesktop.login1.reboot --process "$desktop_pid" || { echo FAIL:reboot-authorization; ok=0; }
    pkcheck --action-id org.freedesktop.NetworkManager.enable-disable-wifi --process "$desktop_pid" || { echo FAIL:wifi-toggle-authorization; ok=0; }
fi
pidof xfsettingsd >/dev/null || { echo FAIL:xfsettingsd; ok=0; }
pidof xfwm4 >/dev/null || { echo FAIL:xfwm4; ok=0; }
pidof xfce4-panel >/dev/null || { echo FAIL:xfce4-panel; ok=0; }
pidof xfdesktop >/dev/null || { echo FAIL:xfdesktop; ok=0; }
pidof xfce4-notifyd >/dev/null || { echo FAIL:xfce4-notifyd; ok=0; }
pidof xfce4-screensaver >/dev/null || { echo FAIL:xfce4-screensaver; ok=0; }
pidof xfce-polkit >/dev/null || { echo FAIL:xfce-polkit; ok=0; }
test -f /etc/pam.d/xfce4-screensaver || { echo FAIL:xfce4-screensaver-pam; ok=0; }
grep -Fqx 'auth include system-auth' /etc/pam.d/xfce4-screensaver || { echo FAIL:xfce4-screensaver-pam-policy; ok=0; }
xorg_log=/var/log/Xorg.0.log
test -f "$xorg_log" || { echo FAIL:xorg-log; ok=0; }
grep -Fq "Using input driver 'libinput' for 'AT Translated Set 2 keyboard'" "$xorg_log" || { echo FAIL:keyboard-libinput; ok=0; }
grep -Fq "Using input driver 'libinput' for 'QEMU QEMU USB Tablet'" "$xorg_log" || { echo FAIL:tablet-libinput; ok=0; }
! grep -Fq 'No input driver specified, ignoring this device.' "$xorg_log" || { echo FAIL:ignored-input-device; ok=0; }
! grep -Fq 'AIGLX error:' "$xorg_log" || { echo FAIL:aiglx; ok=0; }
! grep -Fq '/tmp/efilinux' "$xorg_log" || { echo FAIL:xorg-host-path; ok=0; }
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
su -s /usr/bin/sh user -c 'XDG_RUNTIME_DIR=/run/user/1000 elogind-inhibit --what=sleep --mode=delay --who=efilinux-test --why=screen-lock-test /usr/bin/true' || { echo FAIL:elogind-sleep-inhibit; ok=0; }
su -s /usr/bin/sh user -c 'DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority xwininfo -root >/dev/null' || { echo FAIL:xwininfo; ok=0; }
test -x /mnt/glx-probe/glx-llvmpipe-probe || { echo FAIL:glx-probe-binary; ok=0; }
su -s /usr/bin/sh user -c 'DISPLAY=:0 XAUTHORITY=/home/user/.Xauthority LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=2 /mnt/glx-probe/glx-llvmpipe-probe' || { echo FAIL:glx-llvmpipe-probe; ok=0; }
test "$ok" = 1 && echo EFILINUX_XFCE_OK
echo EFILINUX_XFCE_CHECK_DONE
poweroff -f
