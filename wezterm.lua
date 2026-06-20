local wezterm = require("wezterm")

wezterm.on("zoom-font-in", function(window, pane)
	window:perform_action(wezterm.action.IncreaseFontSize, pane)
end)

wezterm.on("zoom-font-out", function(window, pane)
	window:perform_action(wezterm.action.DecreaseFontSize, pane)
end)
local config = wezterm.config_builder()

-- =========================
-- 🎨 APPARENCE
-- =========================
------config.color_scheme = "Gruvbox dark, medium (base16)"
config.color_scheme = "nightfox"
config.window_background_opacity = 0.92
config.macos_window_background_blur = 20

config.window_padding = {
	left = 10,
	right = 10,
	top = 10,
	bottom = 25,
}

-- =========================
-- 🔤 FONT
-- =========================
config.font = wezterm.font_with_fallback({
	"Red Hat Mono",
	"Hack Nerd Font Mono",
	"JetBrains Mono",
})

config.font_size = 11.5

-- =========================
-- 🧠 UI
-- =========================
config.enable_tab_bar = false
config.audible_bell = "Disabled"
config.scrollback_lines = 5000
config.default_cursor_style = "BlinkingBlock"
config.enable_scroll_bar = true
config.colors = {
	scrollbar_thumb = "#7aa2f7",
}

config.pane_focus_follows_mouse = true

-- =========================
-- ⚡ PERF
-- =========================
config.enable_kitty_keyboard = true
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
---config.window_decorations = "RESIZE"
---config.window_decorations = "TITLE|RESIZE"
config.integrated_title_buttons = { "Hide", "Maximize", "Close" }

config.initial_cols = 120
config.initial_rows = 30

config.adjust_window_size_when_changing_font_size = false
-- =========================
-- 🪟 KEYBINDS
-- =========================
config.keys = {

	-- =========================
	-- 🪟 SPLITS
	-- =========================

	{
		key = "RightArrow",
		mods = "ALT|SHIFT",
		action = wezterm.action.SplitHorizontal({
			domain = "CurrentPaneDomain",
		}),
	},

	{
		key = "DownArrow",
		mods = "ALT|SHIFT",
		action = wezterm.action.SplitVertical({
			domain = "CurrentPaneDomain",
		}),
	},

	-- =========================
	-- 🧭 NAVIGATION
	-- =========================

	{
		key = "LeftArrow",
		mods = "ALT",
		action = wezterm.action.ActivatePaneDirection("Left"),
	},
	{
		key = "RightArrow",
		mods = "ALT",
		action = wezterm.action.ActivatePaneDirection("Right"),
	},
	{
		key = "UpArrow",
		mods = "ALT",
		action = wezterm.action.ActivatePaneDirection("Up"),
	},
	{
		key = "DownArrow",
		mods = "ALT",
		action = wezterm.action.ActivatePaneDirection("Down"),
	},

	-- =========================
	-- 🔁 MOVE MODE
	-- =========================

	{
		key = "m",
		mods = "CTRL|SHIFT",
		action = wezterm.action.ActivateKeyTable({
			name = "move_pane",
			one_shot = false,
		}),
	},

	-- =========================
	-- ❌ CLOSE PANE
	-- =========================

	{
		key = "w",
		mods = "ALT|SHIFT",
		action = wezterm.action.CloseCurrentPane({
			confirm = true,
		}),
	},
	{
		key = "r",
		mods = "CTRL|SHIFT",
		action = wezterm.action.ActivateKeyTable({
			name = "resize_pane",
			one_shot = false,
		}),
	},
}

-- =========================
-- 🔁 MOVE KEY TABLE
-- =========================
config.key_tables = {

	move_pane = {

		-- navigation inside move mode
		{
			key = "LeftArrow",
			action = wezterm.action.ActivatePaneDirection("Left"),
		},
		{
			key = "RightArrow",
			action = wezterm.action.ActivatePaneDirection("Right"),
		},
		{
			key = "UpArrow",
			action = wezterm.action.ActivatePaneDirection("Up"),
		},
		{
			key = "DownArrow",
			action = wezterm.action.ActivatePaneDirection("Down"),
		},

		-- swap / confirm reposition
		{
			key = "Enter",
			action = wezterm.action.PopKeyTable,
		},

		-- exit move mode
		{
			key = "Escape",
			action = wezterm.action.PopKeyTable,
		},
	},
	resize_pane = {

		{
			key = "LeftArrow",
			action = wezterm.action.AdjustPaneSize({ "Left", 3 }),
		},

		{
			key = "RightArrow",
			action = wezterm.action.AdjustPaneSize({ "Right", 3 }),
		},

		{
			key = "UpArrow",
			action = wezterm.action.AdjustPaneSize({ "Up", 1 }),
		},

		{
			key = "DownArrow",
			action = wezterm.action.AdjustPaneSize({ "Down", 1 }),
		},

		{
			key = "Escape",
			action = wezterm.action.PopKeyTable,
		},
	},
}

-- =========================
-- 🖱️ CLIC DROIT COPIER/COLLER/ZOOM
-- =========================
config.inactive_pane_hsb = {
	saturation = 0.6,
	brightness = 0.5,
}
config.window_frame = {
	active_titlebar_bg = "#333333",
	inactive_titlebar_bg = "#1a1a1a",
}

config.mouse_bindings = {
  -- clic droit = coller
  {
    event = { Down = { streak = 1, button = "Right" } },
    mods = "NONE",
    action = wezterm.action.PasteFrom("Clipboard"),
  },

  -- SUPER + drag = Déplacé la fenêtre 
  {
    event = { Drag = { streak = 1, button = "Left" } },
    mods = "SUPER",
    action = wezterm.action.StartWindowDrag,
  },

  -- CTRL + molette haut = zoom in
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = "CTRL",
    action = wezterm.action.EmitEvent("zoom-font-in"),
  },

  -- CTRL + molette bas = zoom out
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = "CTRL",
    action = wezterm.action.EmitEvent("zoom-font-out"),
  },
}

-- =========================
-- 🔗 LIENS CLIQUABLES
-- =========================
config.hyperlink_rules = wezterm.default_hyperlink_rules()

return config
