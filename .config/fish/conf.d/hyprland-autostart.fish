# Start Hyprland after logging in on TTY1.
# install.sh turns this on by creating the flag file below; delete the file to turn it off.
if status is-login; and test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = 1
    if test -e ~/.local/state/my-dots/autostart-hyprland
        exec start-hyprland
    end
end
