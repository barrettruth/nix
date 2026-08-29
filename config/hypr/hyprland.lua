hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("GTK_USE_PORTAL", "1")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")

hl.config({
	cursor = {
		no_hardware_cursors = true,
		zoom_rigid = true,
	},

	general = {
		gaps_in = 0,
		gaps_out = 0,
		border_size = 3,
		layout = "master",
		resize_on_border = true,
	},

	master = {
		new_status = "slave",
		new_on_top = false,
		mfact = 0.50,
	},

	decoration = {
		rounding = 0,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		blur = {
			enabled = false,
		},
	},

	animations = {
		enabled = true,
	},

	input = {
		kb_layout = "us,us,us",
		kb_variant = ",dvorak,colemak_dh",
		follow_mouse = 1,
		sensitivity = 0,
		touchpad = {
			tap_to_click = false,
		},
		repeat_delay = 300,
		repeat_rate = 50,
	},

	ecosystem = {
		no_donation_nag = true,
		no_update_news = true,
	},

	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
	},
})

pcall(require, "~/.config/hypr/themes/theme.lua")

hl.curve("easeOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "easeOut", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "easeOut" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 5, bezier = "easeOut" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOut", style = "slide" })
hl.animation({ leaf = "layers", enabled = false })
hl.animation({ leaf = "fadeLayers", enabled = false })
hl.animation({ leaf = "border", enabled = false })
hl.animation({ leaf = "borderangle", enabled = false })

hl.gesture({ fingers = 3, direction = "pinch", action = "cursor_zoom", zoom_level = "1", mode = "live" })
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.on("hyprland.start", function()
	hl.exec_cmd("ctl wallpaper gen")
	hl.exec_cmd("hypr spawnfocus --ws 1 $TERMINAL -e nvim -c 'Mux ~/.config/nix'")
	hl.exec_cmd("hypr spawnfocus --ws 2 $BROWSER")
end)

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("ctl volume up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("ctl volume down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("ctl volume toggle"), { locked = true })

hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("ctl brightness up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("ctl brightness down"), { locked = true, repeating = true })

hl.bind("ALT + mouse:273", hl.dsp.window.drag())

hl.bind("ALT + SPACE", hl.dsp.exec_cmd("fuzzel"))
hl.bind("ALT + SHIFT + SPACE", hl.dsp.exec_cmd("fuzzel --list-executables-in-path --no-icons"))
hl.bind("ALT + TAB", hl.dsp.focus({ workspace = "previous" }))
hl.bind("ALT + A", hl.dsp.window.cycle_next())
hl.bind("ALT + B", hl.dsp.exec_cmd("waybarctl toggle"))
hl.bind("ALT + D", hl.dsp.layout("swapnext"))
hl.bind("ALT + F", hl.dsp.window.cycle_next({ next = false }))
hl.bind("ALT + H", hl.dsp.window.resize({ x = -15, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + J", hl.dsp.window.resize({ x = 0, y = 15, relative = true }), { repeating = true })
hl.bind("ALT + K", hl.dsp.window.resize({ x = 0, y = -15, relative = true }), { repeating = true })
hl.bind("ALT + L", hl.dsp.window.resize({ x = 15, y = 0, relative = true }), { repeating = true })
hl.bind("ALT + Q", hl.dsp.window.close())
hl.bind("ALT + U", hl.dsp.layout("swapprev"))

hl.bind("ALT + CTRL + B", hl.dsp.exec_cmd("hypr pull $BROWSER"))
hl.bind("ALT + CTRL + T", hl.dsp.exec_cmd("hypr pull $TERMINAL"))
hl.bind("ALT + CTRL + Z", hl.dsp.exec_cmd("hypr pull zathura"))

hl.bind("ALT + SHIFT + RETURN", hl.dsp.exec_cmd("hypr spawnfocus --ws 1 $TERMINAL"))
hl.bind("ALT + SHIFT + B", hl.dsp.exec_cmd("hypr spawnfocus --ws 2 $BROWSER"))
hl.bind("ALT + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind("ALT + SHIFT + Q", hl.dsp.exec_cmd("hypr exit"))
hl.bind("ALT + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload && notify-send 'Hyprland' 'Compositor reloaded'"))
hl.bind("ALT + SHIFT + Z", hl.dsp.exec_cmd("hypr spawnfocus --ws 3 zathura"))

hl.bind("XF86Tools", hl.dsp.submap("scripts"))

hl.define_submap("scripts", "reset", function()
	hl.bind("A", hl.dsp.exec_cmd("ctl audio sink"))
	hl.bind("C", hl.dsp.exec_cmd("ctl clip"))
	hl.bind("K", hl.dsp.exec_cmd("ctl keyboard next"))
	hl.bind("M", hl.dsp.exec_cmd("ctl media"))
	hl.bind("P", hl.dsp.exec_cmd("ctl power"))
	hl.bind("S", hl.dsp.exec_cmd("ctl screenshot"))
	hl.bind("D", hl.dsp.exec_cmd("ctl dictate"))
	hl.bind("T", hl.dsp.exec_cmd("theme"))
	hl.bind("W", hl.dsp.exec_cmd("ctl wifi pick"))

	hl.bind("catchall", hl.dsp.submap("reset"), { release = true })
end)

for i = 1, 9 do
	hl.bind("ALT + " .. i, hl.dsp.focus({ workspace = i }))
	hl.bind("ALT + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
	hl.bind("ALT + CTRL + " .. i, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

hl.window_rule({
	name = "no-gaps-wtv1",
	match = { float = false, workspace = "w[tv1]" },
	border_size = 0,
	rounding = 0,
})
hl.window_rule({
	name = "no-gaps-f1",
	match = { float = false, workspace = "f[1]" },
	border_size = 0,
	rounding = 0,
})

for _, portal in ipairs({ "xdg-desktop-portal-gtk", "xdg-desktop-portal-kde", "xdg-desktop-portal-hyprland" }) do
	hl.window_rule({
		name = "float-" .. portal,
		match = { class = "^(" .. portal .. ")$" },
		float = true,
		size = "monitor_w * 0.5 monitor_h * 0.6",
	})
end
