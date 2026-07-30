# Applications layer

`005-applications` contains graphical and desktop applications plus their
GUI-oriented dependencies. The ordinary XFCE selection remains
`profiles/applications-desktop.packages`; it currently selects Xarchiver.

Xarchiver is a GTK3 archive browser that uses the separately selectable
`sevenzip` maintenance utility as its archive backend. It does not make the
maintenance utility profile part of the default desktop image.
