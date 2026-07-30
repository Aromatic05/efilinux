# Applications layer

`005-applications` is intentionally independent of the runtime, system,
graphical, and XFCE layers.  Its build aggregator produces packages only; its
maintenance image composes `applications-maintenance.packages`, while
`applications-desktop.packages` is a separately selectable XFCE profile.  A
console/rescue image therefore never gains GTK/XFCE applications merely by
adding the maintenance set.

All implemented recipes download a versioned upstream release over HTTPS and
verify its pinned SHA-256 digest.  Runtime packages retain only executable
programs, required shared libraries, and directly-used data files.

## 1. Required base maintenance tools

| Item | Purpose | Runtime dependencies | Placement | Status |
| --- | --- | --- | --- | --- |
| `file` / libmagic | Identify unknown files and damaged media signatures. | glibc, zlib | maintenance default | implemented |
| `less` | Safe pager for logs, manifests, and large diagnostic output. | glibc, ncurses, PCRE2 | maintenance default | implemented |
| `curl` | Authenticated HTTPS retrieval and upload during recovery. | glibc, OpenSSL, zlib | maintenance default | implemented; intentionally no HTTP/2, SSH, PSL, Brotli, or zstd stack |
| `rsync` | Incremental local/remote recovery copies over existing OpenSSH. | glibc, ACL, popt, zlib | maintenance default | implemented |
| `7zz` (7-Zip) | Create/test/extract 7z and ZIP archives without stagnant p7zip. | glibc | maintenance default | implemented |
| `strace` | Diagnose failed programs, missing paths, and syscalls. | glibc, Linux headers | maintenance default | implemented |
| `lsof` | Map open files/sockets to processes. | glibc, Linux headers | maintenance default | implemented |
| `dmidecode` | Report firmware, memory, and system inventory. | glibc, Linux headers | maintenance default | implemented |
| `pciutils` | Enumerate PCI devices with `lspci`/`setpci`. | glibc, zlib, Linux headers | maintenance default | implemented |
| `ddrescue` | Mapfile-based, retry-safe recovery from failing block media. | glibc | maintenance default | implemented |
| `unzip` | Extract legacy ZIP archives. | glibc | optional maintenance module | deferred: Info-ZIP has no maintained release; `7zz` covers ZIP extraction and creation. |
| `usbutils` + libusb | Enumerate USB topology and inspect devices. | libusb, udev, glibc | optional maintenance module | deferred: adds a new libusb runtime library; retain as a focused USB module. |
| `smartmontools` | Query ATA/SCSI/NVMe SMART data. | glibc, libcap, Linux headers | optional maintenance module | deferred: needs device access policy and a real-disk test fixture. |
| `nvme-cli` | NVMe health, format, and namespace maintenance. | libnvme, json-c, OpenSSL, keyutils | optional maintenance module | deferred: libnvme already exists, but CLI has a larger JSON/plugin surface and needs hardware-safe integration tests. |
| `parted` | Partition table and filesystem-aware edits. | readline, util-linux, device-mapper, libuuid | optional maintenance module | deferred: destructive-operation UX and loop-device integration testing are required. |
| `gptfdisk` | GPT-focused partition repair. | ncurses, glibc | optional maintenance module | deferred: needs loop-device corruption/recovery tests before inclusion. |
| `efivar` / `efibootmgr` | Inspect and repair UEFI NVRAM boot entries. | efivar, popt, Linux EFI headers | optional maintenance module | deferred: introduces efivar and must never be tested against host NVRAM. |
| `lvm2` | Activate and repair LVM volume groups. | device-mapper, readline, libaio, udev | optional maintenance module | deferred: requires libaio plus careful privileged loop-device tests. |

## 2. Recommended GUI maintenance tools

| Item | Purpose | Runtime dependencies | Placement | Status |
| --- | --- | --- | --- | --- |
| Xarchiver | Graphical archive inspection/extraction using the installed `7zz` backend. | GTK3, libarchive, 7-Zip | desktop profile | implemented |
| GParted | Graphical partition editor. | GTKmm, libparted, libuuid, polkit | optional GUI-maintenance module | deferred: adds C++ GTK bindings and depends on the deferred partition backend. |
| GSmartControl | Graphical SMART front end. | GTKmm, smartmontools | optional GUI-maintenance module | deferred: adds C++ GTK bindings and depends on deferred smartmontools. |
| pavucontrol | Per-stream PulseAudio/PipeWire volume control. | GTKmm, libcanberra, PulseAudio client API | optional desktop module | deferred: GTKmm/libcanberra are not in the controlled XFCE stack. |

## 3. Desktop usability applications

| Item | Purpose | Runtime dependencies | Placement | Status |
| --- | --- | --- | --- | --- |
| Xarchiver | Everyday archive browsing from XFCE. | GTK3, libarchive, 7-Zip | desktop profile | implemented |
| Mousepad | Native lightweight XFCE text editor. | GTK3, libxfce4ui, GtkSourceView 4 | desktop profile | deferred: GtkSourceView is absent; add it as a small, separately reviewed graphical dependency. |
| Ristretto | Lightweight XFCE image viewer. | GTK3, libxfce4ui, gdk-pixbuf, libexif | desktop profile | deferred: source audit is pending; it is preferred over a GNOME viewer because it does not require a new desktop platform. |
| Galculator | GTK calculator. | GTK3, glib | desktop profile | deferred: upstream's last stable release is old; do not add an unmaintained desktop calculator by default. |

## 4. Recovery/forensics modules outside the base

| Item | Purpose | Runtime dependencies | Placement | Status |
| --- | --- | --- | --- | --- |
| TestDisk / PhotoRec | Partition and file-carving recovery. | ncurses, glibc | recovery `.zxm` | deferred: recovery workloads are large and should not inflate the default image. |
| Sleuth Kit / Autopsy | Filesystem timeline and forensic analysis. | ICU/Java or Python ecosystem, sqlite | forensic `.zxm` | deferred: pulls a substantial analysis/runtime stack. |
| `ewf-tools` | E01 forensic image support. | libewf, zlib, OpenSSL | forensic `.zxm` | deferred: specialized library stack. |
| `dc3dd` / `dcfldd` | Forensic copying with hashes and split output. | OpenSSL or libgcrypt | recovery `.zxm` | deferred: `ddrescue` is the safer default for failing-media acquisition. |

## 5. Large optional `.zxm` desktop modules

| Item | Purpose | Runtime dependencies | Placement | Status |
| --- | --- | --- | --- | --- |
| Firefox ESR | Full browser for portals and documentation. | NSS, ICU, Rust build toolchain, media stack | browser `.zxm` | deferred: large runtime/build footprint. |
| Chromium | Alternative browser for compatibility. | ICU, NSS, multimedia/graphics stack | browser `.zxm` | deferred: substantially larger than the base desktop. |
| WPS Office | Office document editing. | Qt runtime, font collection, proprietary upstream payload | WPS `.zxm` | deferred: external binary distribution and large Qt payload. |
| LibreOffice | Fully open office suite. | Java/ICU/font and multimedia stack | office `.zxm` | deferred: large build and runtime footprint. |

The profile split is deliberate: install/composition code should select either
the maintenance profile or the desktop profile, rather than treating GUI
applications as implicit dependencies of recovery tools.
