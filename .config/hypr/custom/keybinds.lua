hl.bind("CTRL + SUPER + ALT + Minus", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), { description = "User: Edit user keybinds" })

-- Super tap opens search on release; pressing anything else while Super is held
-- must interrupt that, otherwise Super+<key> also opens the launcher.
local superKeycodes = { [133] = true, [134] = true } -- Super_L, Super_R
local function superHeld() return hl.is_key_down(133) or hl.is_key_down(134) end
local function interruptSearch() hl.dispatch(hl.dsp.global("quickshell:searchToggleReleaseInterrupt")) end

hl.on("input.keyboard.key", function(keycode, _, state)
    if state == 1 and not superKeycodes[keycode] and superHeld() then interruptSearch() end
end)
for _, button in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275", "mouse:276", "mouse:277", "mouse_up", "mouse_down", "mouse_left", "mouse_right" }) do
    hl.bind("SUPER + " .. button, interruptSearch, { ignore_mods = true, non_consuming = true })
end
