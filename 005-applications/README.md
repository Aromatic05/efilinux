# Applications layer

`005-applications` contains graphical desktop applications and GUI-oriented
libraries. Console maintenance commands, partitioning backends, SquashFS tools,
and `zxmod` belong to `005-utils`.

All recipes use versioned upstream releases with pinned SHA-256 checksums.
Optional applications install their own icons under `hicolor`; the base Qogir
theme does not preinstall icons for unloaded software.

## Ordinary desktop profile

`profiles/applications-desktop.packages` extends the XFCE desktop with:

- Mousepad, a lightweight GTK3 text editor;
- Ristretto, the XFCE image viewer;
- Pavucontrol 5.0 for PipeWire's PulseAudio compatibility API, built without optional event sounds;
- XFCE Task Manager;
- XFCE Screenshooter;
- Xarchiver and the Thunar Archive Plugin;
- Galculator.

The applications remain outside `profiles/desktop.packages`, so the default
single-EFI desktop does not grow merely because the recipes exist.

## GUI maintenance profile

`profiles/applications-gui-maintenance.packages` includes the ordinary desktop
profile and adds GParted. GParted uses the real GNU Parted package from
`005-utils` and retains its polkit action and privileged helper. Destructive
partition editing is therefore not part of the ordinary desktop profile.

## Deferred ZXM applications

Large or externally distributed software should be delivered as local `.zxm`
modules rather than embedded into the single EFI image. Current candidates are:

- WPS Office 2016 x86_64 for offline Office document compatibility;
- a browser such as Firefox ESR;
- larger recovery and forensic suites;
- remote-desktop and multimedia applications when their dependency closures
  have been measured.
