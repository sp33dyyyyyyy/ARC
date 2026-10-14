extends Node
## Global user settings: graphics, audio, controls and key bindings.
## Persisted to user://settings.cfg. Missing/corrupt files fall back to defaults.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"

const PRESET_NAMES := ["Low", "Medium", "High"]
## terrain_step must divide the 150 m chunk size (10, 6, 5, 3, ...)
const PRESETS := [
	{"shadows": false, "shadow_size": 1024, "shadow_dist": 80.0, "msaa": 0, "scale3d": 0.85, "trees": 110, "view": 380.0, "glow": false, "ssao": false, "terrain_step": 10.0},
	{"shadows": true, "shadow_size": 1024, "shadow_dist": 110.0, "msaa": 0, "scale3d": 1.0, "trees": 240, "view": 520.0, "glow": false, "ssao": false, "terrain_step": 6.0},
	{"shadows": true, "shadow_size": 2048, "shadow_dist": 180.0, "msaa": 1, "scale3d": 1.0, "trees": 420, "view": 800.0, "glow": true, "ssao": false, "terrain_step": 5.0},
]

# --- values -----------------------------------------------------------------
var graphics_preset: int = 1
var fov: float = 90.0
var mouse_sens: float = 1.0
var hud_on: bool = true
var mouse_stick: bool = false
var fullscreen: bool = false
var vsync: bool = true
var master_vol: float = 0.8
var music_vol: float = 0.5
var sfx_vol: float = 0.8

## action id -> {"kb": "key:87", "pad": "joyaxis:1:-1"}   ("" = unbound)
var bindings: Dictionary = {}

var show_stats: bool = false          # F3 performance overlay
var capturing: bool = false  # true while the options menu is waiting for a key press


# --- action table -----------------------------------------------------------
## Ordered list of every rebindable action. kb / pad are default bindings.
func action_table() -> Array:
	return [
		{"id": "throttle_up", "label": "Throttle up", "group": "Flight", "kb": "key:%d" % KEY_W, "pad": "joyaxis:1:-1"},
		{"id": "throttle_down", "label": "Throttle down", "group": "Flight", "kb": "key:%d" % KEY_S, "pad": "joyaxis:1:1"},
		{"id": "yaw_left", "label": "Yaw left", "group": "Flight", "kb": "key:%d" % KEY_A, "pad": "joyaxis:0:-1"},
		{"id": "yaw_right", "label": "Yaw right", "group": "Flight", "kb": "key:%d" % KEY_D, "pad": "joyaxis:0:1"},
		{"id": "pitch_forward", "label": "Pitch forward", "group": "Flight", "kb": "key:%d" % KEY_UP, "pad": "joyaxis:3:-1"},
		{"id": "pitch_back", "label": "Pitch back", "group": "Flight", "kb": "key:%d" % KEY_DOWN, "pad": "joyaxis:3:1"},
		{"id": "roll_left", "label": "Roll left", "group": "Flight", "kb": "key:%d" % KEY_LEFT, "pad": "joyaxis:2:-1"},
		{"id": "roll_right", "label": "Roll right", "group": "Flight", "kb": "key:%d" % KEY_RIGHT, "pad": "joyaxis:2:1"},
		{"id": "arm", "label": "Arm / disarm", "group": "Flight", "kb": "key:%d" % KEY_SPACE, "pad": "joybtn:%d" % JOY_BUTTON_A},
		{"id": "kb_precision", "label": "Fine stick (hold)", "group": "Flight", "kb": "key:%d" % KEY_SHIFT, "pad": ""},
		{"id": "flight_mode", "label": "Toggle angle / acro mode", "group": "Flight", "kb": "key:%d" % KEY_V, "pad": "joybtn:%d" % JOY_BUTTON_X},
		{"id": "mouse_stick", "label": "Toggle mouse stick mode", "group": "Flight", "kb": "key:%d" % KEY_M, "pad": ""},
		{"id": "toggle_hud", "label": "Toggle HUD", "group": "Flight", "kb": "key:%d" % KEY_H, "pad": "joybtn:%d" % JOY_BUTTON_Y},
		{"id": "restart", "label": "Restart mission", "group": "Flight", "kb": "key:%d" % KEY_F5, "pad": "joybtn:%d" % JOY_BUTTON_BACK},
		{"id": "pause", "label": "Pause / back", "group": "General", "kb": "key:%d" % KEY_ESCAPE, "pad": "joybtn:%d" % JOY_BUTTON_START},
		{"id": "fullscreen", "label": "Toggle fullscreen", "group": "General", "kb": "key:%d" % KEY_F11, "pad": ""},
		{"id": "debug_stats", "label": "Show FPS / performance overlay", "group": "General", "kb": "key:%d" % KEY_F3, "pad": ""},
		{"id": "interact", "label": "Grab / place / select", "group": "Workshop", "kb": "mouse:%d" % MOUSE_BUTTON_LEFT, "pad": ""},
		{"id": "build_rotate", "label": "Rotate held part", "group": "Workshop", "kb": "key:%d" % KEY_R, "pad": ""},
		{"id": "cam_orbit", "label": "Orbit camera (hold)", "group": "Workshop", "kb": "mouse:%d" % MOUSE_BUTTON_RIGHT, "pad": ""},
		{"id": "cam_zoom_in", "label": "Zoom in", "group": "Workshop", "kb": "mouse:%d" % MOUSE_BUTTON_WHEEL_UP, "pad": ""},
		{"id": "cam_zoom_out", "label": "Zoom out", "group": "Workshop", "kb": "mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN, "pad": ""},
		{"id": "motor_test_1", "label": "Motor test M1 (hold)", "group": "Setup", "kb": "key:%d" % KEY_1, "pad": ""},
		{"id": "motor_test_2", "label": "Motor test M2 (hold)", "group": "Setup", "kb": "key:%d" % KEY_2, "pad": ""},
		{"id": "motor_test_3", "label": "Motor test M3 (hold)", "group": "Setup", "kb": "key:%d" % KEY_3, "pad": ""},
		{"id": "motor_test_4", "label": "Motor test M4 (hold)", "group": "Setup", "kb": "key:%d" % KEY_4, "pad": ""},
	]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_bindings()
	var had_file := FileAccess.file_exists(SETTINGS_PATH)
	load_settings()
	if not had_file:
		graphics_preset = _detect_preset()
		save_settings()
	rebuild_input_map()
	apply_all()
	_make_stats_overlay()


func _input(event: InputEvent) -> void:
	if capturing:
		return
	if event.is_action_pressed("debug_stats"):
		show_stats = not show_stats
		_stats_layer.visible = show_stats
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("fullscreen"):
		fullscreen = not fullscreen
		apply_display()
		save_settings()
		settings_changed.emit()
		get_viewport().set_input_as_handled()


# --- quality ----------------------------------------------------------------
func quality() -> Dictionary:
	return PRESETS[clampi(graphics_preset, 0, PRESETS.size() - 1)]


## Applies the graphics preset to a viewport (MSAA and 3D render scale).
func apply_to_viewport(vp: Viewport) -> void:
	var q := quality()
	var msaa: int = q["msaa"]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa]
	var s: float = q["scale3d"]
	# The Compatibility (OpenGL) renderer only supports bilinear 3D scaling.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


# --- bindings ---------------------------------------------------------------
func _reset_bindings() -> void:
	bindings.clear()
	for a in action_table():
		bindings[a["id"]] = {"kb": a["kb"], "pad": a["pad"]}


func reset_bindings_to_default() -> void:
	_reset_bindings()
	rebuild_input_map()
	save_settings()
	settings_changed.emit()


func default_binding(action: String, slot: String) -> String:
	for a in action_table():
		if a["id"] == action:
			return a[slot]
	return ""


## Converts a stored binding string into an InputEvent (null when unbound/invalid).
func binding_to_event(s: String) -> InputEvent:
	var parts := s.split(":")
	if parts.size() < 2:
		return null
	match parts[0]:
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(parts[1]) as Key
			return ev
		"mouse":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(parts[1]) as MouseButton
			return ev
		"joybtn":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(parts[1]) as JoyButton
			return ev
		"joyaxis":
			if parts.size() < 3:
				return null
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(parts[1]) as JoyAxis
			ev.axis_value = 1.0 if int(parts[2]) > 0 else -1.0
			return ev
	return null


## Converts a captured InputEvent to a binding string ("" if not bindable for the slot).
func event_to_binding(ev: InputEvent, slot: String) -> String:
	if slot == "kb":
		if ev is InputEventKey and ev.pressed and not ev.echo:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return "key:%d" % code
		if ev is InputEventMouseButton and ev.pressed:
			return "mouse:%d" % ev.button_index
	else:
		if ev is InputEventJoypadButton and ev.pressed:
			return "joybtn:%d" % ev.button_index
		if ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.6:
			return "joyaxis:%d:%d" % [ev.axis, 1 if ev.axis_value > 0 else -1]
	return ""


const AXIS_NAMES := ["Left stick X", "Left stick Y", "Right stick X", "Right stick Y", "Left trigger", "Right trigger"]


func binding_text(s: String) -> String:
	if s == "":
		return "—"
	var parts := s.split(":")
	match parts[0]:
		"key":
			var code := int(parts[1])
			var txt := OS.get_keycode_string(code as Key)
			return txt if txt != "" else "Key %d" % code
		"mouse":
			match int(parts[1]):
				MOUSE_BUTTON_LEFT: return "Mouse Left"
				MOUSE_BUTTON_RIGHT: return "Mouse Right"
				MOUSE_BUTTON_MIDDLE: return "Mouse Middle"
				MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
				MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
				_: return "Mouse %s" % parts[1]
		"joybtn":
			var names := ["A", "B", "X", "Y", "Back", "Guide", "Start", "L-Stick", "R-Stick", "LB", "RB", "D-Up", "D-Down", "D-Left", "D-Right"]
			var i := int(parts[1])
			return "Pad " + (names[i] if i < names.size() else str(i))
		"joyaxis":
			var ax := int(parts[1])
			var nm: String = AXIS_NAMES[ax] if ax < AXIS_NAMES.size() else "Axis %d" % ax
			return "%s %s" % [nm, "+" if int(parts[2]) > 0 else "−"]
	return s


## Sets a binding. Any other action using the same input in the same slot is unbound.
func set_binding(action: String, slot: String, value: String) -> void:
	if value != "":
		for id in bindings:
			if id != action and bindings[id][slot] == value:
				bindings[id][slot] = ""
	bindings[action][slot] = value
	rebuild_input_map()
	save_settings()
	settings_changed.emit()


func rebuild_input_map() -> void:
	for a in action_table():
		var id: String = a["id"]
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, 0.2)
		var b: Dictionary = bindings.get(id, {"kb": a["kb"], "pad": a["pad"]})
		for slot in ["kb", "pad"]:
			var ev := binding_to_event(str(b.get(slot, "")))
			if ev != null:
				InputMap.action_add_event(id, ev)


# --- persistence ------------------------------------------------------------
func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return  # missing or corrupt -> keep defaults
	graphics_preset = clampi(_geti(cfg, "display", "graphics_preset", graphics_preset), 0, 2)
	fov = clampf(_getf(cfg, "display", "fov", fov), 60.0, 110.0)
	fullscreen = _getb(cfg, "display", "fullscreen", fullscreen)
	vsync = _getb(cfg, "display", "vsync", vsync)
	mouse_sens = clampf(_getf(cfg, "controls", "mouse_sens", mouse_sens), 0.2, 3.0)
	hud_on = _getb(cfg, "controls", "hud_on", hud_on)
	mouse_stick = _getb(cfg, "controls", "mouse_stick", mouse_stick)
	master_vol = clampf(_getf(cfg, "audio", "master", master_vol), 0.0, 1.0)
	music_vol = clampf(_getf(cfg, "audio", "music", music_vol), 0.0, 1.0)
	sfx_vol = clampf(_getf(cfg, "audio", "sfx", sfx_vol), 0.0, 1.0)
	for a in action_table():
		var id: String = a["id"]
		for slot in ["kb", "pad"]:
			var key := "%s_%s" % [id, slot]
			if cfg.has_section_key("keys", key):
				var v = cfg.get_value("keys", key, a[slot])
				if v is String and (v == "" or binding_to_event(v) != null):
					bindings[id][slot] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "graphics_preset", graphics_preset)
	cfg.set_value("display", "fov", fov)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("controls", "mouse_sens", mouse_sens)
	cfg.set_value("controls", "hud_on", hud_on)
	cfg.set_value("controls", "mouse_stick", mouse_stick)
	cfg.set_value("audio", "master", master_vol)
	cfg.set_value("audio", "music", music_vol)
	cfg.set_value("audio", "sfx", sfx_vol)
	for id in bindings:
		for slot in ["kb", "pad"]:
			cfg.set_value("keys", "%s_%s" % [id, slot], bindings[id][slot])
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


func _getf(cfg: ConfigFile, sec: String, key: String, def: float) -> float:
	var v = cfg.get_value(sec, key, def)
	return float(v) if (v is float or v is int) else def


func _geti(cfg: ConfigFile, sec: String, key: String, def: int) -> int:
	var v = cfg.get_value(sec, key, def)
	return int(v) if (v is float or v is int) else def


func _getb(cfg: ConfigFile, sec: String, key: String, def: bool) -> bool:
	var v = cfg.get_value(sec, key, def)
	return bool(v) if v is bool else def


# --- applying ---------------------------------------------------------------
func apply_all() -> void:
	apply_display()
	apply_audio()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var screen := DisplayServer.screen_get_size()
		var want := Vector2i(1920, 1080)
		if screen.x < want.x or screen.y < want.y:
			want = Vector2i(int(screen.x * 0.9), int(screen.y * 0.9))
		DisplayServer.window_set_size(want)
		DisplayServer.window_set_position((screen - want) / 2)


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func apply_audio() -> void:
	_set_bus_linear(0, master_vol)
	_set_bus_linear(_ensure_bus("Music"), music_vol)
	_set_bus_linear(_ensure_bus("SFX"), sfx_vol)


func _set_bus_linear(idx: int, v: float) -> void:
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


# --- first-run GPU detection & performance overlay -----------------------------
func _detect_preset() -> int:
	var name := RenderingServer.get_video_adapter_name().to_lower()
	var slow := ["intel", "uhd", "iris", "llvmpipe", "software", "basic render", "microsoft", "vega", "radeon(tm) graphics", "radeon graphics", "mesa"]
	for k in slow:
		if name.contains(k):
			return 0
	if name.contains("geforce") or name.contains("rtx") or name.contains("gtx") or name.contains("radeon rx") or name.contains("rx "):
		return 1
	return 0


var _stats_layer: CanvasLayer
var _stats_label: Label


func _make_stats_overlay() -> void:
	_stats_layer = CanvasLayer.new()
	_stats_layer.layer = 100
	_stats_layer.visible = false
	add_child(_stats_layer)
	_stats_label = Label.new()
	_stats_label.position = Vector2(8, 4)
	_stats_label.add_theme_font_size_override("font_size", 18)
	_stats_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	_stats_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats_label.add_theme_constant_override("outline_size", 6)
	_stats_layer.add_child(_stats_label)


func _process(_dt: float) -> void:
	if not show_stats:
		return
	_stats_label.text = "%d FPS  (%.1f ms)   draws %d   tris %dk   preset %s\n%s" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		PRESET_NAMES[graphics_preset], RenderingServer.get_video_adapter_name()]
