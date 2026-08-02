# EFI Linux

EFI Linux is a source-built, non-self-hosting x86-64 Linux system. The host
compiler and build tools produce the target artifacts; no compiler toolchain is
installed into the target system and no toolchain bootstrap is performed.

## Current milestone

All package layers use directly executable Bash recipes.
Each package provides a complete devel tree plus a generated, declarative
installation subset. Profiles compose packages into the target rootfs without
running package scripts or allowing undeclared file replacement.

The current build covers:

```text
000-kernel
├── linux                 curated common-PC kernel and modules
├── linux-firmware        module-derived device firmware selection
├── sof-firmware          Intel SOF firmware and topology data
└── wireless-regdb        wireless regulatory database

001-runtime
├── linux-headers, glibc, zlib, xz, zstd
├── attr, acl, libcap, libxcrypt, lzo
├── busybox               ash and rescue applets
├── kmod                  formal module management
├── util-linux            block, mount, partition, swap, and hardware tools
├── e2fsprogs, btrfs-progs, xfsprogs
├── dosfstools, exfatprogs, NTFS maintenance tools
├── kbd, iana-etc, tzdata
└── base-files, runtime-init, runtime-config

002-system
├── sysvinit, sysklogd, udev, dbus, cronie
├── linux-pam, shadow, elogind, polkit, upower
├── iproute2, iputils, dhcpcd, openssh, iwd, networkmanager
├── pulseaudio, pipewire, wireplumber
├── device-mapper, cryptsetup, mdadm, libblockdev
├── udisks, gvfs
└── efilinux-system-config

003-graphical
├── xorg                 X11 protocols, client libraries, and utilities
├── xorg-server          Xorg server and input/video drivers
├── mesa                 no-LLVM Gallium graphics stack
├── libinput, libxkbcommon, xkeyboard-config
├── freetype, harfbuzz, fontconfig, cairo, pango
├── gdk-pixbuf, librsvg, gtk3, vte
├── independent GNOME/X11 support libraries
├── noto-sans-cjk-sc
├── qogir-icon-theme
└── qogir-desktop-theme

004-desktop
├── xfce                 integrated XFCE software stack
├── libnma
├── network-manager-applet
└── efilinux-xfce-config

005-utils
├── zxmod and squashfs-tools
└── selectable command-line maintenance utilities

005-applications
└── graphical desktop applications
```

BusyBox `ash` provides `/bin/sh` and rescue implementations of basic commands.
Formal module, mount, block-device, partition, console, and filesystem tools
own their paths directly; conflicting BusyBox applets are removed from the
BusyBox installation subset. Bash, GNU coreutils, and other broad utility
suites are not installed.
Headers, static libraries, pkg-config files, and documentation remain in the
package devel trees and are not copied into the target rootfs.

The target userspace baseline is `x86-64-v2`. SysVinit is the final PID 1;
BusyBox remains the rescue shell and compact implementation of basic commands.
The composer preserves fakeroot ownership, modes, device nodes, and declared
ACL/capability replay metadata without requiring the host build to run as root.

The maintenance environment can create, inspect, and repair ext4, Btrfs, XFS,
FAT, exFAT, and NTFS filesystems. NTFS mounting uses the in-kernel `ntfs3`
driver; NTFS-3G contributes maintenance programs only, not the FUSE mount
driver.

Runlevel 3 starts Udev, local networking, Sysklogd, the D-Bus system bus,
elogind, polkit, Cronie, IWD, NetworkManager, UDisks, and OpenSSH. Host keys and
the D-Bus machine ID are generated at boot and are never shared between built
images.

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

The numbered directories are organizational layers. Package recipes resolve
their target dependencies by package name, while profile files under
`profiles/` select the exact runtime closure for console, graphical, and XFCE
images. The selected rootfs is composed first; kernel modules and firmware are
then transactionally added, and the EFI-stub kernel is relinked with that
complete rootfs.

Generated files are restricted to:

```text
downloads/
build/
packages/
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
- explicit replacement of BusyBox links by Kmod, Util-linux, Kbd, and
  filesystem-specific tools;
- complete ELF shared-library closure across programs, PAM modules, Udev
  helpers, plugins, and libexec files, with no target headers, static libraries,
  or development metadata in the rootfs;
- real create-and-read-only-check round trips for ext4, Btrfs, XFS, FAT, exFAT,
  and NTFS sparse images;
- exact kernel policy and curated compressed module set;
- modules, curated firmware, and regulatory data under `target/rootfs`;
- `target/rootfs` as the sole `CONFIG_INITRAMFS_SOURCE` directory;
- exact initramfs ownership mapping from the build user to root;
- real OVMF boot with a `Nehalem` CPU model into SysVinit runlevel 3;
- live Udev, Sysklogd, D-Bus, Cronie, dhcpcd, and OpenSSH processes;
- DHCP configuration and an OpenSSH listener inside the guest;
- target Kmod loading a Zstd-compressed module from the embedded rootfs.

The default single EFI image composes `utils-maintenance.packages` and
`applications-desktop.packages` after the XFCE base.  The maintenance profile
includes `utils-zxmod.packages`, so local Zstd SquashFS module support, command-
line recovery tools, lightweight desktop applications, and GParted are present
in the same rootfs.

## Live modules and persistence

At early boot, EFI Linux reads block-device metadata from Udev and considers
only filesystems whose volume label is exactly `EFILINUX`.  Unmarked devices
are not mounted or probed by the live-media scanner.  A labeled candidate is
accepted only when it contains a regular, non-symbolic-link
`efilinux/efilinux.conf`; paths are relative to that directory and may not
contain whitespace, traverse outside it, or resolve through escaping symbolic
links.

```text
module modules/001-recovery.zxm
persistence persistence.img
```

`module` directives from all discovered filesystems are processed in stable
device order and duplicate relative module paths are loaded once.  Only the
first valid `persistence` directive is used.  Its image must contain ext4 and
is used as the upper/work storage for a whole-root OverlayFS before SysVinit
starts.  `/run`, `/dev`, `/proc`, and `/sys` remain transient mounts.

Set the filesystem label before enabling automatic discovery.  For example:

```sh
e2label /dev/sdX1 EFILINUX
fatlabel /dev/sdX1 EFILINUX
```

The label is the partition-independent discovery marker and therefore works
with GPT, MBR, and filesystems placed directly on a whole block device.

Create a container and starter configuration on a writable mounted filesystem
with:

```sh
efilinux-persistence-create /path/to/mounted/media 1024
```

This creates `/path/to/mounted/media/efilinux/persistence.img`; it refuses to
overwrite an existing container.

The desktop image includes **EFI Linux Live Manager**, a single GTK3 control
panel for both features.  It can import and remove `.zxm` files, load or unload
modules in the current session, toggle their boot-time `module` directives,
create `persistence.img`, and enable or disable persistence for later boots.
Disabling persistence does not delete the container or alter the current
session.  The GUI delegates all mutations to `efilinux-livectl`; the same
validated operations are available from the command line.

The removable-media EFI path is:

```text
target/efi/EFI/BOOT/BOOTX64.EFI
```
