# EFI Linux

A source-built, non-self-hosting Linux runtime. Host compilers and build tools
produce the target system; no compiler toolchain is installed into the target.

## Current milestone

- `001-runtime/linux-headers`: Linux UAPI headers from LFS
- `001-runtime/glibc`: target glibc from LFS
- `001-runtime/busybox`: dynamically linked minimal command environment
- `001-runtime/rootfs`: merged-/usr rootfs and initramfs device manifest
- `000-kernel/linux`: EFI-stub Linux kernel with embedded initramfs

The build output is:

```text
target/efi/EFI/BOOT/BOOTX64.EFI
```

BusyBox is the primary command implementation. Additional GNU utilities are
introduced only when a concrete runtime requirement cannot be met by BusyBox.
The target uses a merged `/usr` layout: `/bin` and `/sbin` both point to
`/usr/bin`, while glibc runtime libraries live in `/usr/lib`.
The initial x86-64 userspace baseline is `x86-64-v2`.

## Build

```sh
./build.sh
```

The directory numbers describe image layers rather than build dependency order.
The runtime is staged before the kernel because the final EFI executable embeds
the initramfs and boots without GRUB or systemd-boot.

## Host requirements

The first stage expects GCC, Make, Bison, Flex, Perl, Python, Cpio, gzip, bc,
OpenSSL development headers, and standard archive/download tools.

## Boot

Copy `target/efi` to a FAT EFI System Partition. Firmware using the removable
media path executes `EFI/BOOT/BOOTX64.EFI` directly. Serial output is configured
for 115200 baud.

## QEMU acceptance test

```sh
./test/boot-qemu.sh
```

The test boots through OVMF with the `Nehalem` CPU model, matching the
`x86-64-v2` userspace baseline. Logs and temporary firmware state remain under
`build/logs` and `build/test`; generated artifacts are never placed in the
repository root.
