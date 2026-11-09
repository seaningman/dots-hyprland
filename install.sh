#!/usr/bin/env bash
# Arch installer for these dotfiles.
#
# Takes a fresh minimal Arch install (base system, a user with sudo, internet)
# to a working Hyprland desktop, and can be re-run at any time: packages use
# --needed, links and services are checked before they are touched, and
# existing configs are moved to a backup folder, never deleted.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
BACKUP_DIR="$HOME/.config-backup-$STAMP"
VENV="$STATE_DIR/quickshell/.venv"
AUTOSTART_FLAG="$STATE_DIR/my-dots/autostart-hyprland"
TOTAL_STEPS=11

DRY_RUN=false
ASSUME_YES=false
SKIP_PACKAGES=false

LINKED=()
BACKED_UP=()
NOTES=()
STEP=0

if [[ -t 1 ]]; then
    C_STEP=$'\e[1;36m' C_OK=$'\e[32m' C_WARN=$'\e[33m' C_ERR=$'\e[1;31m' C_DIM=$'\e[2m' C_RST=$'\e[0m'
else
    C_STEP='' C_OK='' C_WARN='' C_ERR='' C_DIM='' C_RST=''
fi

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --dry-run         Print every action, change nothing
  --yes             No prompts, use the defaults
  --skip-packages   Only link configs and do the setup steps
  --help            Show this help

Package lists are in packages/. Existing configs are moved to
~/.config-backup-<date-time>/ before a link replaces them.
EOF
}

step() { STEP=$((STEP + 1)); printf '\n%s==> [%d/%d] %s%s\n' "$C_STEP" "$STEP" "$TOTAL_STEPS" "$1" "$C_RST"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s%s%s\n' "$C_OK" "$*" "$C_RST"; }
warn() { printf '    %swarning:%s %s\n' "$C_WARN" "$C_RST" "$*"; }
die()  { printf '%serror:%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; exit 1; }
note() { NOTES+=("$*"); }

# Print a command, and run it unless this is a dry run.
run() {
    printf '    %s$ %s%s\n' "$C_DIM" "$(printf '%q ' "$@")" "$C_RST"
    $DRY_RUN || "$@"
}

# ask "Question" y|n  -> returns 0 for yes. --yes, --dry-run and non-interactive runs take the default.
ask() {
    local question=$1 default=$2 reply hint='[y/N]'
    [[ $default == y ]] && hint='[Y/n]'
    if $ASSUME_YES || $DRY_RUN || [[ ! -t 0 ]]; then
        info "$question $hint -> $default (default)"
        [[ $default == y ]]
        return
    fi
    read -r -p "    $question $hint " reply
    reply=${reply:-$default}
    [[ $reply =~ ^[Yy] ]]
}

# One entry per line; blank lines and # comments are skipped.
read_list() { [[ -f $1 ]] && sed -E 's/#.*//; s/[[:space:]]+$//; /^$/d' "$1" || true; }

confirm_flag() { if $ASSUME_YES; then echo --noconfirm; fi; }

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --yes) ASSUME_YES=true ;;
        --skip-packages) SKIP_PACKAGES=true ;;
        --help | -h) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $arg" ;;
    esac
done

# ---------------------------------------------------------------- 1. checks

step "Pre-checks"
[[ -f /etc/arch-release ]] || die "this installer only supports Arch Linux (/etc/arch-release not found)"
[[ $EUID -ne 0 ]] || die "run this as your normal user, not as root; sudo is used where needed"
command -v sudo >/dev/null || die "sudo is not installed; install it and add your user to the wheel group"
if ! $DRY_RUN; then
    sudo -v || die "sudo does not work for $USER"
    # Keep the sudo timestamp alive during long AUR builds.
    (while sudo -n true 2>/dev/null; do sleep 50; done) &
    SUDO_KEEPALIVE=$!
    trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
fi
curl -fsS --max-time 15 -o /dev/null https://archlinux.org || die "no internet connection (could not reach archlinux.org)"
ok "Arch Linux, user $USER, sudo and internet are fine"
$DRY_RUN && info "dry run: nothing below is executed"

# -------------------------------------------------- 2. repos, system update

multilib_enabled() { grep -Eq '^\[multilib\]' /etc/pacman.conf; }
MULTILIB=false
multilib_enabled && MULTILIB=true

step "Repositories and system update"
if $SKIP_PACKAGES; then
    info "skipped (--skip-packages)"
else
    if ! $MULTILIB; then
        info "Steam needs the [multilib] repo. This would uncomment these two lines in /etc/pacman.conf:"
        info "    [multilib]"
        info "    Include = /etc/pacman.d/mirrorlist"
        if ask "Enable [multilib]?" y; then
            run sudo cp /etc/pacman.conf "/etc/pacman.conf.bak-$STAMP"
            run sudo sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' /etc/pacman.conf
            MULTILIB=true
        else
            warn "multilib stays off: Steam and the 32-bit drivers are skipped"
            note "Steam was not installed because [multilib] is disabled."
        fi
    fi
    # shellcheck disable=SC2046
    run sudo pacman -Syu $(confirm_flag)
    # shellcheck disable=SC2046
    run sudo pacman -S --needed $(confirm_flag) base-devel git
fi

# ------------------------------------------------------------ 3. AUR helper

AUR_HELPER=''
step "AUR helper"
if $SKIP_PACKAGES; then
    info "skipped (--skip-packages)"
else
    if command -v yay >/dev/null; then
        AUR_HELPER=yay
    elif command -v paru >/dev/null; then
        AUR_HELPER=paru
    else
        info "neither yay nor paru found: building yay-bin from the AUR"
        build_dir="$(mktemp -d)"
        run git clone https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin"
        if ! $DRY_RUN; then
            (cd "$build_dir/yay-bin" && makepkg -si --noconfirm)
        else
            info "\$ (cd $build_dir/yay-bin && makepkg -si --noconfirm)"
        fi
        rm -rf "$build_dir"
        AUR_HELPER=yay
    fi
    ok "using $AUR_HELPER"
fi

# -------------------------------------------------------------- 4. packages

# GPU vendors from sysfs, so no extra tool is needed on a minimal system.
gpu_vendors() { cat /sys/class/drm/card*/device/vendor 2>/dev/null | sort -u; }

step "Packages"
if $SKIP_PACKAGES; then
    info "skipped (--skip-packages)"
else
    mapfile -t pkgs < <(read_list "$REPO/packages/pacman.txt")
    $MULTILIB && mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$REPO/packages/multilib.txt")
    for vendor in $(gpu_vendors); do
        case $vendor in
            0x8086) gpu=intel ;;
            0x1002) gpu=amd ;;
            0x10de)
                warn "NVIDIA GPU found: its driver is not installed by this script"
                note "NVIDIA GPU detected. Install the driver yourself (see the Arch wiki and the Hyprland wiki NVIDIA page)."
                continue ;;
            *) continue ;;
        esac
        info "$gpu GPU detected"
        mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$REPO/packages/gpu-$gpu.txt")
        $MULTILIB && mapfile -t -O "${#pkgs[@]}" pkgs < <(read_list "$REPO/packages/gpu-$gpu-multilib.txt")
    done
    # shellcheck disable=SC2046
    run sudo pacman -S --needed $(confirm_flag) "${pkgs[@]}"

    mapfile -t aur_pkgs < <(read_list "$REPO/packages/aur.txt")
    if ((${#aur_pkgs[@]})); then
        aur_flags=(--needed)
        if $ASSUME_YES; then
            aur_flags+=(--noconfirm)
            [[ $AUR_HELPER == yay ]] && aur_flags+=(--answerdiff None --answerclean None --answeredit None)
            [[ $AUR_HELPER == paru ]] && aur_flags+=(--skipreview)
        fi
        run "$AUR_HELPER" -S "${aur_flags[@]}" "${aur_pkgs[@]}"
    fi

    # Packages that were already installed as dependencies would otherwise be
    # removed as orphans later; everything on the lists is wanted explicitly.
    if ! $DRY_RUN; then
        mapfile -t installed < <(pacman -Qq "${pkgs[@]}" "${aur_pkgs[@]}" 2>/dev/null || true)
        ((${#installed[@]})) && sudo pacman -D --asexplicit "${installed[@]}" >/dev/null
    fi

    mapfile -t flatpaks < <(read_list "$REPO/packages/flatpak.txt")
    if ((${#flatpaks[@]})); then
        run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        run flatpak install --user -y flathub "${flatpaks[@]}"
        # Let Flatpak apps read the generated GTK colours.
        run flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro
    fi

    # Claude Code: the official native installer (it updates itself).
    if command -v claude >/dev/null || [[ -x $HOME/.local/bin/claude ]]; then
        info "Claude Code is already installed"
    else
        installer="$(mktemp)"
        run curl -fsSL https://claude.ai/install.sh -o "$installer"
        run bash "$installer"
        rm -f "$installer"
    fi

    # reanime: no package exists, so it is installed as a uv tool into ~/.local/bin.
    if command -v reanime >/dev/null || [[ -e $HOME/.local/bin/reanime ]]; then
        info "reanime is already installed"
    else
        run uv tool install git+https://github.com/vashhdev/reanime
    fi
fi

# --------------------------------------------------------------- 5. configs

# link_entry <source in repo> <destination>: links, moving anything in the way to the backup folder.
link_entry() {
    local src=$1 dst=$2 rel
    if [[ -L $dst && "$(readlink -f -- "$dst")" == "$(readlink -f -- "$src")" ]]; then
        return 0
    fi
    if [[ -e $dst || -L $dst ]]; then
        rel=${dst#"$HOME"/}
        [[ -d $BACKUP_DIR/$(dirname -- "$rel") ]] || run mkdir -p "$BACKUP_DIR/$(dirname -- "$rel")"
        run mv -- "$dst" "$BACKUP_DIR/$rel"
        BACKED_UP+=("$rel")
    fi
    [[ -d $(dirname -- "$dst") ]] || run mkdir -p "$(dirname -- "$dst")"
    run ln -s -- "$src" "$dst"
    LINKED+=("${dst/#$HOME/\~}")
}

# copy_once <source in repo> <destination>: for files that programs rewrite at runtime.
copy_once() {
    local src=$1 dst=$2
    [[ -e $dst ]] && return 0
    run mkdir -p "$(dirname -- "$dst")"
    run cp -- "$src" "$dst"
}

step "Configs"
if [[ -d $REPO/.git ]]; then
    run git -C "$REPO" submodule update --init --recursive
fi
$DRY_RUN || [[ -f $REPO/.config/quickshell/ii/modules/common/widgets/shapes/ShapeCanvas.qml ]] ||
    warn "the shapes submodule is empty; clone the repo with git, not as a zip download"

shopt -s nullglob dotglob
for src in "$REPO"/.config/*; do
    name=$(basename -- "$src")
    case $name in
        # Rewritten by the shell and by apps while they run, so these are copied once, not linked.
        illogical-impulse | mimeapps.list) continue ;;
    esac
    link_entry "$src" "$CONFIG_DIR/$name"
done
shopt -u nullglob dotglob
copy_once "$REPO/.config/illogical-impulse/config.json" "$CONFIG_DIR/illogical-impulse/config.json"
copy_once "$REPO/.config/mimeapps.list" "$CONFIG_DIR/mimeapps.list"

# Files outside .config are linked one by one, so ~/.local keeps everything else in it.
while IFS= read -r -d '' src; do
    link_entry "$src" "$HOME/${src#"$REPO"/}"
done < <(find "$REPO/.local" -type f -print0)

# Generated files (colours, fish state) start from the *.default copies.
while IFS= read -r -d '' seed; do
    target="$CONFIG_DIR/${seed#"$REPO"/.config/}"
    copy_once "$seed" "${target%.default}"
done < <(find "$REPO/.config" -name '*.default' -print0)

if ((${#LINKED[@]})); then ok "linked ${#LINKED[@]} entries"; else ok "all links already in place"; fi

# -------------------------------------------------------------- 6. services

enable_service() {
    local unit=$1
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        info "$unit is already enabled"
    else
        run sudo systemctl enable --now "$unit"
    fi
}

step "Services"
# NetworkManager: the bar's network indicator and Wi-Fi menu talk to it.
if ! systemctl is-enabled --quiet NetworkManager 2>/dev/null &&
    { systemctl is-active --quiet systemd-networkd || systemctl is-active --quiet iwd; }; then
    warn "another network service is active; enabling NetworkManager for the next boot only"
    run sudo systemctl enable NetworkManager
    note "NetworkManager was enabled but not started, because systemd-networkd or iwd is running. Disable that one and reboot."
else
    enable_service NetworkManager
fi
# bluetooth: the Bluetooth quick toggle and device list.
enable_service bluetooth
# power-profiles-daemon: the power profile toggle.
enable_service power-profiles-daemon

# ydotool (user service): the clipboard history uses it to paste.
if systemctl --user is-enabled --quiet ydotool 2>/dev/null; then
    info "ydotool (user) is already enabled"
elif [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    run systemctl --user enable ydotool
else
    run sudo systemctl --machine="$USER@.host" --user enable ydotool
fi

# Groups: video and input for brightness and ydotool, i2c for external monitor brightness (ddcutil).
getent group i2c >/dev/null || run sudo groupadd i2c
for group in video input i2c; do
    if grep -qw "$group" <<<"$(id -nG "$USER")"; then
        info "$USER is already in the $group group"
    else
        run sudo usermod -aG "$group" "$USER"
    fi
done
if [[ ! -f /etc/modules-load.d/i2c-dev.conf ]]; then
    info "loading the i2c-dev module at boot (for ddcutil):"
    run sudo sh -c 'echo i2c-dev > /etc/modules-load.d/i2c-dev.conf'
fi

# ------------------------------------------------ 7. shell and default apps

step "Default shell and default apps"
if [[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/fish ]]; then
    info "fish is already the login shell"
elif [[ -x /usr/bin/fish ]] || $DRY_RUN; then
    run sudo chsh -s /usr/bin/fish "$USER"
else
    warn "fish is not installed; the login shell was not changed"
fi
if command -v xdg-settings >/dev/null; then
    if [[ "$(xdg-settings get default-web-browser 2>/dev/null)" == zen.desktop ]]; then
        info "Zen is already the default browser"
    else
        run xdg-settings set default-web-browser zen.desktop
    fi
fi
command -v xdg-user-dirs-update >/dev/null && run xdg-user-dirs-update

# -------------------------------------------------------------- 8. theme

gset() {
    if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
        run gsettings set org.gnome.desktop.interface "$@"
    else
        run dbus-run-session gsettings set org.gnome.desktop.interface "$@"
    fi
}

step "First theme"
# Python environment for the colour, thumbnail and image scripts.
if [[ -x $VENV/bin/python ]]; then
    info "Python environment exists"
else
    run uv venv --prompt .venv -p 3.12 "$VENV"
fi
run uv pip install -q -p "$VENV/bin/python" -r "$REPO/packages/python.txt"

# The shell's main font is not packaged; end-4 publishes it as a git repo.
FONT_DIR="$DATA_DIR/fonts/illogical-impulse-google-sans-flex"
if [[ -n "$(fc-list 'Google Sans Flex' 2>/dev/null)" || -d $FONT_DIR ]]; then
    info "Google Sans Flex is already installed"
else
    run git clone --depth 1 --recurse-submodules https://github.com/end-4/google-sans-flex "$FONT_DIR"
fi
run fc-cache -f

if command -v gsettings >/dev/null || $DRY_RUN; then
    gset font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
    gset color-scheme 'prefer-dark'
    gset gtk-theme 'adw-gtk3-dark'
    gset icon-theme 'breeze-dark'
    gset cursor-theme 'Bibata-Modern-Classic'
fi

# The wallpaper picker reads ~/Wallpapers. Colours are generated from the
# wallpaper the first time the shell starts.
run mkdir -p "$HOME/Wallpapers"
shopt -s nullglob nocaseglob
for img in "$REPO"/.config/quickshell/ii/assets/images/default_wallpaper.png "$REPO"/wallpapers/*.{png,jpg,jpeg,webp,avif}; do
    [[ -e $HOME/Wallpapers/$(basename -- "$img") ]] || run cp -- "$img" "$HOME/Wallpapers/"
done
shopt -u nullglob nocaseglob

# -------------------------------------------------- 9. starting Hyprland

step "Starting Hyprland"
if [[ -e $AUTOSTART_FLAG ]]; then
    info "Hyprland already starts automatically on TTY1"
elif ask "Start Hyprland automatically after logging in on TTY1?" n; then
    run mkdir -p "$(dirname -- "$AUTOSTART_FLAG")"
    run touch "$AUTOSTART_FLAG"
else
    info "not enabled; start it by hand with: start-hyprland"
fi
if systemctl is-enabled --quiet display-manager.service 2>/dev/null; then
    note "A display manager is enabled on this system. It was left alone; pick the Hyprland session there."
fi

# ------------------------------------------------ 10. laptop and login extras

# Prints /etc/pam.d/login with the two keyring lines added after the last auth and session lines.
pam_login_with_keyring() {
    awk '
        { lines[NR] = $0 }
        $1 == "auth" || $1 == "-auth" { last_auth = NR }
        $1 == "session" || $1 == "-session" { last_session = NR }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_auth) print "auth       optional     pam_gnome_keyring.so"
                if (i == last_session) print "session    optional     pam_gnome_keyring.so auto_start"
            }
        }' /etc/pam.d/login
}

step "Login keyring, fingerprint, battery"
# Without a display manager nothing unlocks the keyring at login, so apps would ask for it.
if grep -q pam_gnome_keyring /etc/pam.d/login 2>/dev/null; then
    info "the keyring is already unlocked at login"
elif [[ -f /etc/pam.d/login ]]; then
    info "to unlock the keyring at TTY login, /etc/pam.d/login would change like this:"
    new_pam="$(mktemp)"
    pam_login_with_keyring >"$new_pam"
    diff -u /etc/pam.d/login "$new_pam" | sed 's/^/      /' || true
    if ask "Apply this edit to /etc/pam.d/login?" y; then
        run sudo cp /etc/pam.d/login "/etc/pam.d/login.bak-$STAMP"
        run sudo install -m 644 "$new_pam" /etc/pam.d/login
    fi
    rm -f "$new_pam"
fi

if command -v lsusb >/dev/null && grep -Eiq 'fingerprint|06cb:|27c6:|138a:|1c7a:|04f3:0c' <<<"$(lsusb)"; then
    info "fingerprint reader found"
    if grep -q pam_fprintd /etc/pam.d/sudo 2>/dev/null; then
        info "sudo already accepts a fingerprint"
    else
        info "to use it for sudo, this line would be added at the top of /etc/pam.d/sudo (the password keeps working):"
        info "    auth       sufficient   pam_fprintd.so"
        if ask "Apply this edit to /etc/pam.d/sudo?" n; then
            run sudo cp /etc/pam.d/sudo "/etc/pam.d/sudo.bak-$STAMP"
            run sudo sed -i '0,/^auth/s//auth       sufficient   pam_fprintd.so\n&/' /etc/pam.d/sudo
        fi
    fi
    if ! $ASSUME_YES && ask "Enrol a finger now (fprintd-enroll)?" n; then
        run fprintd-enroll
    fi
    note "Fingerprint: enrol with fprintd-enroll. The lock screen picks it up on its own once a finger is enrolled."
else
    info "no fingerprint reader found"
fi

if compgen -G "/sys/class/power_supply/BAT*/charge_control_end_threshold" >/dev/null; then
    if [[ -f /etc/udev/rules.d/90-battery-charge-limit.rules ]]; then
        info "the battery charge limit rule is already installed"
    else
        info "the shell's charge limit setting needs write access to the battery thresholds;"
        info "this would install system/90-battery-charge-limit.rules to /etc/udev/rules.d/"
        if ask "Install the udev rule?" y; then
            run sudo install -m 644 "$REPO/system/90-battery-charge-limit.rules" /etc/udev/rules.d/
            run sudo udevadm control --reload
            run sudo udevadm trigger --subsystem-match=power_supply
        fi
    fi
else
    info "no battery with charge thresholds found"
fi

# Optional: the wallpaper change transition can outline the subject of a picture.
# That needs a separate ~1 GB Python environment, so it is off unless asked for.
if [[ ! -d $DATA_DIR/wallfx ]] && ask "Install the cut-out environment for the wallpaper transition (about 1 GB)?" n; then
    run env ILLOGICAL_IMPULSE_VIRTUAL_ENV="$VENV" "$REPO/.config/quickshell/ii/scripts/wallfx/wallfx-venv.sh" instalar
fi

# -------------------------------------------------------------- 11. summary

step "Summary"
if $DRY_RUN; then
    info "dry run finished: nothing was changed"
fi
if $SKIP_PACKAGES; then
    info "packages: skipped"
else
    info "packages: $(read_list "$REPO/packages/pacman.txt" | wc -l) official, $(read_list "$REPO/packages/aur.txt" | wc -l) AUR, $(read_list "$REPO/packages/flatpak.txt" | wc -l) Flatpak (plus drivers for this machine)"
fi
if ((${#LINKED[@]})); then
    info "linked to $REPO:"
    printf '      %s\n' "${LINKED[@]}"
else
    info "links: nothing to change"
fi
if ((${#BACKED_UP[@]})); then
    info "previous configs were moved to $BACKUP_DIR:"
    printf '      %s\n' "${BACKED_UP[@]}"
fi
for n in "${NOTES[@]+"${NOTES[@]}"}"; do warn "$n"; done
if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    info "next: log out and back in so group and shell changes apply"
elif [[ -e $AUTOSTART_FLAG ]]; then
    info "next: reboot and log in on TTY1; Hyprland starts by itself"
else
    info "next: reboot, log in on TTY1 and run: start-hyprland"
fi
