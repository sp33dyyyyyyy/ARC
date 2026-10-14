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
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	panel.custom_minimum_size = Vector2(1180, 820)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(UITheme.label("OPTIONS", 34, UITheme.ACCENT))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	tabs.add_child(_build_game_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_controls_tab())

	_toast = UITheme.label("", 18, UITheme.MUTED)
	vb.add_child(_toast)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(foot)
	foot.add_child(UITheme.accent_button("Close", _close, Vector2(180, 46)))

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


func _build_game_tab() -> Control:
	var r := _scroll_grid("Game", 2)
	var g: GridContainer = r[1]
	var ob := OptionButton.new()
	for n in Settings.PRESET_NAMES:
		ob.add_item(n)
	ob.select(Settings.graphics_preset)
	ob.item_selected.connect(func(i: int):
		Settings.graphics_preset = i
		Settings.settings_changed.emit())
	_row(g, "Graphics preset", ob)
	_slider_row(g, "Field of view", 60, 110, 1, Settings.fov, "%d°", func(x: float): Settings.fov = x)
	_slider_row(g, "Mouse sensitivity", 0.2, 3.0, 0.05, Settings.mouse_sens, "%.2f", func(x: float): Settings.mouse_sens = x)
	var hud := CheckButton.new()
	hud.button_pressed = Settings.hud_on
	hud.toggled.connect(func(on: bool): Settings.hud_on = on)
	_row(g, "HUD enabled", hud)
	var ms := CheckButton.new()
	ms.button_pressed = Settings.mouse_stick
	ms.toggled.connect(func(on: bool): Settings.mouse_stick = on)
	_row(g, "Mouse as sticks (fly)", ms)
	var fs := CheckButton.new()
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on: bool):
		Settings.fullscreen = on
		Settings.apply_display())
	_row(g, "Fullscreen (F11)", fs)
	var vs := CheckButton.new()
	vs.button_pressed = Settings.vsync
	vs.toggled.connect(func(on: bool):
		Settings.vsync = on
		Settings.apply_display())
	_row(g, "V-Sync", vs)
	var ua := UITheme.button("Unlock all parts (testing)", func():
		SaveData.unlock_all()
		_say("All parts unlocked."), Vector2(300, 44))
	_row(g, "Progress", ua)
	return r[0]


func _build_audio_tab() -> Control:
	var r := _scroll_grid("Audio", 2)
	var g: GridContainer = r[1]
	_slider_row(g, "Master volume", 0, 1, 0.01, Settings.master_vol, "%.2f", func(x: float):
		Settings.master_vol = x
		Settings.apply_audio())
	_slider_row(g, "Music volume", 0, 1, 0.01, Settings.music_vol, "%.2f", func(x: float):
		Settings.music_vol = x
		Settings.apply_audio())
	_slider_row(g, "SFX volume", 0, 1, 0.01, Settings.sfx_vol, "%.2f", func(x: float):
		Settings.sfx_vol = x
		Settings.apply_audio()
		Audio.play("beep"))
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
