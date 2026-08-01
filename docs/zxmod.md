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
to replace its output. `zxmod load` validates the compression, manifest,
architecture, payload layout, source identity, and path conflicts before
switching the live system view.

## Lifecycle and safety

At first load zxmod bind-mounts the original `/usr` and `/opt` under
`/run/zxmod/base`. Every load or unload constructs a fresh read-only OverlayFS
generation, then atomically switches the live `/usr` and `/opt` mount views.
Module mounts are `ro,nodev,nosuid`; execution remains enabled so applications
can run.

Only `root/usr` and `root/opt` are accepted. A load rejects every non-directory
payload path already present in the base image or another active module, and
also rejects a module directory over a base non-directory. Format 1 has no
override mode.

After a successful load or unload, zxmod restarts active Xfce panels so Garcon
and Whisker reload application entries from the new `/usr` view. Module-owned
menu entries use directly resolvable icons. EFI Linux registers
`application/vnd.efilinux.zxm`, so opening a `.zxm` in the file manager invokes
the privileged `zxmod load` action.

## Test scope

`test/zxmod.sh` creates real module images and verifies builder validation,
load/unload behavior, simultaneous non-conflicting modules, conflict rejection,
standalone Bash completion, and the XDG MIME association. The mount namespace
section skips only when unprivileged SquashFS mounts are unavailable.
