case $(/usr/bin/tty 2>/dev/null || true) in
    /dev/tty7)
        runtime_dir=${XDG_RUNTIME_DIR:-}
        if [ -z "${XDG_SESSION_ID:-}" ] || [ -z "$runtime_dir" ] || \
           [ ! -d "$runtime_dir" ] || \
           [ "$(/usr/bin/stat -c %u "$runtime_dir" 2>/dev/null || true)" != "$(/usr/bin/id -u)" ]; then
            printf '%s\n' 'Cannot start X: elogind did not create the user session runtime directory.' >&2
            /usr/bin/sleep 5
            exit 1
        fi
        if [ -z "${DISPLAY:-}" ]; then
            export GDK_BACKEND=x11
            export XDG_SESSION_TYPE=x11
            export XDG_SESSION_DESKTOP=efilinux-graphical
            export XDG_CURRENT_DESKTOP=EFILinux
            exec /usr/bin/startx /etc/X11/xinit/xinitrc -- \
                /usr/bin/Xorg :0 vt7 -nolisten tcp -noreset
        fi
        ;;
esac
