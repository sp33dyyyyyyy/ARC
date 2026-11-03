class_name MainMenu
extends Node
## Title screen: a slowly orbiting showcase drone over a grid floor, the main menu,
## a career card, the next step and a controls strip.

const VERSION := "v0.3"

var _drone: Node3D
var _cam: Camera3D
var _status: Label
var _t := 0.0
var _ui: Control


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.1, 0.1, 0.18)
	psm.sky_horizon_color = Color(0.95, 0.5, 0.3)
	psm.ground_horizon_color = Color(0.5, 0.28, 0.2)
	psm.ground_bottom_color = Color(0.06, 0.05, 0.07)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.012
	env.fog_light_color = Color(0.55, 0.3, 0.22)
	Settings.apply_env(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -35, 0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.shadow_enabled = Settings.quality()["shadows"]
	add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(16, 8, -10)
	rim.light_color = Color(0.4, 0.8, 0.9)
	rim.light_energy = 2.0
	rim.omni_range = 40.0
	add_child(rim)
	# floor: dark tiles with an amber grid
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	floor_mi.mesh = pm
	floor_mi.material_override = _grid_material()
	floor_mi.position = Vector3(7, -6.5, 0)
	add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 38
	add_child(_cam)
	Settings.apply_to_viewport(get_viewport())

	var placed: Dictionary = Game.placed if Game.placed.has("frame") and Game.stats()["complete"] else DroneVisual.default_placement()
	if not Career.roster().is_empty():
		var d: Dictionary = Career.active_drone() if not Career.active_drone().is_empty() else Career.roster()[0]
		placed = d["placed"]
	_drone = DroneVisual.assemble(placed, {}, {}, Career.paint_of(Career.active_drone()) if not Career.active_drone().is_empty() else Color(0, 0, 0, 0))
	_drone.position = Vector3(8, 0, 0)
	_drone.scale = Vector3.ONE * 0.62
	_drone.rotation_degrees = Vector3(14, 0, 0)
	add_child(_drone)

	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = UITheme.root_control()
	layer.add_child(_ui)
	_ui.add_child(_vignette())

	# --- left: title + menu ---------------------------------------------------------
	var panel := PanelContainer.new()
	panel.position = Vector2(90, 90)
	panel.custom_minimum_size = Vector2(560, 0)
	var pst := UITheme.flat(Color(0.04, 0.045, 0.055, 0.82), 12, Color(1, 1, 1, 0.08), 1, 34)
	pst.border_width_left = 6
	pst.border_color = UITheme.ACCENT
	panel.add_theme_stylebox_override("panel", pst)
	_ui.add_child(panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	panel.add_child(left)
	left.add_child(UITheme.label("KALVARIAN VOLUNTEER WORKSHOPS", 16, UITheme.ACCENT2))
	left.add_child(UITheme.title("FRONTLINE FPV", 76))
	var sub := UITheme.title("G A R A G E   W A R F A R E", 30, UITheme.ACCENT)
	left.add_child(sub)
	left.add_child(UITheme.label("Build.  Test.  Maintain.  Deploy.", 21, UITheme.MUTED))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	left.add_child(sp)

	var started: bool = FileAccess.file_exists(Career.PATH) or not Career.roster().is_empty()
	var cont := _menu_button("▶   " + ("CONTINUE CAREER" if started else "START CAREER"), true, func():
		if not started:
			Career.new_career()
		Game.goto("garage", {"spawn": "door"}))
	left.add_child(cont)
	var newc := _menu_button("✚   NEW CAREER", false, Callable())
	newc.pressed.connect(func():
		if started and not newc.text.ends_with("?"):
			newc.text = "✚   REALLY START OVER?"
			return
		Career.new_career()
		Game.goto("garage", {"spawn": "door"}))
	left.add_child(newc)
	left.add_child(_menu_button("?   HOW TO PLAY", false, _open_help))
	left.add_child(_menu_button("⚙   WORKBENCH  (current build)", false, func(): Game.goto("workshop", {"stage": "build"})))
	left.add_child(_menu_button("☰   OPTIONS", false, _open_options))
	left.add_child(_menu_button("✕   QUIT", false, func(): get_tree().quit()))
	Pad.focus_first(left, true)

	# --- right: career card + next step ------------------------------------------------
	var rp := PanelContainer.new()
	rp.position = Vector2(1300, 90)
	rp.custom_minimum_size = Vector2(530, 0)
	_ui.add_child(rp)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	rp.add_child(pv)
	pv.add_child(UITheme.header("Workshop log", 22))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	pv.add_child(chips)
	for c in [["%d cr" % Career.credits(), UITheme.ACCENT], ["Rep %d" % int(Career.data["rep"]), UITheme.ACCENT2], ["Lv %d" % Career.level(), Color(0.75, 0.6, 1.0)], ["Day %d" % int(Career.data["day"]), UITheme.MUTED]]:
		chips.add_child(_chip(c[0], c[1]))
	pv.add_child(UITheme.label(Career.level_info()["name"], 20))
	pv.add_child(UITheme.label("Drones on the roster   %d" % Career.roster().size(), 19, UITheme.MUTED))
	pv.add_child(UITheme.label("Missions completed   %d" % Career.data["missions_done"].size(), 19, UITheme.MUTED))
	for m in ["gate_race", "battery_challenge"]:
		var bt := SaveData.best_time(m)
		pv.add_child(UITheme.label("%s best   %s" % [Parts.MISSION_NAMES[m], "—" if bt <= 0.0 else _fmt(bt)], 18, UITheme.MUTED))
	var g := Career.guide_text()
	if g != "":
		var np := PanelContainer.new()
		np.position = Vector2(1300, 470)
		np.custom_minimum_size = Vector2(530, 0)
		var nst := UITheme.flat(Color(0.04, 0.045, 0.055, 0.86), 10, Color(UITheme.ACCENT, 0.5), 1, 18)
		nst.border_width_left = 6
		np.add_theme_stylebox_override("panel", nst)
		_ui.add_child(np)
		var nv := VBoxContainer.new()
		np.add_child(nv)
		nv.add_child(UITheme.label("NEXT STEP  %d / %d  -  %s" % [int(Career.data["tutorial"]) + 1, Career.GUIDE.size(), Career.guide_title().to_upper()], 17, UITheme.ACCENT))
		var gl := UITheme.label(g, 19)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.custom_minimum_size = Vector2(490, 0)
		nv.add_child(gl)

	# --- bottom strip ---------------------------------------------------------------------------
	var strip := PanelContainer.new()
	strip.position = Vector2(0, 1030)
	strip.custom_minimum_size = Vector2(1920, 50)
	strip.add_theme_stylebox_override("panel", UITheme.flat(Color(0.02, 0.025, 0.03, 0.9), 0, Color(1, 1, 1, 0.06), 1, 12))
	_ui.add_child(strip)
	var sh := HBoxContainer.new()
	strip.add_child(sh)
	_status = UITheme.label(_status_text(), 17, UITheme.MUTED)
	sh.add_child(_status)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sp2)
	sh.add_child(UITheme.label("Keyboard & mouse or DualSense   •   F11 fullscreen   •   %s" % VERSION, 17, UITheme.MUTED))


func _menu_button(text: String, accent: bool, cb: Callable) -> Button:
	var b := UITheme.accent_button(text, cb, Vector2(490, 60)) if accent else UITheme.button(text, cb, Vector2(490, 54))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_font_override("font", UITheme.font(true))
	return b


func _chip(text: String, col: Color) -> Label:
	var l := UITheme.label(" %s " % text, 18, col)
	l.add_theme_stylebox_override("normal", UITheme.flat(Color(col, 0.1), 6, Color(col, 0.5), 1, 8))
	return l


func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.15), Color(0, 0, 0, 0.75)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.55, 0.45)
	gt.fill_to = Vector2(1.15, 1.1)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _grid_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
void fragment() {
	vec2 g = abs(fract(UV * 80.0 - 0.5) - 0.5) / fwidth(UV * 80.0);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float fade = 1.0 - smoothstep(0.05, 0.45, distance(UV, vec2(0.5)));
	ALBEDO = mix(vec3(0.03, 0.03, 0.04), vec3(1.0, 0.6, 0.2), line * 0.55 * fade);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _status_text() -> String:
	var s: Dictionary = Game.stats()
	if not Game.placed.has("frame"):
		return "Workbench: empty"
	if not s["complete"]:
		return "Workbench: build in progress (missing %s)" % s["missing_text"]
	return "Workbench: %s · %s · %.0f g" % [s["frame_name"], s["motor_name"], s["mass_g"]]


func _open_options() -> void:
	_add_overlay(OptionsMenu.new())


func _open_help() -> void:
	_add_overlay(HowToPlay.new())


func _add_overlay(o: Control) -> void:
	var l := CanvasLayer.new()
	l.layer = 50
	add_child(l)
	var r := UITheme.root_control()
	l.add_child(r)
	r.add_child(o)
	o.closed.connect(func():
		l.queue_free()
		Pad.focus_first(_ui, true))
	if o is HowToPlay:
		o.closed.connect(func(): pass)


func _process(dt: float) -> void:
	_t += dt
	if _drone:
		_drone.rotation.y += dt * 0.35
		_drone.position.y = 2.5 + sin(_t * 1.3) * 0.5
	if _cam:
		var a := 0.25 + sin(_t * 0.08) * 0.25
		_cam.position = Vector3(8, 0, 0) + Vector3(sin(a) * 34.0, 10.0 + sin(_t * 0.2) * 1.5, cos(a) * 34.0) + Vector3(-12, 0, 0)
		_cam.look_at(Vector3(4, 2.0, 0))
