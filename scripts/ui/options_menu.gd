class_name OptionsMenu
extends Control
## Options overlay: graphics, audio, controls and full key rebinding.

signal closed

var _cap_action := ""
var _cap_slot := ""
var _cap_label: Label
var _bind_buttons: Dictionary = {}   # "action|slot" -> Button
var _toast: Label


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 900)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(UITheme.label("OPTIONS", 34, UITheme.ACCENT))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	tabs.add_child(_build_display_tab())
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_gameplay_tab())
	tabs.add_child(_build_flight_tab())
	tabs.add_child(_build_osd_tab())
	tabs.add_child(_build_controls_tab())
	tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL

	_toast = UITheme.label("", 18, UITheme.MUTED)
	vb.add_child(_toast)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(foot)
	foot.add_child(UITheme.button("Reset all settings", func():
		Settings.reset_opts()
		Settings.reset_bindings_to_default()
		Settings.apply_all()
		Settings.save_settings()
		_say("Defaults restored - reopen Options to see them."), Vector2(220, 46)))
	foot.add_child(UITheme.accent_button("Save & close", _close, Vector2(200, 46)))

	_cap_label = UITheme.label("", 30, Color.WHITE)
	_cap_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cap_label.add_theme_stylebox_override("normal", UITheme.flat(Color(0, 0, 0, 0.88), 0))
	_cap_label.visible = false
	_cap_label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cap_label)


func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _scroll_grid(name: String, cols: int) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_right", 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(g)
	return [sc, g]


func _row(grid: GridContainer, text: String, ctl: Control) -> void:
	var l := UITheme.label(text, 21)
	l.custom_minimum_size = Vector2(300, 0)
	grid.add_child(l)
	grid.add_child(ctl)


func _slider_row(grid: GridContainer, text: String, lo: float, hi: float, step: float, val: float, fmt: String, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var s := UITheme.slider(lo, hi, step, val)
	s.custom_minimum_size = Vector2(380, 28)
	var v := UITheme.label(fmt % val, 20, UITheme.ACCENT)
	v.custom_minimum_size = Vector2(80, 0)
	s.value_changed.connect(func(x: float):
		v.text = fmt % x
		cb.call(x))
	hb.add_child(s)
	hb.add_child(v)
	_row(grid, text, hb)


func _section(g: GridContainer, text: String) -> void:
	var l := UITheme.label(text.to_upper(), 18, UITheme.ACCENT)
	l.add_theme_font_override("font", UITheme.font(true))
	g.add_child(l)
	g.add_child(Control.new())


func _check_row(g: GridContainer, text: String, value: bool, cb: Callable, tip: String = "") -> void:
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_ALL
	c.tooltip_text = tip
	c.toggled.connect(cb)
	_row(g, text, c)


func _option_row(g: GridContainer, text: String, names: Array, selected: int, cb: Callable, tip: String = "") -> OptionButton:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(380, 40)
	for n in names:
		ob.add_item(n)
	ob.select(clampi(selected, 0, names.size() - 1))
	ob.tooltip_text = tip
	ob.item_selected.connect(cb)
	_row(g, text, ob)
	return ob


## Int option where -1 means "follow the graphics preset".
func _preset_opt(g: GridContainer, text: String, key: String, names: Array) -> void:
	var all := ["Preset default"]
	all.append_array(names)
	_option_row(g, text, all, int(Settings.opt[key]) + 1, func(i: int):
		Settings.opt[key] = i - 1
		_graphics_changed())


func _graphics_changed() -> void:
	Settings.apply_to_viewport(get_viewport())
	Settings.settings_changed.emit()
	_say("Graphics changes apply fully when the next screen loads.")


func _opt_check(g: GridContainer, text: String, key: String, tip: String = "") -> void:
	_check_row(g, text, Settings.opt[key], func(on: bool): Settings.opt[key] = on, tip)


func _opt_slider(g: GridContainer, text: String, key: String, step: float, fmt: String, cb: Callable = Callable()) -> void:
	var o: Array = Settings.OPTS[key]
	_slider_row(g, text, float(o[1]), float(o[2]), step, float(Settings.opt[key]), fmt, func(x: float):
		Settings.opt[key] = type_convert(x, typeof(o[0]))
		if cb.is_valid():
			cb.call(x))


func _build_display_tab() -> Control:
	var r := _scroll_grid("Display", 2)
	var g: GridContainer = r[1]
	_section(g, "Window")
	_option_row(g, "Window mode", Settings.WINDOW_MODE_NAMES, int(Settings.opt["window_mode"]), func(i: int):
		Settings.opt["window_mode"] = i
		Settings.fullscreen = i > 0
		Settings.apply_display(), "F11 toggles windowed / fullscreen at any time.")
	var vs := CheckButton.new()
	vs.button_pressed = Settings.vsync
	vs.toggled.connect(func(on: bool):
		Settings.vsync = on
		Settings.apply_display())
	_row(g, "V-Sync", vs)
	var caps := [0, 30, 60, 120, 144, 165, 240]
	var cap_names := ["Unlimited", "30", "60", "120", "144", "165", "240"]
	_option_row(g, "Frame rate limit", cap_names, maxi(caps.find(int(Settings.opt["fps_cap"])), 0), func(i: int):
		Settings.opt["fps_cap"] = caps[i]
		Engine.max_fps = caps[i])
	_section(g, "Picture")
	_opt_slider(g, "Brightness", "brightness", 0.05, "%.2f", func(_x: float):
		for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			Settings.apply_env((we as WorldEnvironment).environment))
	_slider_row(g, "Field of view (flight)", 60, 110, 1, Settings.fov, "%d°", func(x: float): Settings.fov = x)
	_opt_slider(g, "Field of view (garage)", "garage_fov", 1.0, "%d°")
	var hud := CheckButton.new()
	hud.button_pressed = Settings.hud_on
	hud.toggled.connect(func(on: bool): Settings.hud_on = on)
	_row(g, "Flight HUD enabled", hud)
	return r[0]


func _build_graphics_tab() -> Control:
	var r := _scroll_grid("Graphics", 2)
	var g: GridContainer = r[1]
	_section(g, "Quality")
	_option_row(g, "Graphics preset", Settings.PRESET_NAMES, Settings.graphics_preset, func(i: int):
		Settings.graphics_preset = i
		_graphics_changed())
	_check_row(g, "Safe graphics (compatibility)", Settings.opt["safe_graphics"], func(on: bool):
		Settings.opt["safe_graphics"] = on
		_graphics_changed(), "No shadows, glow or fog and fewer lights. Try this if the game crashes, flickers or runs slowly.")
	_slider_row(g, "Render scale", 0.0, 1.0, 0.05, float(Settings.opt["render_scale"]), "%.2f", func(x: float):
		Settings.opt["render_scale"] = x if x >= 0.5 else 0.0
		Settings.apply_to_viewport(get_viewport()))
	_row(g, "", UITheme.label("Render scale 0 = preset.  0.5 - 1.0 = 3D resolution.", 16, UITheme.MUTED))
	_section(g, "Detail (overrides the preset)")
	_preset_opt(g, "Shadows", "shadows", ["Off", "On"])
	_preset_opt(g, "Shadow quality", "shadow_quality", ["Low", "Medium", "High"])
	_preset_opt(g, "Anti-aliasing (MSAA)", "msaa", ["Off", "2x", "4x"])
	_preset_opt(g, "View distance", "view_dist", ["Short", "Medium", "Far"])
	_preset_opt(g, "Tree density", "trees", ["Low", "Medium", "High"])
	_preset_opt(g, "Glow / bloom", "glow", ["Off", "On"])
	_opt_check(g, "Fog and haze", "fog")
	_opt_slider(g, "Particle amount", "particles", 0.05, "%.2f")
	return r[0]


func _build_audio_tab() -> Control:
	var r := _scroll_grid("Audio", 2)
	var g: GridContainer = r[1]
	_section(g, "Volume")
	_slider_row(g, "Master volume", 0, 1, 0.01, Settings.master_vol, "%.2f", func(x: float):
		Settings.master_vol = x
		Settings.apply_audio())
	_slider_row(g, "Music volume", 0, 1, 0.01, Settings.music_vol, "%.2f", func(x: float):
		Settings.music_vol = x
		Settings.apply_audio())
	_slider_row(g, "Effects volume", 0, 1, 0.01, Settings.sfx_vol, "%.2f", func(x: float):
		Settings.sfx_vol = x
		Settings.apply_audio()
		Audio.play("beep"))
	_opt_slider(g, "Vehicles & ambience volume", "ambience_vol", 0.01, "%.2f", func(_x: float): Settings.apply_audio())
	_opt_check(g, "Mute when the window is in the background", "mute_unfocused")
	return r[0]


func _build_gameplay_tab() -> Control:
	var r := _scroll_grid("Gameplay", 2)
	var g: GridContainer = r[1]
	_section(g, "Career")
	_option_row(g, "Difficulty", ["Relaxed - +35 % pay, gentler crashes", "Standard", "Hardcore - -20 % pay, harsher crashes"], int(Settings.opt["difficulty"]), func(i: int): Settings.opt["difficulty"] = i)
	_opt_slider(g, "Autosave every (seconds)", "autosave", 5.0, "%d s")
	_section(g, "Tutorial")
	_opt_check(g, "Tutorial hints (step card, bench guide, flight school)", "tutorial_hints")
	_opt_check(g, "Floating step arrows in the garage", "beacons")
	_row(g, "Replay the intro guide", UITheme.button("Show HOW TO PLAY next time", func():
		Career.data["flags"].erase("seen_intro")
		_say("The guide will open the next time you enter the garage."), Vector2(380, 42)))
	_section(g, "Display units & comfort")
	_option_row(g, "Units", ["Metric (km/h, m)", "Imperial (mph, ft)"], int(Settings.opt["units"]), func(i: int): Settings.opt["units"] = i)
	_opt_check(g, "Head bob while walking", "head_bob")
	_opt_slider(g, "FPV camera shake", "cam_shake", 0.05, "%.2f")
	_opt_check(g, "Show day / time in the garage", "show_clock")
	_section(g, "Testing")
	var ua := UITheme.button("Unlock all parts in the market", func():
		SaveData.unlock_all()
		_say("All parts unlocked."), Vector2(380, 42))
	_row(g, "Parts", ua)
	var cr := UITheme.button("+5000 credits", func():
		Career.earn(5000, "Testing grant")
		_say("+5000 credits."), Vector2(380, 42))
	_row(g, "Credits", cr)
	return r[0]


func _build_flight_tab() -> Control:
	var r := _scroll_grid("Flight & Pad", 2)
	var g: GridContainer = r[1]
	_section(g, "Flight")
	_option_row(g, "Default flight mode", ["Beginner (self-level + altitude hold)", "Intermediate (self-level)", "Acro (rate mode)"], Settings.assist, func(i: int): Settings.assist = i)
	var ms := CheckButton.new()
	ms.button_pressed = Settings.mouse_stick
	ms.toggled.connect(func(on: bool): Settings.mouse_stick = on)
	_row(g, "Mouse as sticks", ms)
	_slider_row(g, "Mouse stick sensitivity", 0.2, 3.0, 0.05, Settings.mouse_sens, "%.2f", func(x: float): Settings.mouse_sens = x)
	_opt_check(g, "Invert pitch", "invert_pitch")
	_section(g, "Gamepad")
	_check_row(g, "Throttle = stick position (centre 50 %)", Settings.pad_throttle_abs, func(on: bool): Settings.pad_throttle_abs = on)
	_opt_slider(g, "Stick dead zone", "deadzone", 0.01, "%.2f", func(_x: float): Settings.rebuild_input_map())
	_opt_slider(g, "Stick expo (softer centre)", "expo", 0.05, "%.2f")
	_check_row(g, "Controller vibration", Settings.rumble, func(on: bool): Settings.rumble = on)
	_option_row(g, "Button names", ["PlayStation (Cross / Circle / Square / Triangle)", "Xbox (A / B / X / Y)"], Settings.pad_glyphs, func(i: int):
		Settings.pad_glyphs = i
		_refresh_binds())
	_section(g, "Walking")
	_slider_row(g, "Look sensitivity", 0.2, 3.0, 0.05, Settings.look_sens, "%.2f", func(x: float): Settings.look_sens = x)
	_check_row(g, "Invert look Y", Settings.invert_y, func(on: bool): Settings.invert_y = on)
	_opt_check(g, "Crouch is a toggle (off = hold)", "crouch_toggle")
	_opt_check(g, "Sprint is a toggle (off = hold)", "sprint_toggle")
	return r[0]


func _build_osd_tab() -> Control:
	var r := _scroll_grid("OSD", 2)
	var g: GridContainer = r[1]
	_section(g, "Flight on-screen display")
	var names := {"speed": "Speed", "altitude": "Altitude", "battery": "Battery voltage & bar", "amps": "Motor / total current", "mission": "Mission & objectives", "crosshair": "Crosshair", "compass": "Compass & objective bearing", "markers": "Target brackets, arrows & drop reticle"}
	for k in Settings.osd:
		var key: String = k
		_check_row(g, names.get(key, key.capitalize()), Settings.osd[key], func(on: bool): Settings.osd[key] = on)
	return r[0]


func _build_controls_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "Controls"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_right", 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(vb)

	var hdr := HBoxContainer.new()
	hdr.add_child(UITheme.label("Click a binding, then press a key / mouse button / gamepad input.  Esc cancels.", 18, UITheme.MUTED))
	vb.add_child(hdr)
	vb.add_child(UITheme.button("Reset all bindings to default", func():
		Settings.reset_bindings_to_default()
		_refresh_binds()
		_say("Bindings reset."), Vector2(320, 40)))
	var group := ""
	for a in Settings.action_table():
		if a["group"] != group:
			group = a["group"]
			var gl := UITheme.label(group.to_upper(), 20, UITheme.ACCENT)
			gl.add_theme_constant_override("line_spacing", 8)
			vb.add_child(gl)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var l := UITheme.label(a["label"], 20)
		l.custom_minimum_size = Vector2(340, 0)
		hb.add_child(l)
		for slot in ["kb", "pad"]:
			var b := UITheme.button("", func(): _begin_capture(a["id"], slot), Vector2(250, 40))
			_bind_buttons["%s|%s" % [a["id"], slot]] = b
			hb.add_child(b)
		hb.add_child(UITheme.button("Default", func():
			Settings.set_binding(a["id"], "kb", Settings.default_binding(a["id"], "kb"))
			Settings.set_binding(a["id"], "pad", Settings.default_binding(a["id"], "pad"))
			_refresh_binds(), Vector2(100, 40)))
		hb.add_child(UITheme.button("Clear", func():
			Settings.set_binding(a["id"], "kb", "")
			Settings.set_binding(a["id"], "pad", "")
			_refresh_binds(), Vector2(80, 40)))
		vb.add_child(hb)
	_refresh_binds()
	return sc


func _refresh_binds() -> void:
	for key in _bind_buttons:
		var parts: PackedStringArray = key.split("|")
		var b: Button = _bind_buttons[key]
		b.text = Settings.binding_text(Settings.bindings[parts[0]][parts[1]])
		b.tooltip_text = "Keyboard / mouse" if parts[1] == "kb" else "Gamepad"
		b.add_theme_color_override("font_color", UITheme.TEXT if parts[1] == "kb" else Color(0.6, 0.85, 1.0))


func _say(t: String) -> void:
	_toast.text = t


func _begin_capture(action: String, slot: String) -> void:
	_cap_action = action
	_cap_slot = slot
	Settings.capturing = true
	var what := "key / mouse button" if slot == "kb" else "gamepad button / stick direction"
	_cap_label.text = "Press a %s for  “%s”\n\n(Esc to cancel)" % [what, _label_of(action)]
	_cap_label.visible = true


func _label_of(action: String) -> String:
	for a in Settings.action_table():
		if a["id"] == action:
			return a["label"]
	return action


func _end_capture() -> void:
	_cap_action = ""
	Settings.capturing = false
	_cap_label.visible = false
	_refresh_binds()


func _input(event: InputEvent) -> void:
	if _cap_action == "":
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_end_capture()
		get_viewport().set_input_as_handled()
		return
	var b := Settings.event_to_binding(event, _cap_slot)
	if b != "":
		Settings.set_binding(_cap_action, _cap_slot, b)
		_say("%s → %s" % [_label_of(_cap_action), Settings.binding_text(b)])
		_end_capture()
		get_viewport().set_input_as_handled()
		Audio.play("snap")
	elif event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _cap_action == "" and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
