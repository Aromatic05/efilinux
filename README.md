# EFI Linux

EFI Linux is a source-built, non-self-hosting x86-64 Linux system. The host
compiler and build tools produce the target artifacts; no compiler toolchain is
installed into the target system and no toolchain bootstrap is performed.

## Current milestone

The current build covers the first two package groups:

```text
000-kernel
├── linux                 curated common-PC kernel and modules
├── linux-firmware        module-derived device firmware selection
├── sof-firmware          Intel SOF firmware and topology data
└── wireless-regdb        wireless regulatory database

001-runtime
├── linux-headers         Linux UAPI headers
├── glibc                 target C runtime
├── zlib
├── xz
├── zstd
├── busybox               ash and maintenance applets
└── rootfs                merged-/usr system assembly
```

BusyBox `ash` provides `/bin/sh` and most basic commands. Bash, GNU coreutils,
and other broad utility suites are not installed. Standalone programs are added
only when a concrete runtime need is not adequately covered by BusyBox.

The target userspace baseline is `x86-64-v2`.

## Single-rootfs model

There is one target filesystem:

```text
target/
├── efi/EFI/BOOT/BOOTX64.EFI
└── rootfs/
    ├── init
    ├── usr/bin/
    └── usr/lib/
        ├── modules/<version>/
        └── firmware/
```

`target/rootfs` is both the final system root and the source passed to
`CONFIG_INITRAMFS_SOURCE`. The EFI-stub kernel therefore embeds the complete
rootfs, including BusyBox, glibc, compression tools, kernel modules, device
firmware, and wireless regulatory data.

The rootfs uses a merged `/usr` layout:

```text
/bin   -> usr/bin
/sbin  -> usr/bin
/lib   -> usr/lib
/lib64 -> usr/lib
```

## Common-PC kernel policy

The kernel configuration starts from `tinyconfig` and merges the explicit
`000-kernel/linux/common-pc.config` policy. The build fails if the final Kconfig
state does not exactly satisfy that policy.

The current module set covers mainstream x86 PC hardware and virtual machines:

- AMD, Intel, Nouveau, VirtIO, VMware, and Hyper-V graphics;
- Intel, Realtek, Broadcom, Atheros, MediaTek, and Aquantia networking;
- Intel, Atheros, Broadcom, MediaTek, and Realtek wireless devices;
- Bluetooth, HDA, USB Audio, Intel SOF, AMD ACP, and UVC webcams;
- NVMe, AHCI, USB storage, UAS, MMC, common filesystems, and device mapper;
- VirtIO, VMware, and Hyper-V guest devices.

Specialized television receivers, radio, SDR, media test drivers, uncommon
server adapters, and embedded SoC-only devices are excluded.

Device firmware is selected from the pinned `linux-firmware` release using the
actual `MODULE_FIRMWARE` declarations of the built module tree, supplemented by
a small list for common firmware families that are not fully self-described.
An explicit exclusion policy removes duplicate Nouveau r535 images,
data-center-only AMD firmware, access-point Qualcomm firmware, and embedded
Broadcom/Cypress SDIO firmware. Nouveau retains the preferred r570 firmware.

CPU microcode is not included in the default image. Files placed in the
built-in rootfs are unavailable to the x86 early microcode loader, so including
the complete Intel and AMD collections would consume space without providing
early-boot updates. The default image relies on platform firmware until a real
early-microcode delivery mechanism is added.

## Build

```sh
./build.sh
```

The numbered directories describe package groups, not direct build order. The
base rootfs is assembled first, modules and firmware are installed into that
same rootfs, and the final EFI kernel is produced last.

Generated files are restricted to:

```text
downloads/
build/
target/
```

Logs, process state, test files, and OVMF variable images are never written into
the repository root.

## Host requirements

`preflight.sh` reports missing host commands and exits. It never installs or
builds host tools. Install any reported dependency on the host and rerun the
build.

## Acceptance tests

Run all current acceptance tests with:

```sh
./test/run.sh
```

The suite verifies:

- merged-/usr layout and required BusyBox applets;
- target-glibc execution and XZ/Zstd compression round trips;
- exact kernel policy and curated compressed module set;
- modules, curated firmware, and regulatory data under `target/rootfs`;
- `target/rootfs` as the sole `CONFIG_INITRAMFS_SOURCE` directory;
- real OVMF boot with a `Nehalem` CPU model through to the BusyBox `ash` prompt;
- target BusyBox loading a Zstd-compressed module from the embedded rootfs.

The removable-media EFI path is:

```text
target/efi/EFI/BOOT/BOOTX64.EFI
```
