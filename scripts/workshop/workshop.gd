class_name Workshop
extends Node
## The workshop: owns the 3D bench, orbit camera and the BUILD / WIRE / SETUP stages.

const STAGES := ["build", "wire", "setup"]

var start_stage: String = "build"
var message: String = ""

var world: Node3D
var camera: Camera3D
var drone_root: Node3D
var ui_root: Control
var build: BuildStage
var wire: WireStage
var setup: SetupStage
var stage: String = ""

var cam_yaw := deg_to_rad(28.0)
var cam_pitch := deg_to_rad(-38.0)
var cam_dist := 42.0
var cam_target := Vector3(0, 2.5, 9.0)   # looks slightly in front of the drone so it sits above the parts tray

var _stage_buttons: Dictionary = {}
var _toast: Label
var _bar: PanelContainer
var _toast_tween: Tween
var _menu: Control = null
var _sun: DirectionalLight3D


func _ready() -> void:
	_build_world()
	_build_ui()
	build = BuildStage.new()
	build.ws = self
	add_child(build)
	wire = WireStage.new()
	wire.ws = self
	add_child(wire)
	setup = SetupStage.new()
	setup.ws = self
	add_child(setup)
	ui_root.move_child(_bar, ui_root.get_child_count() - 1)
	ui_root.move_child(_toast, ui_root.get_child_count() - 1)
	Settings.apply_to_viewport(get_viewport())
	Settings.settings_changed.connect(_apply_quality)
	_apply_quality()
	switch_stage(start_stage, true)
	if message != "":
		say(message, false, 7.0)


# --- world -------------------------------------------------------------------
func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.075, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.66, 0.6)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-58, 28, 0)
	_sun.light_color = Color(1.0, 0.93, 0.82)
	_sun.light_energy = 0.75
	_sun.shadow_enabled = true
	world.add_child(_sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-18, 36, 18)
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 0.45
	lamp.omni_range = 140.0
	world.add_child(lamp)

	var wood := MeshFactory.wood_texture(128, 128)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_texture = wood
	wood_mat.roughness = 0.75
	wood_mat.uv1_scale = Vector3(1.5, 1.0, 1.0)
	MeshFactory.box(world, Vector3(130, 3, 80), Vector3(0, -1.55, 0), wood_mat)
	var wall_mat := wood_mat.duplicate()
	wall_mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	wall_mat.albedo_color = Color(0.8, 0.8, 0.8)
	MeshFactory.box(world, Vector3(130, 60, 2), Vector3(0, 28, -38), wall_mat)
	# cutting mat
	var mat_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(64, 42)
	mat_mesh.mesh = pm
	mat_mesh.material_override = MeshFactory.mat_grid_material(Vector2(64, 42))
	mat_mesh.position = Vector3(0, 0.0, 0)
	world.add_child(mat_mesh)
	# set dressing
	var metal := MeshFactory.mat(Color(0.75, 0.75, 0.8), 0.9, 0.3)
	MeshFactory.cyl(world, 3.2, 3.0, Vector3(30, 1.5, -14), MeshFactory.mat(Color(0.7, 0.15, 0.12), 0.1, 0.5))  # solder spool
	MeshFactory.cyl(world, 1.0, 3.2, Vector3(30, 1.5, -14), metal)
	MeshFactory.cyl(world, 0.25, 22.0, Vector3(36, 1.2, 10), MeshFactory.mat(Color(0.15, 0.15, 0.17), 0.3, 0.5), Vector3(0, 0, 90))  # screwdriver shaft
	MeshFactory.cyl(world, 1.2, 8.0, Vector3(44, 1.2, 10), MeshFactory.mat(Color(0.95, 0.5, 0.05), 0.0, 0.5), Vector3(0, 0, 90))
	MeshFactory.box(world, Vector3(10, 2, 7), Vector3(-37, 1, -12), MeshFactory.mat(Color(0.18, 0.18, 0.2), 0.2, 0.6))  # parts bin
	for i in 8:
		MeshFactory.cyl(world, 0.35, 0.6, Vector3(-39.5 + (i % 4) * 1.6, 2.3, -14 + (i / 4) * 2.4), MeshFactory.mat(Color(0.85, 0.85, 0.9), 0.9, 0.3), Vector3(90, 0, 0), 8)

	drone_root = Node3D.new()
	drone_root.name = "Drone"
	world.add_child(drone_root)

	camera = Camera3D.new()
	camera.fov = 40
	camera.near = 0.3
	camera.far = 600
	camera.current = true
	world.add_child(camera)
	_update_camera()


func _apply_quality() -> void:
	var q := Settings.quality()
	_sun.shadow_enabled = q["shadows"]
	_sun.directional_shadow_max_distance = 120.0
	Settings.apply_to_viewport(get_viewport())


func _update_camera() -> void:
	var b := Basis.from_euler(Vector3(cam_pitch, cam_yaw, 0))
	camera.global_transform = Transform3D(b, cam_target + b * Vector3(0, 0, cam_dist))


# --- UI ----------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui_root = UITheme.root_control()
	layer.add_child(ui_root)

	_bar = PanelContainer.new()
	var bar := _bar
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_stylebox_override("panel", UITheme.flat(Color(0.06, 0.065, 0.08, 0.94), 0, Color(1, 1, 1, 0.06), 1, 12))
	ui_root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	bar.add_child(hb)
	hb.add_child(UITheme.label("PROPWASH WORKSHOP", 24, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	var names := {"build": "1  BUILD", "wire": "2  WIRE", "setup": "3  SETUP"}
	for s in STAGES:
		var b := Button.new()
		b.text = names[s]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(190, 46)
		b.pressed.connect(func():
			Audio.play("click")
			switch_stage(s))
		_stage_buttons[s] = b
		hb.add_child(b)
	var fly := UITheme.accent_button("4  FLY", func(): setup.save_and_fly(), Vector2(150, 46))
	hb.add_child(fly)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp2)
	hb.add_child(UITheme.button("Menu (Esc)", _show_menu, Vector2(150, 46)))

	_toast = UITheme.label("", 24, Color.WHITE)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(0, 86)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", UITheme.flat(Color(0, 0, 0, 0.72), 8, Color(1, 1, 1, 0.1), 1, 14))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(_toast)


## Shows a transient message under the top bar.
func say(text: String, good: bool = false, seconds: float = 3.5) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", UITheme.GOOD if good else (UITheme.BAD if _is_bad(text) else UITheme.TEXT))
	_toast.reset_size()
	_toast.position.x = (1920.0 - _toast.size.x) * 0.5
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _is_bad(t: String) -> bool:
	return t.begins_with("Wrong") or t.begins_with("Never") or t.contains("already") or t.contains("must") or t.contains("first") or t.begins_with("Rotate") or t.contains("doesn't") or t.begins_with("C BAT")


# --- stage switching ------------------------------------------------------------------
func can_enter(target: String) -> String:
	var s := Game.stats()
	match target:
		"wire":
			if not s["complete"]:
				return "Finish the build first - missing: %s." % s["missing_text"]
			if s["broken_props"] > 0:
				return "%d broken prop(s) - scrap them and fit fresh ones first." % s["broken_props"]
		"setup":
			var w: String = can_enter("wire")
			if w != "":
				return w
			if not Game.wiring_complete():
				return "Wiring incomplete: %s" % Parts.missing_wires(Game.wires)[0]
	return ""


func switch_stage(target: String, force: bool = false) -> void:
	var why := can_enter(target)
	if why != "" and not force:
		say(why)
		Audio.play("error")
		_refresh_buttons()
		return
	if why != "":
		# forced entry with an inconsistent drone (e.g. after a crash): nearest allowed stage
		target = "wire" if (target == "setup" and can_enter("wire") == "") else "build"
	stage = target
	Game.workshop_stage = target
	Game.save_drone()
	world.visible = target != "setup"
	build.set_active(target == "build")
	wire.set_active(target == "wire")
	setup.set_active(target == "setup")
	_refresh_buttons()


func _refresh_buttons() -> void:
	for s in STAGES:
		var b: Button = _stage_buttons[s]
		b.button_pressed = (s == stage)
		var locked := can_enter(s) != ""
		b.modulate = Color(1, 1, 1, 0.55) if locked and s != stage else Color.WHITE


# --- input -----------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _menu != null:
		return
	if event.is_action_pressed("pause"):
		if stage == "build" and build.cancel_hold():
			return
		if stage == "wire" and wire.cancel_pending():
			return
		_show_menu()
		get_viewport().set_input_as_handled()
		return
	if stage != "build" and stage != "wire":
		return
	if event is InputEventMouseMotion and Input.is_action_pressed("cam_orbit"):
		cam_yaw -= event.relative.x * 0.006
		cam_pitch = clampf(cam_pitch - event.relative.y * 0.006, deg_to_rad(-86.0), deg_to_rad(-6.0))
		_update_camera()
	elif event.is_action_pressed("cam_zoom_in"):
		cam_dist = clampf(cam_dist * 0.9, 8.0, 80.0)
		_update_camera()
	elif event.is_action_pressed("cam_zoom_out"):
		cam_dist = clampf(cam_dist * 1.1, 8.0, 80.0)
		_update_camera()


func _show_menu() -> void:
	if _menu != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var root := UITheme.root_control()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	_menu = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UITheme.label("PAUSED", 34, UITheme.ACCENT))
	var close := func():
		_menu = null
		layer.queue_free()
	v.add_child(UITheme.accent_button("Resume", close, Vector2(340, 52)))
	v.add_child(UITheme.button("Options", func():
		var o := OptionsMenu.new()
		layer.add_child(o), Vector2(340, 52)))
	v.add_child(UITheme.button("Main menu", func():
		Game.save_drone()
		Game.goto("menu"), Vector2(340, 52)))


func _exit_tree() -> void:
	Game.save_drone()
