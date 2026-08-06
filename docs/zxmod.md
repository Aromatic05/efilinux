# zxmod local modules

`zxmod` adds local utility or application payloads to the immutable EFI Linux
base after boot. A `.zxm` is a Zstd-compressed SquashFS image with this layout:

```
metadata/manifest
root/usr/...
root/opt/...
```

The manifest is newline-delimited `key=value` data. Format 1 requires exactly
one each of `format=1`, `id`, `arch`, and `version`; `description` is optional.
Modules may also contain controlled load and unload hooks under `metadata/hooks`.

```
zxmod-build --id hello --version 1.0 --description 'Example' stage hello.zxm
zxmod load hello.zxm
zxmod unload hello
```

These are the only runtime commands. Module state is volatile and lasts until
unload or reboot. EFI Linux does not provide enable, disable, startup, list, or
inspection commands.

`zxmod-build` accepts a staging tree containing only `usr/` and/or `opt/`. It
uses Zstd-compressed SquashFS, normalizes ownership and timestamps, and refuses
to replace its output. `zxmod load` trusts builder-produced modules: it reads
the module ID, mounts the SquashFS read-only, and switches the live system view.
It does not hash the module, traverse its payload, validate its architecture or
compression, or reject path conflicts while loading.

## Lifecycle and safety

At first load zxmod bind-mounts the original `/usr` and `/opt` under
`/run/zxmod/base`. Every load or unload constructs a fresh read-only OverlayFS
generation, then atomically switches the live `/usr` and `/opt` mount views.
Module mounts are `ro,nodev,nosuid`; execution remains enabled so applications
can run.

The builder accepts only `root/usr` and `root/opt`. At runtime, later modules
are placed before earlier modules and the base system in the OverlayFS lowerdir
order, so a later module overrides an existing path until it is unloaded.

After a successful load or unload, zxmod restarts active Xfce panels so Garcon
and Whisker reload application entries from the new `/usr` view. Module-owned
menu entries use directly resolvable icons. EFI Linux registers
`application/vnd.efilinux.zxm`, so opening a `.zxm` in the file manager invokes
the privileged `zxmod load` action.

## Test scope

`test/zxmod.sh` creates real module images and verifies builder validation,
load/unload behavior, module overlay precedence and restoration, standalone
Bash completion, and the XDG MIME association. The mount namespace
section skips only when unprivileged SquashFS mounts are unavailable.
