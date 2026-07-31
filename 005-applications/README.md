# Applications layer

`005-applications` contains graphical desktop applications and GUI-oriented
libraries. Console maintenance commands, partitioning backends, SquashFS tools,
and `zxmod` belong to `005-utils`.

All recipes use versioned upstream releases with pinned SHA-256 checksums.
Applications install their own icons under `hicolor`; the base Qogir theme does
not preinstall icons for software that is absent.

## Default desktop profile

`profiles/applications-desktop.packages` extends the XFCE rootfs with:

- Mousepad;
- Ristretto;
- Pavucontrol 5.0 without the optional event-sound stack;
- XFCE Task Manager;
- XFCE Screenshooter without the Imgur/libsoup upload stack;
- Xarchiver and the Thunar Archive Plugin;
- Galculator;
- GParted, including its privileged helper, polkit policy, Chinese translation,
  AppStream metadata, and GNU Parted backend.

`005-applications/image` composes this profile into the default single EFI
image.

## Deferred ZXM applications

Large or externally distributed software should be delivered as local `.zxm`
modules rather than embedded into the single EFI image. Current candidates are:

- WPS Office 2016 x86_64;
- a browser such as Firefox ESR;
- larger recovery and forensic suites;
- remote-desktop and multimedia applications after measuring their dependency
  closures.
