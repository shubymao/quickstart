-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices

-- Updated to JetBrains Mono
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 18

-- disable this to prevent tabs
config.enable_tab_bar = false

config.window_decorations = "TITLE | RESIZE"

config.window_background_opacity = 0.8
config.macos_window_background_blur = 10
config.window_close_confirmation = "NeverPrompt"
config.window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
}

local mux = wezterm.mux

wezterm.on("gui-startup", function()
    local tab, pane, window = mux.spawn_window({})
    window:gui_window():maximize()
end)

return config