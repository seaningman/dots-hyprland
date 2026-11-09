# my-dots

A lean fork of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (the "illogical-impulse" Hyprland + Quickshell setup) with its own Arch-only installer. It keeps the parts I use and drops the rest, so it stays small enough to understand and maintain.

## What is in it

- **Shell (Quickshell `ii`):** bar, notification popups, volume and brightness OSD, overview with search (apps, clipboard, emoji), right sidebar (quick toggles, notifications, calendar, to-do, timer), media controls, keybind cheatsheet, session menu, lock screen, polkit prompt.
- **Tools:** region screenshot, OCR, Google Lens, screen recording, colours generated from the wallpaper (matugen).
- **Wallpaper picker:** the coverflow carousel and change transition ported from [pocket-dots](https://github.com/diegoMalagrida/pocket-dots). It reads `~/Wallpapers`.
- **Configs:** Hyprland (Lua), hypridle, hyprlock (fallback locker), Kitty, fish, starship, matugen, mpv, fuzzel and wlogout (fallbacks when the shell is down).

## What differs from end-4

- **Removed from the shell:** left sidebar (AI chat, translator, anime/booru browser), dock, on-screen keyboard, the Waffle panel family, overlay widgets, screen translator, vertical bar mode, welcome app, LaTeX rendering.
- **No KDE:** no Dolphin, System Settings, Kvantum, Darkly or kde-material-you-colors, and no Qt platform theme. Replacements: `nm-connection-editor`, `blueman-manager`, `pavucontrol`, `btop`, the GTK file chooser, yazi in Kitty as the file manager.
- **No foot, zsh or Chromium flag files.** Terminal is Kitty, shell is fish, browser is Zen.
- **Installer:** one `install.sh` with plain package lists in `packages/` instead of the multi-distro `setup` script and meta packages.
- **Extras:** battery charge limit setting, keep-awake fix for Hyprland 0.57, mpv with Anime4K shaders.

## Keybinds that changed

The full list is on the cheatsheet: **Super + -**.

| Keys | Action |
|---|---|
| Super + - | Cheatsheet (was Super + /) |
| Ctrl + Super + + / Ctrl + Super + - | Zoom in / out (was Super + = / Super + -) |
| Ctrl + Super + Alt + - | Open `hypr/custom/keybinds.lua` |
| Alt + Shift | Switch keyboard layout (German, Finnish) |
| Super + E | yazi in Kitty |
| Ctrl + Super + T | Wallpaper picker |

Gone with their modules: Super + A / B / O (left sidebar), Super + K (on-screen keyboard), Super + G (overlay), Super + Shift + T (screen translate), Ctrl + Super + P (panel family).

## Install

### Fresh Arch

1. Install a minimal Arch, for example with `archinstall`: minimal profile, NetworkManager, PipeWire, a user with sudo.
2. Reboot, log in on the TTY, connect with `nmtui` if you are on Wi-Fi.
3. Then:

```sh
sudo pacman -S --needed git
git clone https://github.com/<your-username>/dots-hyprland ~/my-dots
cd ~/my-dots
./install.sh --dry-run   # shows every action, changes nothing
./install.sh
```

4. Reboot and log in on TTY1. Hyprland starts by itself if you said yes to that question; otherwise run `start-hyprland`.

The installer asks before each change to `/etc` (multilib, the keyring lines in `/etc/pam.d/login`, fingerprint for sudo, the battery udev rule) and shows the edit first. `--yes` takes the defaults without asking.

### Existing system

```sh
git clone https://github.com/<your-username>/dots-hyprland ~/my-dots
cd ~/my-dots
./install.sh --dry-run
./install.sh
```

Anything already in `~/.config` that the repo also provides is moved to `~/.config-backup-<date-time>/` first.

### Updating

```sh
cd ~/my-dots
git pull
./install.sh                  # or: ./install.sh --skip-packages  if only configs changed
```

The folders in `~/.config` are links into the repo, so editing either side edits the same files. Two files are copied once instead of linked, because programs rewrite them while running: `illogical-impulse/config.json` (shell settings) and `mimeapps.list` (default apps). To take the repo's version of one again, delete it in `~/.config` and re-run the installer.

### Undo

Each run that replaces something prints the backup folder it used. To go back:

```sh
rm ~/.config/hypr                                  # remove the link (repeat for each linked entry)
mv ~/.config-backup-<date-time>/.config/hypr ~/.config/
```

Packages are not removed by this; the lists in `packages/` say what was installed. Edits to `/etc` leave a `*.bak-<date-time>` copy next to the file.

## Layout

```
install.sh            Arch installer
packages/             pacman.txt, aur.txt, flatpak.txt, python.txt, per-GPU and multilib lists
system/               files the installer copies into /etc (asks first)
wallpapers/           images copied to ~/Wallpapers
.config/              hypr, quickshell/ii, kitty, fish, matugen, mpv, ...
.local/               icon and the yazi desktop entry
```

Per-machine files are not tracked: generated colour files, `hypr/monitors.lua` and `hypr/workspaces.lua` (see `hypr/monitors.lua.example`).

## Updating from upstream

The layout was moved (`dots/.config` became `.config`) and whole modules were removed, so upstream cannot be merged. Pick single upstream commits instead:

```sh
git remote add upstream https://github.com/end-4/dots-hyprland   # once
git fetch upstream
git log --oneline upstream/main -- dots/.config/quickshell        # find what you want
git cherry-pick <commit>
```

Git usually follows the moved paths. A commit that touches a removed module will conflict; drop those parts.

This fork is based on upstream commit `33f31a08` (2026-10-03).

## Credits

- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland): the whole base. GPL-3.0.
- [diegoMalagrida/pocket-dots](https://github.com/diegoMalagrida/pocket-dots): wallpaper picker and change transition. GPL-3.0.
- [Anime4K](https://github.com/bloc97/Anime4K): the shaders in `.config/mpv/shaders`. MIT.

Licensed under GPL-3.0, like both upstream projects. See `LICENSE` and `licenses/`.
