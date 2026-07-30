# zxmod local modules

`zxmod` adds local application payloads to the immutable EFI Linux base only
after boot. A `.zxm` is a Zstd-compressed SquashFS image with this layout:

```
metadata/manifest
root/usr/...
root/opt/...
```

The manifest is newline-delimited `key=value` data. Version 1 requires exactly
one each of `format=1`, `id`, `arch`, and `version`; `description` is optional.
There are no package-manager hooks or install/post-install scripts.

```
zxmod-build --id hello --version 1.0 --description 'Example' stage hello.zxm
zxmod inspect hello.zxm
sudo zxmod load hello.zxm
sudo zxmod unload hello
zxmod list
```

`zxmod-build` accepts a staging tree containing only `usr/` and/or `opt/`. It
uses `mksquashfs -comp zstd`, normalizes ownership and timestamps, and refuses
to replace its output. Artifact names are not trusted: `inspect` and `load`
validate SquashFS compression, manifest, architecture, payload layout, and the
regular-file source identity.

## Lifecycle and safety

At first load zxmod bind-mounts the original `/usr` and `/opt` under
`/run/zxmod/base`. Every load or unload constructs a fresh OverlayFS generation
in `/run/zxmod/generations`, using read-only mounted module images and the saved
base directories as lower layers, then switches the `/usr` and `/opt` views.
OverlayFS cannot gain lower layers in place. Processes holding old files may
therefore continue using their old generation. Module mounts are
`ro,nodev,nosuid`; `noexec` is intentionally absent so applications can run.
An unloaded module's read-only mount is retained under `/run/zxmod/retired`
until reboot so older OverlayFS generations remain valid.

Only `root/usr` and `root/opt` are accepted. A load rejects every non-directory
payload path already present in the base image or another active module, and
also rejects a module directory over a base non-directory. v1 has no override
mode. The source's device, inode, size, and mtime are recorded; a changed active
source prevents a later generation switch.

State is deliberately volatile in `/run/zxmod`. Modules may come from an
already mounted data partition, USB storage, or network filesystem. zxmod does
not mount media, download, update, resolve dependencies, or use a repository.

## Optional persistent enablement

Persistence is opt-in and never uses `/var` in the built-in initramfs. Mount
writable external media first, then configure its absolute mount point in the
immutable base system:

```
# /etc/zxmod.conf
persist_root=/media/zxmod-state
```

The directory must itself be a mounted non-tmpfs filesystem. `zxmod enable
/mounted/media/hello.zxm` saves only its canonical path and identity below
`persist_root/zxmod/enabled`; `zxmod disable hello` removes that record.
`zxmod startup` loads records after the deployment's boot mounts have made the
store and module media available. Missing or changed media is reported and left
inactive; state is never silently recreated in RAM. v1 provides no boot service
because mount ordering is deployment-specific.

## Test scope

`test/zxmod.sh` creates real `.zxm` images, inspects real SquashFS metadata, and
attempts load, conflict rejection, and unload in a user+mount namespace. Hosts
with disabled unprivileged namespaces or no usable SquashFS/OverlayFS support
skip the runtime section after artifact checks.
