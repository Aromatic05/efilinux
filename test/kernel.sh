#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command find grep modinfo readlink stat wc
ensure_directories

rootfs="$EFILINUX_ROOTFS"
kernel_config="$EFILINUX_KERNEL_BUILD/.config"
module_root="$rootfs/usr/lib/modules/$LINUX_VERSION"
firmware_root="$rootfs/usr/lib/firmware"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"

[[ -f "$kernel_config" ]] || die "kernel configuration is missing"
[[ -d "$rootfs" ]] || die "target rootfs is missing"
[[ -d "$module_root" ]] || die "kernel modules are missing from target rootfs"
[[ -s "$module_root/modules.dep" ]] || die "kernel module dependency map is missing"
[[ -d "$firmware_root" ]] || die "device firmware is missing from target rootfs"
[[ -f "$firmware_root/regulatory.db" ]] || die "wireless regulatory database is missing"
[[ -f "$firmware_root/regulatory.db.p7s" ]] || die "wireless regulatory signature is missing"
[[ -d "$firmware_root/intel-ucode" ]] || die "Intel microcode files are missing from target rootfs"
[[ -d "$firmware_root/amd-ucode" ]] || die "AMD microcode files are missing from target rootfs"
[[ -f "$efi_binary" ]] || die "EFI executable is missing"

[[ -L "$rootfs/lib" ]] || die "rootfs /lib is not a symbolic link"
[[ $(readlink "$rootfs/lib") == usr/lib ]] || die "rootfs /lib does not point to usr/lib"
if find "$rootfs" -name '*[[:space:]]*' -print -quit | grep -q .; then
    die "rootfs contains a path that cannot be embedded by gen_initramfs.sh"
fi

initramfs_source=$(grep '^CONFIG_INITRAMFS_SOURCE=' "$kernel_config")
[[ "$initramfs_source" == *"$rootfs"* ]] || \
    die "target rootfs is not the kernel initramfs source"
[[ "$initramfs_source" != *"target/layers"* ]] || \
    die "obsolete external kernel layer remains in initramfs configuration"
[[ "$initramfs_source" != *"initramfs-root"* ]] || \
    die "a second initramfs root is configured"

require_kernel_option() {
    local option=$1
    if ! grep -Eq "^${option}=(y|m)$" "$kernel_config"; then
        die "required kernel option is disabled: $option"
    fi
}

for option in \
    CONFIG_MODULES \
    CONFIG_MODULE_COMPRESS_ZSTD \
    CONFIG_MODULE_DECOMPRESS \
    CONFIG_FW_LOADER_COMPRESS_ZSTD \
    CONFIG_MICROCODE \
    CONFIG_CPU_MITIGATIONS \
    CONFIG_EFI_STUB \
    CONFIG_EFIVAR_FS \
    CONFIG_DEVTMPFS \
    CONFIG_TMPFS \
    CONFIG_CGROUPS \
    CONFIG_NAMESPACES \
    CONFIG_SECCOMP_FILTER \
    CONFIG_INOTIFY_USER \
    CONFIG_FANOTIFY \
    CONFIG_UNIX \
    CONFIG_INET \
    CONFIG_IPV6 \
    CONFIG_NF_TABLES \
    CONFIG_INPUT_EVDEV \
    CONFIG_HID_MULTITOUCH \
    CONFIG_USB_HID \
    CONFIG_DRM_SIMPLEDRM \
    CONFIG_DRM_I915 \
    CONFIG_DRM_XE \
    CONFIG_DRM_AMDGPU \
    CONFIG_DRM_NOUVEAU \
    CONFIG_NVME_CORE \
    CONFIG_SATA_AHCI \
    CONFIG_USB_STORAGE \
    CONFIG_EXT4_FS \
    CONFIG_VFAT_FS \
    CONFIG_EXFAT_FS \
    CONFIG_NTFS3_FS \
    CONFIG_BTRFS_FS \
    CONFIG_SQUASHFS \
    CONFIG_OVERLAY_FS \
    CONFIG_IWLWIFI \
    CONFIG_ATH10K_PCI \
    CONFIG_ATH11K_PCI \
    CONFIG_ATH12K \
    CONFIG_BRCMFMAC \
    CONFIG_MT7921E \
    CONFIG_RTL8XXXU \
    CONFIG_RTW89_8852BE \
    CONFIG_BT_HCIBTUSB \
    CONFIG_SND_HDA_INTEL \
    CONFIG_SND_USB_AUDIO \
    CONFIG_USB_VIDEO_CLASS \
    CONFIG_VIRTIO_PCI \
    CONFIG_HYPERV_VMBUS; do
    require_kernel_option "$option"
done

module_count=$(find "$module_root" -type f -name '*.ko*' | wc -l)
(( module_count >= 50 )) || die "too few common-PC modules were installed: $module_count"
(( module_count <= 800 )) || die "module set is no longer curated: $module_count modules"

if find "$module_root" -type f -name '*.ko' -print -quit | grep -q .; then
    die "uncompressed kernel modules are present"
fi

required_modules=(
    amdgpu i915 xe nouveau
    e1000e igb igc r8169 tg3 alx
    iwlwifi ath9k ath10k_pci ath11k_pci ath12k brcmfmac
    mt7921e rtl8xxxu rtw89_8852be
    btusb snd_hda_intel snd_usb_audio uvcvideo
    virtio_gpu vmwgfx hv_netvsc
)
for module in "${required_modules[@]}"; do
    modinfo -b "$rootfs" -k "$LINUX_VERSION" "$module" >/dev/null || \
        die "expected common-PC kernel module is unavailable: $module"
done

require_firmware_family() {
    local path=$1
    [[ -d "$firmware_root/$path" ]] || die "firmware family is missing: $path"
    find "$firmware_root/$path" \( -type f -o -type l \) -print -quit |
        grep -q . || die "firmware family is empty: $path"
}

for family in \
    amd-ucode intel-ucode \
    amdgpu i915 xe nvidia \
    ath10k ath11k ath12k brcm mediatek \
    rtl_nic rtl_bt rtw88 rtw89 \
    intel/iwlwifi intel/sof intel/sof-ipc4 intel/sof-ipc4-tplg; do
    require_firmware_family "$family"
done

if find -L "$firmware_root" -type l -print -quit | grep -q .; then
    die "broken symbolic links are present in the firmware tree"
fi

log "Kernel and firmware policy passed with $module_count rootfs modules"
