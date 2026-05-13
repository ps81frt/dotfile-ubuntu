local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- =========================
-- 🎨 APPARENCE
-- =========================
config.color_scheme = "Gruvbox dark, medium (base16)"
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

config.pane_focus_follows_mouse = true

-- =========================
-- ⚡ PERF
-- =========================
config.enable_kitty_keyboard = true
config.window_decorations = "TITLE|RESIZE"

config.initial_cols = 120
config.initial_rows = 30

-- =========================
-- 🪟 KEYBINDS
-- =========================
config.keys = {

	-- =========================
	-- 🪟 SPLITS (UNCHANGED)
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
	-- 🧭 NAVIGATION (UNCHANGED)
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
	-- 🔁 MOVE MODE (NEW CLEAN FIX)
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
	-- ❌ CLOSE PANE (FIXED confirm typo)
	-- =========================

	{
		key = "w",
		mods = "ALT|SHIFT",
		action = wezterm.action.CloseCurrentPane({
			confirm = true,
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
			action = wezterm.action.PaneSelect,
		},

		-- exit move mode
		{
			key = "Escape",
			action = wezterm.action.PopKeyTable,
		},
	},
}

return config
