#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
source "$ROOT/config.sh"
source "$ROOT/lib/common.sh"

require_command cmp find grep modinfo readlink stat wc
ensure_directories

rootfs="$EFILINUX_ROOTFS"
linux_metadata=$("$ROOT/000-kernel/linux/build.sh" --print-metadata)
read -r linux_version linux_recipe_key < <(
    python3 -c \
        'import json,sys; data=json.load(sys.stdin); print(data["pkgver"], data["recipe_key"])' \
        <<<"$linux_metadata"
)
kernel_state="$EFILINUX_BUILD/kernel-state/$linux_recipe_key"
kernel_config="$kernel_state/build/.config"
module_root="$rootfs/usr/lib/modules/$linux_version"
initramfs_manifest="$EFILINUX_INITRAMFS_MANIFEST"
firmware_root="$rootfs/usr/lib/firmware"
efi_binary="$EFILINUX_EFI_DIR/EFI/BOOT/BOOTX64.EFI"

[[ -f "$kernel_config" ]] || die "kernel configuration is missing"
[[ -d "$rootfs" ]] || die "target rootfs is missing"
[[ -d "$module_root" ]] || die "kernel modules are missing from target rootfs"
[[ -s "$module_root/modules.dep" ]] || die "kernel module dependency map is missing"
[[ -d "$firmware_root" ]] || die "device firmware is missing from target rootfs"
[[ -f "$firmware_root/regulatory.db" ]] || die "wireless regulatory database is missing"
[[ -f "$firmware_root/regulatory.db.p7s" ]] || die "wireless regulatory signature is missing"
[[ ! -e "$firmware_root/intel-ucode" ]] || die "unused Intel CPU microcode remains in target rootfs"
[[ ! -e "$firmware_root/amd-ucode" ]] || die "unused AMD CPU microcode remains in target rootfs"
[[ -f "$efi_binary" ]] || die "EFI executable is missing"

[[ -L "$rootfs/lib" ]] || die "rootfs /lib is not a symbolic link"
[[ $(readlink "$rootfs/lib") == usr/lib ]] || die "rootfs /lib does not point to usr/lib"

assert_no_find_match() {
    local message=$1
    shift
    local match

    match=$(find "$@" -print -quit) || die "find failed while checking: $message"
    [[ -z "$match" ]] || die "$message: ${match#"$rootfs/"}"
}

assert_no_find_match \
    "rootfs contains a path that cannot be embedded by gen_initramfs.sh" \
    "$rootfs" -name '*[[:space:]]*'

[[ -s "$initramfs_manifest" ]] || die "generated initramfs manifest is missing"
grep -Fxq 'CONFIG_INITRAMFS_SOURCE="initramfs.files"' "$kernel_config" || \
    die "kernel link state does not use the stable initramfs manifest path"
cmp -s "$initramfs_manifest" "$kernel_state/build/initramfs.files" || \
    die "generated manifest was not staged into the kernel link state"
grep -qx 'CONFIG_INITRAMFS_ROOT_UID=0' "$kernel_config" || \
    die "initramfs UID remapping is still enabled"
grep -qx 'CONFIG_INITRAMFS_ROOT_GID=0' "$kernel_config" || \
    die "initramfs GID remapping is still enabled"

require_manifest_entry() {
    local pattern=$1
    local message=$2
    grep -Eq "$pattern" "$initramfs_manifest" || die "$message"
}

require_manifest_entry '^file /etc/passwd [^ ]+ 0644 0 0$' \
    "initramfs /etc/passwd metadata is incorrect"
require_manifest_entry '^file /etc/group [^ ]+ 0644 0 0$' \
    "initramfs /etc/group metadata is incorrect"
require_manifest_entry '^file /etc/hosts [^ ]+ 0644 0 0$' \
    "initramfs /etc/hosts metadata is incorrect"
require_manifest_entry '^file /etc/nsswitch\.conf [^ ]+ 0644 0 0$' \
    "initramfs /etc/nsswitch.conf metadata is incorrect"
require_manifest_entry '^file /etc/shadow [^ ]+ 0600 0 0$' \
    "initramfs /etc/shadow metadata is incorrect"
require_manifest_entry '^dir /home/user 0750 1000 1000$' \
    "initramfs user home metadata is incorrect"
require_manifest_entry '^nod /dev/console 0600 0 0 c 5 1$' \
    "initramfs console device is missing"
require_manifest_entry '^nod /dev/null 0666 0 0 c 1 3$' \
    "initramfs null device is missing"

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
    CONFIG_CPU_MITIGATIONS \
    CONFIG_EFI_STUB \
    CONFIG_EFIVAR_FS \
    CONFIG_DEVTMPFS \
    CONFIG_TMPFS \
    CONFIG_TMPFS_XATTR \
    CONFIG_TMPFS_POSIX_ACL \
    CONFIG_FS_POSIX_ACL \
    CONFIG_CGROUPS \
    CONFIG_NAMESPACES \
    CONFIG_FUTEX \
    CONFIG_FUTEX_PI \
    CONFIG_EPOLL \
    CONFIG_EVENTFD \
    CONFIG_SIGNALFD \
    CONFIG_TIMERFD \
    CONFIG_FILE_LOCKING \
    CONFIG_SECCOMP_FILTER \
    CONFIG_INOTIFY_USER \
    CONFIG_FANOTIFY \
    CONFIG_KEY_DH_OPERATIONS \
    CONFIG_CRYPTO_USER_API_HASH \
    CONFIG_CRYPTO_USER_API_SKCIPHER \
    CONFIG_CRYPTO_ECB \
    CONFIG_CRYPTO_CBC \
    CONFIG_CRYPTO_MD5 \
    CONFIG_CRYPTO_SHA1 \
    CONFIG_CRYPTO_SHA256 \
    CONFIG_CRYPTO_SHA512 \
    CONFIG_CRYPTO_AES \
    CONFIG_CRYPTO_DES \
    CONFIG_CRYPTO_CMAC \
    CONFIG_CRYPTO_HMAC \
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
    modinfo -b "$rootfs" -k "$linux_version" "$module" >/dev/null || \
        die "expected common-PC kernel module is unavailable: $module"
done

require_firmware_family() {
    local path=$1
    [[ -d "$firmware_root/$path" ]] || die "firmware family is missing: $path"
    find "$firmware_root/$path" \( -type f -o -type l \) -print -quit |
        grep -q . || die "firmware family is empty: $path"
}

for family in \
    amdgpu i915 xe nvidia \
    ath10k ath11k ath12k brcm mediatek \
    rtl_nic rtl_bt rtw88 rtw89 \
    intel/iwlwifi intel/sof intel/sof-ipc4 intel/sof-ipc4-tplg; do
    require_firmware_family "$family"
done

require_firmware_file() {
    local path=$1
    [[ -e "$firmware_root/$path" ]] || die "required firmware is missing: $path"
}

for firmware in \
    nvidia/tu102/gsp/gsp-570.144.bin.zst \
    nvidia/ga102/gsp/gsp-570.144.bin.zst \
    ath10k/QCA6174/hw3.0/firmware-6.bin.zst \
    ath10k/QCA9377/hw1.0/firmware-6.bin.zst \
    ath11k/QCA6390/hw2.0/amss.bin.zst \
    ath11k/WCN6855/hw2.0/amss.bin.zst \
    ath12k/WCN7850/hw2.0/amss.bin.zst \
    brcm/brcmfmac43602-pcie.bin.zst; do
    require_firmware_file "$firmware"
done

assert_no_find_match \
    "deprecated Nouveau r535 firmware remains in target rootfs" \
    "$firmware_root/nvidia" -name '*-535.113.01.bin.zst'
assert_no_find_match \
    "SOF community firmware remains in target rootfs" \
    "$firmware_root/intel" -type d -name community
assert_no_find_match \
    "SOF firmware debug dictionaries remain in target rootfs" \
    "$firmware_root/intel" -type f -name '*.ldc'

for excluded_path in \
    ath10k/QCA9887 \
    ath10k/QCA988X \
    ath10k/QCA99X0 \
    ath11k/QCN9074 \
    ath12k/QCN9274; do
    [[ ! -e "$firmware_root/$excluded_path" ]] || \
        die "non-default firmware family remains: $excluded_path"
done

assert_no_find_match \
    "embedded-only Broadcom SDIO firmware remains in target rootfs" \
    "$firmware_root/brcm" -path '*-sdio*'
if [[ -d "$firmware_root/cypress" ]]; then
    assert_no_find_match \
        "embedded-only Cypress SDIO firmware remains in target rootfs" \
        "$firmware_root/cypress" -path '*-sdio*'
fi
assert_no_find_match \
    "data-center-only AMD GPU firmware remains in target rootfs" \
    "$firmware_root/amdgpu" \( \
        -name 'aldebaran_*' -o \
        -name 'arcturus_*' -o \
        -name 'gc_9_4_3_*' -o \
        -name 'gc_9_4_4_*' \
    \)
assert_no_find_match \
    "broken symbolic links are present in the firmware tree" \
    -L "$firmware_root" -type l

log "Kernel and firmware policy passed with $module_count rootfs modules"
