# Utilities layer

`005-utils` contains local `.zxm` support, SquashFS tooling, and the default
command-line maintenance set embedded in the single EFI image.

`005-utils/image` extends the composed rootfs with
`profiles/utils-maintenance.packages`.  That profile includes the smaller
`utils-zxmod.packages` profile, so module support and maintenance commands are
installed together in the default image.

| Item | Purpose |
| --- | --- |
| `zxmod` and `squashfs-tools` | Build and load local Zstd SquashFS modules. |
| `file`, `less`, `curl`, `rsync`, `7zz` | Inspect, read, retrieve, copy, and archive recovery data. |
| `strace`, `lsof`, `dmidecode`, `pciutils` | Diagnose processes and hardware. |
| `ddrescue`, `parted` | Recover failing media and edit partition tables. |

Graphical applications remain in `005-applications`.
