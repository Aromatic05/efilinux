#!/usr/bin/sh

set -eu

/usr/bin/modprobe iwlwifi
/usr/bin/grep -Eq '^iwlwifi[[:space:]]' /proc/modules
/usr/bin/insmod /mnt/firmware/firmware-request-probe.ko
/usr/bin/dmesg |
    /usr/bin/grep -F \
        'EFILINUX_FIRMWARE_REQUEST_OK name=iwlwifi-ty-a0-gf-a0-89.ucode '
/usr/bin/printf 'EFILINUX_FIRMWARE_DRIVER_OK\n'
/usr/bin/poweroff -f
