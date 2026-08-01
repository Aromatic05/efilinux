case $(/usr/bin/tty 2>/dev/null || true) in
    /dev/tty7)
        if [ -z "${DISPLAY:-}" ]; then
            export GDK_BACKEND=x11
            export XDG_SESSION_TYPE=x11
            export XDG_SESSION_DESKTOP=xfce
            exec /usr/bin/startx /etc/X11/xinit/xinitrc -- \
                /usr/bin/Xorg :0 vt7 -nolisten tcp -noreset
        fi
        ;;
esac
