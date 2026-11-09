-- Default variables
-- Copy these to ~/.config/hypr/custom/variables.lua to make changes in a dotfiles-update-friendly manner

-- The folder within ~/.config/quickshell containing the config
hl.env("qsConfig", "ii")

-- Apps
terminal = "kitty -1"
fileManager = "kitty -1 yazi"
browser = "zen-browser"
codeEditor = "code"
officeSoftware = "libreoffice"
textEditor = "kitty -1 vim"
volumeMixer = "pavucontrol"
settingsApp = "XDG_CURRENT_DESKTOP=gnome qs -p ~/.config/quickshell/$qsConfig/settings.qml"
taskManager = "kitty -1 btop"

workspaceGroupSize = 10
