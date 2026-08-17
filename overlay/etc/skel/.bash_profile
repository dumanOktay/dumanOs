# Auto-start graphical desktop on TTY1 login
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    if command -v startplasma-wayland &> /dev/null; then
        exec startplasma-wayland
    elif command -v startplasma-x11 &> /dev/null; then
        exec startplasma-x11
    elif command -v startx &> /dev/null; then
        exec startx
    fi
fi
