# Utilities layer

`005-utils` contains local `.zxm` support, SquashFS tooling, and command-line
maintenance utilities. Its normal build extends the already composed rootfs
only with the small `utils-zxmod.packages` runtime profile. The broader
`utils-maintenance.packages` profile is separately selectable through
`005-utils/maintenance-image`; it is never implicitly composed into the XFCE
desktop image.

| Item | Purpose | Placement |
| --- | --- | --- |
| `zxmod` and `squashfs-tools` | Build and load local Zstd SquashFS modules. | zxmod extension profile |
| `file`, `less`, `curl`, `rsync`, `7zz` | Inspect, read, retrieve, copy, and archive recovery data. | maintenance profile |
| `strace`, `lsof`, `dmidecode`, `pciutils`, `ddrescue` | Diagnose processes and hardware, and recover failing media. | maintenance profile |

`005-applications` remains separate and owns graphical/desktop applications.
