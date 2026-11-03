class_name FlyStage
extends Node
## FLY stage: FPV flight of the player's own saved build, live power budget, test
## courses and career missions (strike / recon) against fictional targets, flight
## assists, camera modes, damage, recovery or loss of the drone, and replays.

enum S { LOADING, COUNTDOWN, FLYING, REPLAY, RESULT, INTRO, CINEMATIC }

const VTX_RANGES := [Vector2(90, 500), Vector2(260, 1200), Vector2(480, 2000)]   # clear-until / dead-at (m)
const RX_FAILSAFE_DIST := 900.0
const REPLAY_FRAMES := 260
const REC_MAX := 1800
const CAM_OFFSET := Vector3(0, 0.02, -0.08)
const ASSIST_NAMES := ["BEGINNER", "INTERMEDIATE", "ACRO"]
const CAM_NAMES := ["FPV", "CHASE", "SPECTATOR"]
const VIS := 0.02            # drone model scale outside FPV (parts are modelled in cm; a little larger reads better on screen)

var state: int = S.LOADING
var mission: String = "free_flight"
var mdef: Dictionary = {}
var mtype := "free"
var source := "bench"
var drone: Dictionary = {}

var world: FlyWorld
var sim: DroneSim
var runner: MissionRunner
var stats: Dictionary
var cfg: Dictionary
var cam: Camera3D
var drone_vis: Node3D
var hud: Hud
var fx_rect: ColorRect
var fx_mat: ShaderMaterial
var loading_label: Label
var _load_bar: ColorRect
var _deg_cache := 0.0
var pause_ui: Control = null
var result_ui: Control = null

# input
var thr_stick := 0.0
var roll_s := 0.0
var pitch_s := 0.0
var yaw_s := 0.0
var _pad_active := false
var _toasts: Array = []
var _fx_time := 0.0
var assist := 2
var cam_mode := 0

# mission
var gates: Array = []
var gate_nodes: Array = []
var gate_idx := 0
var gate_radius := 3.1
var par_time := 0.0
var time_limit := 0.0
var route: Array = []
var route_nodes: Array = []
var route_idx := 0
var route_radius := 12.0
var countdown := 3.0
var race_time := 0.0
var flight_time := 0.0
var top_speed := 0.0
var _timer_running := false
var _ended := false
var _beam: MeshInstance3D
var _gate_mats: Dictionary = {}
var _need_landing := false
var _land_t := 0.0
var pods_left := 0
var pods_used := 0
var _paid := 0
var _objectives_paid := false
var _rx_range := RX_FAILSAFE_DIST

# crash / replay / cinematics
var _rec_pos: Array = []
var _rec_basis: Array = []
var _rec_tick := 0
var _replay_pos := 0.0
var _replay_start := 0
var _replay_hold := 0.0
var _replay_full := false
var _crash: Dictionary = {}
var _shards: Array = []
var _powerloss_t := 0.0
var _result_timer := -1.0
var _result_btn_back: Button
var _intro_t := 0.0
var _cine_t := 0.0
var _cine_target: Node3D = null
var _cine_then_end := false
var _strike_end: Dictionary = {}
var _cond: Dictionary = {}
var _broken: Dictionary = {}
var _rain: CPUParticles3D
var _spectator := Vector3.ZERO
## Test hook: holds the drone still (targets and effects keep running).
var debug_freeze := false
var _school: PanelContainer
var _school_lbl: RichTextLabel
var _school_armed_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	source = Game.flight.get("source", "bench")
	mission = Game.flight.get("mission", Game.mission) if source == "roster" else Game.mission
	mdef = Campaign.mission(mission)
	if mdef.is_empty():
		mdef = Campaign.mission("free_flight")
	mtype = mdef.get("type", "free")
	if source == "roster":
		drone = Career.get_drone(Game.flight.get("drone_id", ""))
		var why := Career.deploy_check(drone)
		if why != "":
			Game.goto("garage", {"message": why})
			return
	else:
		var ready: Dictionary = Game.ready_to_fly()
		if not ready["ok"]:
			Game.goto("workshop", {"stage": "build", "message": ready["reason"]})
			return
		drone = Game.flight_drone()
	stats = Parts.compute_build(drone["placed"], drone.get("broken", {}), drone.get("cond", {}))
	cfg = drone["cfg"]
	_cond = drone.get("cond", {}).duplicate()
	_broken = drone.get("broken", {}).duplicate()
	assist = Settings.assist
	loading_label = UITheme.label("LOADING %s..." % Campaign.MAP_NAMES.get(mdef.get("map", "testing"), "FIELD").to_upper(), 36, Color.WHITE)
	var ll := CanvasLayer.new()
	ll.layer = 30
	add_child(ll)
	var bgc := ColorRect.new()
	bgc.color = Color(0.05, 0.05, 0.07)
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ll.add_child(bgc)
	loading_label.position = Vector2(560, 500)
	ll.add_child(loading_label)
	var brief := UITheme.label("%s  -  %s" % [mdef.get("name", ""), drone.get("name", "")], 24, UITheme.ACCENT)
	brief.position = Vector2(560, 450)
	ll.add_child(brief)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.12)
	bar_bg.position = Vector2(560, 580)
	bar_bg.size = Vector2(800, 14)
	ll.add_child(bar_bg)
	_load_bar = ColorRect.new()
	_load_bar.color = UITheme.ACCENT
	_load_bar.position = bar_bg.position
	_load_bar.size = Vector2(1, 14)
	ll.add_child(_load_bar)
	await get_tree().process_frame
	await get_tree().process_frame
	await _build_all()
	ll.queue_free()


func _build_all() -> void:   # coroutine
	var q := Settings.quality()
	world = FlyWorld.new()
	world.set_map(mdef.get("map", "testing"))
	world.conditions = {"time": mdef.get("time", "dusk"), "weather": mdef.get("weather", "clear"), "wind": mdef.get("wind", 1.0)}
	if mission == "gate_race":
		world.exclusions = Missions.exclusions()
	elif mission == "shakedown":
		world.exclusions = Missions.SHAKEDOWN_XZ.duplicate()
	for spec in mdef.get("targets", []):
		var a: Vector2 = FlyWorld.map_info(world.map)["anchors"].get(spec.get("at", "convoy"), Vector2.ZERO)
		world.exclusions.append(a)
	add_child(world)
	world.progress.connect(func(f: float, what: String):
		loading_label.text = "LOADING...  %s" % what
		_load_bar.size.x = maxf(800.0 * f, 1.0))
	await world.build(q)
	Settings.apply_to_viewport(get_viewport())

	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = Settings.fov
	cam.near = 0.05
	cam.far = q["view"] * 1.6
	cam.current = true
	add_child(cam)

	sim = DroneSim.new()
	sim.setup(stats, cfg)
	sim.ground_height = world.height
	sim.obstacles = world.trees_near
	sim.boxes = world.boxes_near
	sim.water_level = FlyWorld.WATER_LEVEL if world.map == "testing" else -1000.0
	sim.water_test = world.is_water
	sim.pos = world.start_position() + Vector3(0, 0.03, 0)
	sim.rx_link = cfg["rx_enabled"]
	sim.used_mah = sim.capacity_mah * (1.0 - clampf(float(drone.get("charge", 1.0)), 0.0, 1.0))
	var wind: float = float(mdef.get("wind", 1.0))
	var wa := float(absi(mission.hash()) % 628) / 100.0
	sim.wind = Vector3(cos(wa), 0, sin(wa)) * wind
	sim.gust_strength = wind * 0.35
	_apply_assist()
	_rx_range = float(stats.get("rx_range", RX_FAILSAFE_DIST))
	pods_left = maxi(int(stats.get("payload_charges", 0)) - int(drone.get("pods_used", 0)), 0) if stats.get("payload_kind", "") == "drop" else 0
	if source == "roster":
		pods_left = int(stats.get("payload_charges", 0)) if stats.get("payload_kind", "") == "drop" else 0

	drone_vis = DroneVisual.assemble(drone["placed"], _broken, _cond, Career.paint_of(drone))
	drone_vis.visible = false
	add_child(drone_vis)

	runner = MissionRunner.new()
	add_child(runner)
	runner.notice.connect(func(t: String, c: Color): _toast(t, 3.0, c))
	runner.objective_destroyed.connect(_on_objective_destroyed)
	if mtype in ["strike", "recon"]:
		runner.setup(mdef, world)
	if world.rain:
		_make_rain()
	_spectator = world.start_position() + Vector3(6, 2.2, 8)

	_build_overlay_ui()
	_build_mission()
	_update_camera(0.0)
	if source == "roster":
		state = S.INTRO
		_intro_t = 0.0
		hud.overlay_title = "DEPLOYING %s" % drone.get("name", "").to_upper()
		hud.overlay_sub = "%s  •  %s, %s, wind %.0f m/s" % [mdef.get("name", ""), mdef.get("time", ""), mdef.get("weather", ""), mdef.get("wind", 0.0)]
		Career.data["stats"]["flights"] = int(Career.data["stats"]["flights"]) + 1
	elif mtype == "free":
		state = S.FLYING
	else:
		state = S.COUNTDOWN
		countdown = 3.4
	if not _school.visible:
		_toast("%s arm  •  throttle W/S or left stick  •  %s flight mode (%s)  •  %s camera  •  %s flight school" % [Pad.glyph("arm"), Pad.glyph("flight_assist"), ASSIST_NAMES[assist], Pad.glyph("camera_mode"), Pad.glyph("help")], 7.0, Hud.WHITE)


func _apply_assist() -> void:
	sim.angle_mode = assist < 2
	sim.alt_assist = assist == 0
	sim.angle_max = deg_to_rad(32.0 if assist == 0 else 55.0)
	if assist == 2 and cfg.get("angle_mode", false):
		sim.angle_mode = true
	if assist == 0:
		thr_stick = maxf(thr_stick, 0.0)


func _make_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 500 if Settings.graphics_preset > 0 else 200
	_rain.lifetime = 0.8
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(18, 2, 18)
	_rain.direction = Vector3(0.15, -1, 0.05)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 20.0
	_rain.initial_velocity_max = 26.0
	_rain.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	q.material = m
	_rain.mesh = q
	_rain.local_coords = false
	add_child(_rain)


func _build_overlay_ui() -> void:
	var l1 := CanvasLayer.new()
	l1.layer = 1
	add_child(l1)
	fx_rect = ColorRect.new()
	fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_mat = ShaderMaterial.new()
	fx_mat.shader = load("res://shaders/analog_fx.gdshader")
	fx_rect.material = fx_mat
	l1.add_child(fx_rect)
	var l2 := CanvasLayer.new()
	l2.layer = 2
	add_child(l2)
	hud = Hud.new()
	hud.show_hud = Settings.hud_on
	l2.add_child(hud)
	# flight school card (tutorial)
	var l3 := CanvasLayer.new()
	l3.layer = 3
	add_child(l3)
	var root := UITheme.root_control()
	l3.add_child(root)
	_school = PanelContainer.new()
	_school.position = Vector2(1440, 250)
	_school.custom_minimum_size = Vector2(450, 0)
	var st := UITheme.flat(Color(0.04, 0.05, 0.06, 0.82), 8, Color(UITheme.ACCENT2, 0.6), 1, 14)
	st.border_width_left = 6
	_school.add_theme_stylebox_override("panel", st)
	_school.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_school)
	_school_lbl = RichTextLabel.new()
	_school_lbl.bbcode_enabled = true
	_school_lbl.fit_content = true
	_school_lbl.scroll_active = false
	_school_lbl.custom_minimum_size = Vector2(420, 0)
	_school_lbl.add_theme_font_size_override("normal_font_size", 19)
	_school_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_school.add_child(_school_lbl)
	var flights := int(Career.data["stats"].get("flights", 0))
	_school.visible = Settings.opt.get("tutorial_hints", true) and (flights <= 3 or mission == "shakedown" or source == "bench" and SaveData.best_time("gate_race") <= 0.0)


# --- missions ------------------------------------------------------------------------------------
func _gate_material(color: Color, emit: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = emit
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_mission() -> void:
	_gate_mats = {
		"wait": _gate_material(Color(0.35, 0.75, 1.0), 1.0),
		"next": _gate_material(Color(1.0, 0.45, 0.2), 2.0),
		"done": _gate_material(Color(0.4, 1.0, 0.5), 1.0),
	}
	if mission == "gate_race" or mission == "shakedown":
		var g := Missions.gate_race(world) if mission == "gate_race" else Missions.shakedown(world)
		gates = g["gates"]
		gate_radius = g["radius"]
		par_time = g["par"]
		time_limit = g["limit"]
		for i in gates.size():
			var node := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = gate_radius - 0.2
			tm.outer_radius = gate_radius + 0.25
			tm.rings = 28
			tm.ring_segments = 8
			node.mesh = tm
			node.material_override = _gate_mats["wait"]
			var n: Vector3 = gates[i]["normal"]
			node.transform = Transform3D(Basis(Quaternion(Vector3.UP, n)), gates[i]["pos"])
			add_child(node)
			gate_nodes.append(node)
	elif mission == "battery_challenge":
		var r := Missions.battery_route(world)
		route = r["points"]
		route_radius = r["radius"]
		for i in route.size():
			var node := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = route_radius - 0.5
			tm.outer_radius = route_radius
			tm.rings = 36
			tm.ring_segments = 6
			node.mesh = tm
			node.material_override = _gate_mats["wait"]
			node.position = route[i]
			add_child(node)
			route_nodes.append(node)
	if mtype in ["race", "gates", "battery"]:
		_beam = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = 160.0
		_beam.mesh = cm
		var bm := _gate_material(Color(1.0, 0.5, 0.25, 0.35), 1.5)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam.material_override = bm
		add_child(_beam)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_mission_markers()


func _refresh_mission_markers() -> void:
	if not gate_nodes.is_empty():
		for i in gate_nodes.size():
			gate_nodes[i].material_override = _gate_mats["done"] if i < gate_idx else (_gate_mats["next"] if i == gate_idx else _gate_mats["wait"])
		if gate_idx < gates.size():
			_beam.position = gates[gate_idx]["pos"] + Vector3(0, 80, 0)
			_beam.visible = true
		elif _need_landing:
			_beam.position = world.start_position() + Vector3(0, 80, 0)
			_beam.visible = true
		else:
			_beam.visible = false
	elif mission == "battery_challenge":
		for i in route_nodes.size():
			route_nodes[i].material_override = _gate_mats["done"] if i < route_idx else (_gate_mats["next"] if i == route_idx else _gate_mats["wait"])
		if route_idx < route.size():
			_beam.position = route[route_idx] + Vector3(0, 70, 0)
			_beam.visible = true
		else:
			_beam.visible = false


# --- input -------------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.3 or event is InputEventJoypadButton:
		_pad_active = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad_active = false


func _unhandled_input(event: InputEvent) -> void:
	if state == S.LOADING:
		return
	if event.is_action_pressed("pause"):
		if state == S.RESULT:
			return
		if state == S.INTRO:
			_end_intro()
			return
		if pause_ui != null:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if state == S.INTRO and (event.is_action_pressed("arm") or event.is_action_pressed("ui_accept")):
		_end_intro()
		return
	if state == S.REPLAY and (event.is_action_pressed("arm") or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER)):
		_replay_pos = REPLAY_FRAMES + 99999.0
		_replay_hold = 9.0
		return
	if event.is_action_pressed("toggle_hud"):
		hud.show_hud = not hud.show_hud
		Settings.hud_on = hud.show_hud
		Settings.save_settings()
	elif event.is_action_pressed("mouse_stick"):
		Settings.mouse_stick = not Settings.mouse_stick
		Settings.save_settings()
		_toast("Mouse stick mode %s" % ("ON - pointer = sticks" if Settings.mouse_stick else "OFF"), 2.0, Hud.WHITE)
	elif event.is_action_pressed("flight_mode"):
		sim.angle_mode = not sim.angle_mode
		if not sim.angle_mode:
			sim.alt_assist = false
			assist = 2
		_toast("%s mode" % ("ANGLE (self-level)" if sim.angle_mode else "ACRO (rate)"), 2.0, Hud.GREEN)
		Audio.play("beep")
	elif event.is_action_pressed("flight_assist"):
		assist = (assist + 1) % 3
		_apply_assist()
		if assist == 0:
			thr_stick = 0.5 if sim.armed else 0.0
		_toast("%s flight mode%s" % [ASSIST_NAMES[assist], ["  - self-level + altitude hold (throttle centre = hover)", "  - self-level, manual throttle", "  - rate mode, no self-level"][assist]], 3.0, Hud.GREEN)
		Audio.play("beep")
	elif event.is_action_pressed("help"):
		_school.visible = not _school.visible
		_school_armed_t = 0.0
	elif event.is_action_pressed("camera_mode"):
		cam_mode = (cam_mode + 1) % 3
		_toast("Camera: %s" % CAM_NAMES[cam_mode], 1.5, Hud.WHITE)
	elif event.is_action_pressed("payload") and state == S.FLYING:
		_release_payload()
	elif event.is_action_pressed("restart"):
		if source == "bench":
			Game.goto("fly")
	elif event.is_action_pressed("arm") and state == S.FLYING:
		_toggle_arm()


func _toggle_arm() -> void:
	if sim.armed:
		sim.armed = false
		thr_stick = 0.0
		_toast("DISARMED", 1.5, Hud.AMBER)
		return
	if not cfg["rx_enabled"]:
		_toast("NO RX LINK - receiver UART is disabled (SETUP > Port)", 3.0)
		Audio.play("error")
	elif sim.power_lost:
		_toast("Battery empty - cannot arm", 2.5)
		Audio.play("error")
	elif thr_stick > 0.06 and assist != 0 and not (_pad_active and Settings.pad_throttle_abs):
		_toast("Throttle must be low to arm  (S)", 2.5)
		Audio.play("error")
	else:
		sim.armed = true
		Audio.play("arm")
		Pad.rumble(0.2, 0.0, 0.15)
		_toast("ARMED", 1.5, Hud.GREEN)


func _release_payload() -> void:
	if stats.get("payload_kind", "") != "drop":
		_toast("No drop module fitted", 1.5, Hud.AMBER)
		return
	if pods_left <= 0:
		_toast("Module empty", 1.5, Hud.AMBER)
		Audio.play("error")
		return
	pods_left -= 1
	pods_used += 1
	runner.release(sim, float(stats["payload_power"]), float(stats["payload_radius"]))
	sim.mass = maxf(sim.mass - float(stats.get("payload_unit_mass", 0.05)), 0.15)
	_toast("POD RELEASED  (%d left)" % pods_left, 1.5, Hud.AMBER)


func _read_controls(dt: float) -> void:
	var prec := 0.45 if Input.is_action_pressed("kb_precision") else 1.0
	if _pad_active and Settings.pad_throttle_abs:
		# absolute gamepad throttle: stick fully down = 0, centre = 50 %, up = 100 %
		var ax := Input.get_axis("throttle_down", "throttle_up")
		thr_stick = clampf(0.5 + ax * 0.5, 0.0, 1.0)
	else:
		var rate := (0.75 if _pad_active else 0.55) * (0.7 if assist == 0 else 1.0)
		thr_stick = clampf(thr_stick + Input.get_axis("throttle_down", "throttle_up") * rate * dt, 0.0, 1.0)
		if assist == 0 and sim.armed and absf(Input.get_axis("throttle_down", "throttle_up")) < 0.1:
			thr_stick = move_toward(thr_stick, 0.5, dt * 0.35)   # beginner: throttle drifts back to "hold altitude"
	var yaw_t := Input.get_axis("yaw_left", "yaw_right") * prec
	var roll_t := Input.get_axis("roll_left", "roll_right") * prec
	var pitch_t := Input.get_axis("pitch_back", "pitch_forward") * prec
	if Settings.mouse_stick:
		var mp := get_viewport().get_mouse_position()
		var r := 300.0 / maxf(Settings.mouse_sens, 0.1)
		roll_t += clampf((mp.x - 960.0) / r, -1.0, 1.0)
		pitch_t += clampf(-(mp.y - 540.0) / r, -1.0, 1.0)
	if Settings.opt.get("invert_pitch", false):
		pitch_t = -pitch_t
	roll_t = clampf(roll_t, -1.0, 1.0)
	pitch_t = clampf(pitch_t, -1.0, 1.0)
	if _pad_active:
		# stick expo: softer around centre, full deflection unchanged
		var e := float(Settings.opt.get("expo", 0.25))
		roll_t = roll_t * (1.0 - e) + roll_t * roll_t * roll_t * e
		pitch_t = pitch_t * (1.0 - e) + pitch_t * pitch_t * pitch_t * e
		yaw_t = yaw_t * (1.0 - e) + yaw_t * yaw_t * yaw_t * e
	if _pad_active or Settings.mouse_stick:
		roll_s = roll_t
		pitch_s = pitch_t
		yaw_s = yaw_t
	else:
		var ramp := 7.0 * dt
		roll_s = move_toward(roll_s, roll_t, ramp)
		pitch_s = move_toward(pitch_s, pitch_t, ramp)
		yaw_s = move_toward(yaw_s, yaw_t, ramp)


# --- simulation tick -------------------------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	if state == S.LOADING or get_tree().paused:
		return
	if state == S.INTRO or state == S.CINEMATIC:
		if runner and state == S.CINEMATIC:
			runner.tick(dt, sim, null, 1.0)
		return
	if state == S.COUNTDOWN:
		countdown -= dt
		if countdown <= 0.0:
			state = S.FLYING
			_timer_running = true
			Audio.play("gate", 1.5)
			_toast("GO!", 1.2, Hud.GREEN)
		return
	if state != S.FLYING:
		if runner and state != S.REPLAY:
			runner.tick(dt, sim, null, 1.0)
		return
	if debug_freeze:
		runner.tick(dt, sim, cam, float(stats.get("scan_mult", 1.0)))
		return
	_read_controls(dt)
	sim.stick_throttle = thr_stick
	sim.stick_roll = roll_s
	sim.stick_pitch = pitch_s
	sim.stick_yaw = yaw_s
	var home := world.start_position()
	var dist_h := Vector2(sim.pos.x - home.x, sim.pos.z - home.z).length()
	sim.rx_link = cfg["rx_enabled"] and dist_h < _rx_range and absf(sim.pos.x) < world.half - 4.0 and absf(sim.pos.z) < world.half - 4.0
	# damaged electronics: brief control glitches
	if stats.get("glitch", 0.0) > 0.25 and randf() < float(stats["glitch"]) * 0.004:
		sim.rx_link = false
	var prev := sim.pos
	sim.step(dt)
	flight_time += dt
	top_speed = maxf(top_speed, sim.speed())
	if _timer_running and not _ended:
		race_time += dt
	_rec_tick += 1
	if _rec_tick % 4 == 0:
		_rec_pos.append(sim.pos)
		_rec_basis.append(sim.basis)
		if _rec_pos.size() > REC_MAX:
			_rec_pos.pop_front()
			_rec_basis.pop_front()
	runner.tick(dt, sim, cam if cam_mode == 0 else _scan_cam(), float(stats.get("scan_mult", 1.0)))
	# flying into a target is an impact strike
	var tgt := runner.impact_target(sim)
	if tgt != null and sim.speed() > 3.0:
		_impact_strike(tgt)
		return
	if sim.impact_kind != "":
		_on_impact()
		return
	_mission_tick(prev)
	if runner.phase == "failed" and not _ended:
		_end_flight("MISSION FAILED", "The objective got away.", "Mission failed.", false)
		return
	# battery flat -> glide down, then back to the workshop
	if sim.power_lost:
		_powerloss_t += dt
		var gh := world.top_at(sim.pos.x, sim.pos.z)
		if (sim.on_ground and sim.speed() < 1.5 and _powerloss_t > 1.0) or _powerloss_t > 25.0:
			_end_flight("BATTERY FLAT", "The pack hit its voltage cut-off and the drone lost power.", "Battery flat after %s." % _fmt(flight_time), false, _drone_is_lost())
		elif sim.pos.y < gh - 5.0:
			_end_flight("BATTERY FLAT", "The pack hit its voltage cut-off and the drone lost power.", "Battery flat.", false, _drone_is_lost())


func _scan_cam() -> Camera3D:
	return cam


func _landed_home() -> bool:
	var home := world.start_position()
	return sim.on_ground and sim.speed() < 1.2 and Vector2(sim.pos.x - home.x, sim.pos.z - home.z).length() < 16.0


func _mission_tick(prev: Vector3) -> void:
	if _ended:
		return
	if (mission == "gate_race" or mission == "shakedown") and gate_idx < gates.size() and _timer_running:
		var g: Dictionary = gates[gate_idx]
		var n: Vector3 = g["normal"]
		var s0: float = (prev - g["pos"]).dot(n)
		var s1: float = (sim.pos - g["pos"]).dot(n)
		if s0 * s1 <= 0.0 and s0 != s1:
			var t: float = s0 / (s0 - s1)
			var p := prev.lerp(sim.pos, t)
			if p.distance_to(g["pos"]) < gate_radius:
				gate_idx += 1
				Audio.play("gate")
				Pad.rumble(0.2, 0.0, 0.08)
				_toast("Gate %d / %d" % [gate_idx, gates.size()], 1.2, Hud.GREEN)
				if gate_idx >= gates.size():
					if mission == "shakedown":
						_need_landing = true
						_toast("All gates! Now land back on the pad.", 4.0, Hud.GREEN)
					else:
						_complete_mission()
				_refresh_mission_markers()
		if race_time > time_limit and not _ended:
			_end_flight("TIME OVER", "You ran out of time (limit %s)." % _fmt(time_limit), "Out of time.", false)
	elif mission == "shakedown" and _need_landing:
		if _landed_home():
			_land_t += 1.0 / Engine.physics_ticks_per_second
			if _land_t > 0.6:
				_complete_mission()
		else:
			_land_t = 0.0
	elif mission == "battery_challenge" and route_idx < route.size() and _timer_running:
		if sim.pos.distance_to(route[route_idx]) < route_radius:
			route_idx += 1
			Audio.play("gate")
			_toast("Checkpoint %d / %d" % [route_idx, route.size()], 1.2, Hud.GREEN)
			_refresh_mission_markers()
			if route_idx >= route.size():
				_complete_mission()
	elif mtype in ["strike", "recon"] and runner.phase == "rtb":
		if not _objectives_paid:
			_objectives_paid = true
			_pay_mission()
		if _landed_home():
			_land_t += 1.0 / Engine.physics_ticks_per_second
			if _land_t > 0.8:
				_complete_mission()
		else:
			_land_t = 0.0


## Pays out a career mission once (objectives complete).
func _pay_mission() -> void:
	if source != "roster" or _paid > 0:
		return
	_paid = Career.complete_mission(mdef, runner.bonus_credits() if runner else 0)
	Audio.play("cash")
	_toast("+%d cr" % _paid, 3.0, Hud.GREEN)


func _complete_mission() -> void:
	_ended = true
	var lines: Array = []
	if mtype in ["race", "gates", "battery"]:
		var res := SaveData.record_run(mission, race_time, sim.used_mah)
		lines.append("Time  %s" % _fmt(race_time))
		if mission == "gate_race":
			lines.append("Par   %s" % _fmt(par_time))
		if res["new_best"]:
			lines.append("NEW BEST TIME!")
		if not res["unlocked"].is_empty():
			var names: Array = []
			for id in res["unlocked"]:
				names.append(Parts.part(id)["name"])
			lines.append("New parts in the market: " + ", ".join(names))
	lines.append("Battery used  %d mAh   (%d%% left)" % [int(sim.used_mah), int(sim.soc() * 100.0)])
	if mtype in ["strike", "recon"]:
		lines.append("Targets destroyed %d   •   score %d" % [runner.kills, runner.score])
	_pay_mission()
	if source == "roster":
		lines.append("Reward  %d cr%s" % [_paid, "" if Career.mission_count(mission) > 1 else "   +%d reputation" % int(mdef.get("rep", 0))])
		lines.append("%s recovered and back on the rack." % drone.get("name", "Drone"))
	elif mtype != "free":
		lines.append("(Bench test flight - career rewards are paid when you deploy from the garage.)")
	_apply_outcome(false)
	Audio.play("success")
	Pad.rumble(0.3, 0.3, 0.4)
	_show_result("%s COMPLETE" % mdef.get("name", "MISSION").to_upper(), lines, true, false)


# --- impacts, strikes, crashes ------------------------------------------------------------------------
func _impact_strike(t: CombatTarget) -> void:
	var spd := sim.speed()
	var kinetic := clampf(0.5 * sim.mass * spd * spd * 0.25, 10.0, 110.0)
	var power := kinetic + float(stats.get("payload_power", 0.0)) * pods_left * 1.2
	var radius := maxf(float(stats.get("payload_radius", 0.0)), 3.0)
	runner.detonate(sim.pos, power, radius, t)
	pods_left = 0
	_strike_end = {"target": t.title}
	Audio.motor_level = 0.0
	Pad.rumble(1.0, 1.0, 0.5)
	sim.armed = false
	_ended = true
	# every component takes heavy damage
	for slot in drone["placed"]:
		_cond[slot] = minf(float(_cond.get(slot, 1.0)), randf_range(0.1, 0.35))
		if slot.begins_with("prop_"):
			_broken[slot] = true
	_crash = {"text": "Impact strike on the %s at %d km/h." % [t.title, int(spd * 3.6)], "broken": [], "pos": sim.pos, "normal": Vector3.UP, "kind": "strike"}
	if state == S.CINEMATIC:
		_cine_then_end = true
		return
	_start_replay()


func _on_impact() -> void:
	var kind := sim.impact_kind
	var speed := sim.impact_speed
	var n := sim.impact_normal
	var broken_now: Array = []
	if kind != "water" or speed > sim.crash_speed:
		var count := clampi(1 + int((speed - sim.crash_speed) / 3.5), 1, 4)
		var ranked: Array = []
		for i in 4:
			var mp: Vector2 = sim.motor_pos[i]
			var dir := (sim.basis * Vector3(mp.x, 0, mp.y)).normalized()
			ranked.append([dir.dot(-n) + randf() * 0.05, i])
		ranked.sort_custom(func(a, b): return a[0] > b[0])
		for k in count:
			var slot := "prop_%d" % (ranked[k][1] + 1)
			_broken[slot] = true
			broken_now.append(slot)
		# structural damage scales with the impact and is reduced by guards / armour
		var protect := maxf(float(stats.get("durability", 1.0)), 0.5)
		var sev := clampf((speed - sim.crash_speed) / 14.0, 0.05, 1.0) / protect * Settings.difficulty_damage()
		var fwd := -(sim.basis.z)
		var front := fwd.dot(-n) > 0.4
		_hurt("frame", sev * 0.35)
		_hurt("cam", sev * (0.55 if front else 0.12))
		_hurt("cam_mount", sev * (0.4 if front else 0.1))
		_hurt("battery", sev * 0.15)
		_hurt("antenna", sev * 0.3)
		for e in Parts.ELECTRONICS:
			_hurt(e, sev * 0.18)
		for k in count:
			_hurt("motor_%d" % (ranked[k][1] + 1), sev * 0.45)
		_hurt("guard", sev * 0.5)
	if source == "bench":
		for s in broken_now:
			Game.broken[s] = true
		Game.save_drone()
	var place: String = {"ground": "the ground", "tree": "a tree", "water": "the lake", "building": "a building"}.get(kind, "something")
	var kmh := int(speed * 3.6)
	var text := "Hit %s at %d km/h." % [place, kmh]
	if kind == "water" and broken_now.is_empty():
		text = "Splashdown! The drone was fished out of the lake."
	elif not broken_now.is_empty():
		text += "  %d prop%s broke." % [broken_now.size(), "" if broken_now.size() == 1 else "s"]
	_crash = {"text": text, "broken": broken_now, "pos": sim.impact_point, "normal": n, "kind": kind}
	Audio.play("crash")
	Audio.motor_level = 0.0
	Pad.rumble(0.8, 1.0, 0.4)
	Fx.dust(runner, sim.impact_point, 0.5)
	Fx.sparks(runner, sim.impact_point, 14)
	_ended = true
	_start_replay()


func _hurt(slot: String, amount: float) -> void:
	if not drone["placed"].has(slot) or amount <= 0.0:
		return
	_cond[slot] = clampf(float(_cond.get(slot, 1.0)) - amount * randf_range(0.6, 1.2), 0.05, 1.0)


func _on_objective_destroyed(t: CombatTarget) -> void:
	if state != S.FLYING and state != S.RESULT:
		return
	if state == S.RESULT:
		return
	state = S.CINEMATIC
	_cine_t = 0.0
	_cine_target = t
	Engine.time_scale = 0.45
	hud.overlay_title = "OBJECTIVE DESTROYED"
	hud.overlay_sub = t.title
	Audio.motor_level = 0.0


func _drone_is_lost() -> bool:
	if mdef.get("recover", "recoverable") != "contested" or source != "roster":
		return false
	if not _crash.is_empty() and _crash.get("kind", "") == "strike":
		return true
	var home := world.start_position()
	return Vector2(sim.pos.x - home.x, sim.pos.z - home.z).length() > 45.0


func _start_replay() -> void:
	if _school:
		_school.visible = false
	state = S.REPLAY
	_replay_full = false
	_replay_start = maxi(0, _rec_pos.size() - REPLAY_FRAMES)
	_replay_pos = float(_replay_start)
	_replay_hold = 0.0
	hud.show_hud = false
	hud.warnings = []
	hud.markers = []
	hud.overlay_title = "REPLAY"
	hud.overlay_sub = "%s / Enter: skip" % Pad.glyph("arm")
	drone_vis.visible = true
	fx_mat.set_shader_parameter("intensity", 0.0)
	cam.fov = 70.0


## Full cinematic replay of the recorded flight (from the result screen).
func _start_full_replay() -> void:
	if _rec_pos.size() < 10:
		return
	if result_ui:
		result_ui.get_parent().visible = false
	state = S.REPLAY
	_replay_full = true
	_replay_start = 0
	_replay_pos = 0.0
	_replay_hold = 0.0
	hud.show_hud = false
	hud.overlay_title = "CINEMATIC REPLAY"
	hud.overlay_sub = "%s / Enter: skip" % Pad.glyph("arm")
	drone_vis.visible = true
	fx_mat.set_shader_parameter("intensity", 0.0)
	cam.fov = 60.0


func _process_replay(dt: float) -> void:
	_replay_pos += dt * 60.0 * (0.55 if not _replay_full else 1.0)
	var last := _rec_pos.size() - 1
	if last < 1:
		_finish_replay()
		return
	if _replay_pos >= last:
		_replay_pos = last
		if _replay_hold == 0.0 and not _replay_full:
			_spawn_shards()
			_swap_broken_visual()
		_replay_hold += dt
	var i0 := clampi(int(_replay_pos), 0, last)
	var i1 := mini(i0 + 1, last)
	var f := _replay_pos - float(i0)
	var p: Vector3 = (_rec_pos[i0] as Vector3).lerp(_rec_pos[i1], f)
	var b: Basis = (_rec_basis[i0] as Basis).slerp(_rec_basis[i1], f)
	drone_vis.global_transform = Transform3D(b * Basis.from_scale(Vector3.ONE * VIS), p)
	var back_i := maxi(i0 - 10, 0)
	var travel: Vector3 = p - (_rec_pos[back_i] as Vector3)
	if travel.length() < 0.2:
		travel = Vector3(0, 0, -1)
	travel = travel.normalized()
	var want := p - travel * 4.5 + Vector3(0, 1.8, 0)
	if _replay_full:
		# cut between a chase camera and fixed "trackside" cameras every few seconds
		var shot := int(_replay_pos / 240.0) % 3
		if shot == 1:
			var anchor_i := clampi(int(_replay_pos / 240.0) * 240 + 120, 0, last)
			want = (_rec_pos[anchor_i] as Vector3) + Vector3(9, 4, 9)
			cam.global_position = want
		elif shot == 2:
			want = p + Vector3(sin(_replay_pos * 0.01) * 6.0, 2.5, cos(_replay_pos * 0.01) * 6.0)
			cam.global_position = cam.global_position.lerp(want, minf(dt * 3.0, 1.0))
		else:
			cam.global_position = cam.global_position.lerp(want, minf(dt * 4.0, 1.0))
	else:
		cam.global_position = cam.global_position.lerp(want, minf(dt * 4.0, 1.0)) if _replay_pos > _replay_start + 1 else want
	var gh := world.top_at(cam.global_position.x, cam.global_position.z) + 0.6
	cam.global_position.y = maxf(cam.global_position.y, gh)
	if cam.global_position.distance_to(p) > 0.05:
		cam.look_at(p, Vector3.UP)
	for s in _shards:
		s["v"].y -= 9.81 * dt
		s["n"].position += s["v"] * dt
		s["n"].rotation += s["spin"] * dt
	if _replay_hold > (1.6 if not _replay_full else 0.5) or (_replay_pos >= _replay_start + REPLAY_FRAMES + 50 and not _replay_full):
		_finish_replay()


func _finish_replay() -> void:
	hud.overlay_title = ""
	hud.overlay_sub = ""
	if _replay_full:
		state = S.RESULT
		if result_ui:
			result_ui.get_parent().visible = true
		return
	var lost := _drone_is_lost()
	if not _strike_end.is_empty():
		_end_flight("IMPACT STRIKE", _crash["text"], _crash["text"], true, lost)
	else:
		_end_flight("CRASHED" if not lost else "DRONE LOST", _crash["text"], _workshop_crash_message(), true, lost)


func _workshop_crash_message() -> String:
	var t: String = _crash["text"]
	if not _crash["broken"].is_empty():
		t += "  Scrap the broken props and fit fresh ones."
	return t


func _swap_broken_visual() -> void:
	var t := drone_vis.global_transform
	drone_vis.queue_free()
	drone_vis = DroneVisual.assemble(drone["placed"], _broken, _cond, Career.paint_of(drone))
	add_child(drone_vis)
	drone_vis.global_transform = t


func _spawn_shards() -> void:
	var pc: Color = Parts.part(drone["placed"].get("prop_1", "prop_5143_ccw")).get("color", Color(1, 0.85, 0))
	for k in range(_crash["broken"].size() * 3):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.012, 0.025)
		mi.mesh = bm
		mi.material_override = MeshFactory.mat(pc, 0.0, 0.4, 0.3)
		add_child(mi)
		mi.global_position = _crash["pos"] + Vector3(0, 0.1, 0)
		var v := Vector3(randf_range(-1, 1), randf_range(1.0, 3.5), randf_range(-1, 1)) * 1.5
		_shards.append({"n": mi, "v": v, "spin": Vector3(randf() * 20, randf() * 20, randf() * 20)})


## Writes the flight's consequences back to the drone (roster entry or the workbench).
func _apply_outcome(lost: bool) -> void:
	var charge := sim.soc()
	if source == "bench":
		Game.bench_charge = charge
		for slot in _cond:
			if float(_cond[slot]) < 0.999:
				Game.cond[slot] = _cond[slot]
		for slot in _broken:
			Game.broken[slot] = true
		Game.save_drone()
		return
	var d := Career.get_drone(drone.get("id", ""))
	if d.is_empty():
		return
	if lost:
		Career.remove_drone(d["id"])
		Career.data["stats"]["drones_lost"] = int(Career.data["stats"]["drones_lost"]) + 1
		Career.save()
		return
	d["cond"] = _cond.duplicate()
	d["broken"] = _broken.duplicate()
	d["charge"] = charge
	d["missions"] = int(d.get("missions", 0)) + 1
	d["targets"] = int(d.get("targets", 0)) + (runner.kills if runner else 0)
	d["pods_used"] = int(d.get("pods_used", 0)) + pods_used
	d["location"] = "rack"
	if not _broken.is_empty() or _cond.values().any(func(c): return float(c) < 0.5):
		d["certified"] = false
	Career.mark_dirty()
	Career.save()


func _end_flight(title: String, sub: String, workshop_msg: String, crashed: bool, lost: bool = false) -> void:
	if state == S.RESULT:
		return
	_ended = true
	state = S.RESULT
	Engine.time_scale = 1.0
	drone_vis.visible = true
	var lines := [sub, "", "Flight time  %s     Top speed  %d km/h" % [_fmt(flight_time), int(top_speed * 3.6)], "Battery used  %d mAh" % int(sim.used_mah)]
	if crashed and not _crash.get("broken", []).is_empty():
		lines.append("Broken: " + ", ".join(_crash["broken"]).replace("prop_", "prop "))
	var dmg: Array = []
	for slot in _cond:
		if float(_cond[slot]) < float(drone.get("cond", {}).get(slot, 1.0)) - 0.01:
			dmg.append("%s %d %%" % [slot.replace("_", " "), int(float(_cond[slot]) * 100.0)])
	if not dmg.is_empty():
		lines.append("Damage: " + ", ".join(dmg))
	if runner and mtype in ["strike", "recon"]:
		lines.append("Targets destroyed %d   •   score %d" % [runner.kills, runner.score])
		if runner.phase == "rtb" and _paid > 0:
			lines.append("Objectives were completed: %d cr paid." % _paid)
	if lost:
		lines.append("")
		lines.append("%s went down in contested ground and is LOST." % drone.get("name", "The drone"))
	elif source == "roster" and crashed:
		lines.append("The drone was recovered - repair it at the workbench.")
	SaveData.note_speed(top_speed * 3.6)
	_apply_outcome(lost)
	Game.last_result = {"msg": workshop_msg}
	_show_result(title, lines, false, crashed, workshop_msg)
	_result_timer = -1.0


# --- result / pause UI --------------------------------------------------------------------------------------------
func _show_result(title: String, lines: Array, success: bool, crashed: bool, msg: String = "") -> void:
	if _school:
		_school.visible = false
	state = S.RESULT
	_ended = true
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.warnings = []
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	result_ui = UITheme.root_control()
	result_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(result_ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_ui.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_ui.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(860, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var col := UITheme.GOOD if success else (UITheme.BAD if crashed else UITheme.ACCENT)
	v.add_child(UITheme.label(title, 44, col))
	for l in lines:
		var lab := UITheme.label(l, 22)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(820, 0)
		v.add_child(lab)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var message := msg
	if message == "":
		message = "Back at the bench." if not success else "Great flying!"
	if source == "roster":
		_result_btn_back = UITheme.accent_button("RETURN TO GARAGE", func(): _go_garage(message), Vector2(300, 56))
	else:
		_result_btn_back = UITheme.accent_button("BACK TO WORKBENCH", func(): _go_workshop(message), Vector2(300, 56))
		h.add_child(_result_btn_back)
		_result_btn_back = UITheme.button("Garage", func(): _go_garage(message), Vector2(160, 56))
	h.add_child(_result_btn_back)
	h.add_child(UITheme.button("Watch replay", _start_full_replay, Vector2(200, 56)))
	if source == "bench" and not crashed and Game.stats()["broken_props"] == 0:
		h.add_child(UITheme.button("Fly again", func(): Game.goto("fly"), Vector2(180, 56)))
	Pad.focus_first(h, true)


func _go_workshop(msg: String) -> void:
	Game.save_drone()
	var stage := "build" if Game.stats()["broken_props"] > 0 else "setup"
	Game.goto("workshop", {"stage": stage, "message": msg})


func _go_garage(msg: String) -> void:
	Game.save_drone()
	Career.save()
	Game.goto("garage", {"spawn": "rack" if source == "roster" else "outside", "message": msg})


func _pause() -> void:
	if state == S.REPLAY or state == S.RESULT:
		return
	get_tree().paused = true
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.motor_level = 0.0
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	pause_ui = UITheme.root_control()
	pause_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(pause_ui)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_ui.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_ui.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UITheme.label("PAUSED", 38, UITheme.ACCENT))
	v.add_child(UITheme.label("%s  •  %s" % [mdef.get("name", ""), drone.get("name", "")], 20, UITheme.MUTED))
	v.add_child(UITheme.accent_button("Resume", _resume, Vector2(420, 54)))
	if source == "bench":
		v.add_child(UITheme.button("Restart", func():
			get_tree().paused = false
			Game.goto("fly"), Vector2(420, 54)))
	v.add_child(UITheme.button("Options", func():
		var o := OptionsMenu.new()
		pause_ui.add_child(o), Vector2(420, 54)))
	var contested: bool = mdef.get("recover", "") == "contested" and source == "roster"
	var home := world.start_position()
	var near_home := Vector2(sim.pos.x - home.x, sim.pos.z - home.z).length() < 45.0
	var end_txt := "End mission & recover drone"
	if contested and not near_home and flight_time > 1.0:
		end_txt = "End mission - ABANDON the drone (it is far from the launch point)"
	v.add_child(UITheme.button(end_txt, func():
		get_tree().paused = false
		_end_by_menu(contested and not near_home and flight_time > 1.0), Vector2(420, 54)))
	Pad.focus_first(v, true)


func _end_by_menu(abandon: bool) -> void:
	_resume()
	if runner and runner.phase == "rtb":
		_pay_mission()
	_end_flight("MISSION ENDED" if not abandon else "DRONE ABANDONED", "You ended the flight.", "Flight ended.", false, abandon)


func _resume() -> void:
	get_tree().paused = false
	if pause_ui:
		pause_ui.get_parent().queue_free()
		pause_ui = null
	hud.show_hud = Settings.hud_on
	if state == S.CINEMATIC:
		Engine.time_scale = 0.45


func _end_intro() -> void:
	if state != S.INTRO:
		return
	hud.overlay_title = ""
	hud.overlay_sub = ""
	if mtype in ["race", "gates", "battery"]:
		state = S.COUNTDOWN
		countdown = 3.4
	else:
		state = S.FLYING
		_timer_running = true
	Audio.play("beep")


# --- per-frame ----------------------------------------------------------------------------------------------------------
func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _toast(text: String, seconds: float, color: Color = Hud.RED) -> void:
	_toasts.append({"text": text, "time": seconds, "color": color})
	if _toasts.size() > 3:
		_toasts.pop_front()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Audio.engine_level = 0.0


func _process(dt: float) -> void:
	if state == S.LOADING or world == null:
		return
	if get_tree().paused:
		return
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	_fx_time += dt
	if _rain:
		_rain.global_position = cam.global_position + Vector3(0, 6, 0) + sim.vel * 0.3
	if state == S.INTRO:
		hud.show_hud = false
		_process_intro(real_dt)
		_update_hud(dt)
		return
	if state == S.CINEMATIC:
		hud.show_hud = false
		_process_cinematic(real_dt)
		_update_hud(dt)
		return
	if state == S.FLYING and not hud.show_hud and Settings.hud_on and pause_ui == null:
		hud.show_hud = true
	if state == S.REPLAY:
		_process_replay(dt)
		return
	if state == S.RESULT:
		_update_camera(dt)
		return
	_update_camera(dt)
	_update_hud(dt)
	_update_fx()
	# audio
	var avg: float = (sim.w[0] + sim.w[1] + sim.w[2] + sim.w[3]) * 0.25
	Audio.motor_level = 0.0 if (not sim.armed and avg < 0.01) else clampf(0.25 + avg, 0.0, 1.0)
	Audio.motor_pitch = avg
	if sim.armed and Engine.get_process_frames() % 12 == 0 and avg > 0.6:
		Pad.rumble(avg * 0.12, 0.0, 0.2)
	# mouse mode
	if Settings.mouse_stick and state == S.FLYING:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process_intro(dt: float) -> void:
	_intro_t += dt
	# the drone sits on the deployment case at the launch point while the camera circles it
	drone_vis.visible = true
	drone_vis.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * VIS), sim.pos)
	var a := _intro_t * 0.6 + 0.8
	var r := lerpf(1.6, 0.6, clampf(_intro_t / 3.2, 0.0, 1.0))
	cam.global_position = sim.pos + Vector3(cos(a) * r, 0.35 + 0.4 * (1.0 - _intro_t / 3.5), sin(a) * r)
	cam.look_at(sim.pos + Vector3(0, 0.05, 0), Vector3.UP)
	cam.fov = 55.0
	fx_rect.visible = false
	if _intro_t > 3.6:
		_end_intro()


func _process_cinematic(dt: float) -> void:
	_cine_t += dt
	if _cine_target != null and is_instance_valid(_cine_target):
		var c: Vector3 = (_cine_target as CombatTarget).center()
		var a := _cine_t * 0.5 + 0.6
		var want := c + Vector3(cos(a) * 16.0, 7.0, sin(a) * 16.0)
		cam.global_position = cam.global_position.lerp(want, minf(dt * 3.0, 1.0)) if _cine_t > 0.05 else want
		cam.global_position.y = maxf(cam.global_position.y, world.top_at(cam.global_position.x, cam.global_position.z) + 2.0)
		cam.look_at(c, Vector3.UP)
		cam.fov = 55.0
	fx_rect.visible = false
	drone_vis.visible = true
	drone_vis.global_transform = Transform3D(sim.basis * Basis.from_scale(Vector3.ONE * VIS), sim.pos)
	if _cine_t > 2.8:
		Engine.time_scale = 1.0
		hud.overlay_title = ""
		hud.overlay_sub = ""
		_cine_target = null
		if _cine_then_end:
			_cine_then_end = false
			_start_replay()
		else:
			state = S.FLYING
			drone_vis.visible = false


func _update_camera(_dt: float) -> void:
	if state == S.REPLAY:
		return
	if state == S.RESULT:
		drone_vis.global_transform = Transform3D(sim.basis * Basis.from_scale(Vector3.ONE * VIS), sim.pos)
		var p := sim.pos + Vector3(2.5, 1.6, 3.0)
		cam.global_position = p
		cam.look_at(sim.pos, Vector3.UP)
		return
	match cam_mode:
		1:
			drone_vis.visible = true
			drone_vis.global_transform = Transform3D(sim.basis * Basis.from_scale(Vector3.ONE * VIS), sim.pos)
			var flat := Vector3(sim.basis.z.x, 0, sim.basis.z.z)
			if flat.length() < 0.1:
				flat = Vector3(0, 0, 1)
			var want := sim.pos + flat.normalized() * 2.2 + Vector3(0, 0.8, 0)
			cam.global_position = cam.global_position.lerp(want, minf(_dt * 6.0, 1.0))
			cam.global_position.y = maxf(cam.global_position.y, world.top_at(cam.global_position.x, cam.global_position.z) + 0.3)
			cam.look_at(sim.pos + Vector3(0, 0.2, 0), Vector3.UP)
			cam.fov = 70.0
			return
		2:
			drone_vis.visible = true
			drone_vis.global_transform = Transform3D(sim.basis * Basis.from_scale(Vector3.ONE * VIS), sim.pos)
			cam.global_position = _spectator
			if cam.global_position.distance_to(sim.pos) > 0.2:
				cam.look_at(sim.pos, Vector3.UP)
			cam.fov = clampf(2400.0 / maxf(cam.global_position.distance_to(sim.pos), 1.0), 8.0, 70.0)
			return
	drone_vis.visible = false
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(cfg["cam_angle"]))
	var jitter: float = 0.0007 * (sim.w[0] + sim.w[1] + sim.w[2] + sim.w[3]) * float(stats.get("vibration", 1.0)) * float(Settings.opt.get("cam_shake", 1.0))
	var shake := Basis.from_euler(Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter), randf_range(-jitter, jitter)))
	var b := sim.basis * tilt * shake
	cam.global_transform = Transform3D(b, sim.pos + sim.basis * CAM_OFFSET)
	cam.fov = Settings.fov + clampf(sim.speed() * 0.12, 0.0, 5.0)


func _video_degrade() -> float:
	var vr: Vector2 = VTX_RANGES[clampi(cfg["vtx_power"], 0, 2)] * float(stats.get("video_gain", 1.0))
	var d := sim.pos.distance_to(world.start_position())
	var deg := clampf((d - vr.x) / (vr.y - vr.x), 0.0, 1.0)
	deg = pow(deg, 1.2)
	# terrain and buildings between pilot and drone block the signal
	var origin := world.start_position() + Vector3(0, 4.0, 0)   # ground station antenna on a mast
	var blocked := 0.0
	for k in [0.35, 0.65]:
		var pt: Vector3 = origin.lerp(sim.pos, k)
		if world.top_at(pt.x, pt.z) > pt.y - 0.5:
			blocked += 0.2
	var jam := runner.jam_level if runner else 0.0
	return clampf(deg + blocked * clampf(d / 60.0, 0.0, 1.0) + jam * 0.9, 0.0, 1.0)


func _update_fx() -> void:
	var deg := _video_degrade()
	_deg_cache = deg
	var fpv := cam_mode == 0
	fx_mat.set_shader_parameter("degrade", deg if fpv else 0.0)
	fx_mat.set_shader_parameter("tcount", _fx_time)
	fx_mat.set_shader_parameter("static_only", 0.0 if cfg["vtx_enabled"] or not fpv else 1.0)
	fx_mat.set_shader_parameter("intensity", 1.0 if fpv else 0.0)
	fx_mat.set_shader_parameter("digital", 1.0 if stats.get("digital", false) else 0.0)
	fx_mat.set_shader_parameter("cam_noise", float(stats.get("cam_noise", 0.0)))
	# the screen-copy the shader needs costs fill-rate: on Low only pay for it once the link degrades
	fx_rect.visible = fpv and ((Settings.graphics_preset > 0 and not stats.get("digital", false)) or deg > 0.03 or not cfg["vtx_enabled"] or float(stats.get("cam_noise", 0.0)) > 0.05)
	hud.link_text = "%s VTX %s  •  %d m" % ["HD" if stats.get("digital", false) else "AN", ["25mW", "200mW", "600mW"][clampi(cfg["vtx_power"], 0, 2)], int(sim.pos.distance_to(world.start_position()))]


func _update_school(dt: float) -> void:
	if _school == null or not _school.visible:
		return
	if sim.armed:
		_school_armed_t += dt
		if _school_armed_t > 25.0:
			_school.visible = false     # fades out once the pilot is airborne for a while
			return
	var k := func(a: String) -> String: return UITheme.key_cap(Pad.glyph(a))
	var t: Array = ["[color=#52c7bd][b]FLIGHT SCHOOL[/b][/color]   %s hide" % k.call("help"), "Mode: [b]%s[/b]  (%s to change)" % [ASSIST_NAMES[assist], k.call("flight_assist")]]
	if not sim.armed:
		t.append("1. Throttle fully down, then %s to [b]arm[/b]." % k.call("arm"))
	match assist:
		0:
			t.append("Throttle %s / %s: up = climb, centre = [b]hover[/b], down = descend." % [k.call("throttle_up"), k.call("throttle_down")])
		1:
			t.append("Throttle %s / %s: about 35 %% hovers. The drone self-levels." % [k.call("throttle_up"), k.call("throttle_down")])
		2:
			t.append("ACRO: the sticks set rotation speed - nothing self-levels.")
	t.append("Pitch / roll: %s %s %s %s   Yaw: %s %s" % [k.call("pitch_forward"), k.call("pitch_back"), k.call("roll_left"), k.call("roll_right"), k.call("yaw_left"), k.call("yaw_right")])
	t.append("Camera %s   •   HUD %s   •   Pause %s" % [k.call("camera_mode"), k.call("toggle_hud"), k.call("pause")])
	if stats.get("payload_kind", "") == "drop":
		t.append("Release a pod: %s - the round reticle shows where it lands." % k.call("payload"))
	match mtype:
		"gates": t.append("Fly through the orange ring with the beam above it, then land on the pad.")
		"race": t.append("Fly the rings in order before the time runs out.")
		"strike": t.append("Find the red bracket - that's the objective. Then land back at the launch point.")
		"recon": t.append("Keep each target centred in view until its ring fills.")
	_school_lbl.text = "\n".join(t)


func _update_hud(dt: float) -> void:
	_update_school(dt)
	hud.speed_kmh = sim.speed() * 3.6
	hud.altitude = maxf(sim.pos.y - world.top_at(sim.pos.x, sim.pos.z) - DroneSim.DRONE_RADIUS, 0.0)
	hud.volts = sim.v_term
	hud.vcell = sim.v_cell()
	hud.batt_frac = clampf((sim.v_cell() - 3.2) / 1.0, 0.0, 1.0)
	hud.mah_used = sim.used_mah
	hud.soc = sim.soc()
	hud.has_current_sensor = drone.get("wires", []).has("cur")
	hud.amps_total = sim.total_amps
	hud.motor_amps = sim.amps
	hud.throttle = thr_stick
	hud.armed = sim.armed
	hud.mode_text = ASSIST_NAMES[assist] if assist < 2 else ("ACRO" if not sim.angle_mode else "ANGLE")
	hud.cam_text = "CAM %s" % CAM_NAMES[cam_mode]
	var fwd := -(sim.basis.z)
	hud.heading = fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	hud.pods_text = ("PODS %d" % pods_left) if stats.get("payload_kind", "") == "drop" else ""
	# mission lines
	var lines: Array = []
	match mtype:
		"free":
			lines = [mdef.get("name", "FREE FLIGHT").to_upper(), "Flight  %s" % _fmt(flight_time), "Best speed  %d km/h" % int(top_speed * 3.6)]
		"race", "gates":
			lines = ["%s   %s" % [mdef.get("name", "").to_upper(), _fmt(race_time)], "Gate  %d / %d" % [mini(gate_idx + 1, gates.size()), gates.size()]]
			if _need_landing:
				lines.append("Land on the pad")
			elif mission == "gate_race":
				lines.append("Par %s   Best %s" % [_fmt(par_time), _fmt(SaveData.best_time(mission)) if SaveData.best_time(mission) > 0.0 else "--"])
		"battery":
			lines = ["BATTERY CHALLENGE   %s" % _fmt(race_time), "Checkpoint  %d / %d" % [mini(route_idx + 1, route.size()), route.size()], "Used %d mAh of %d" % [int(sim.used_mah), int(sim.capacity_mah)]]
		_:
			lines = [mdef.get("name", "").to_upper()]
			lines.append_array(runner.objective_lines())
	hud.mission_lines = lines
	hud.countdown_text = ""
	if state == S.COUNTDOWN:
		hud.countdown_text = str(maxi(ceili(countdown - 0.4), 1)) if countdown > 0.4 else ""
	_update_markers()
	# warnings
	var w: Array = []
	for t in _toasts:
		t["time"] -= dt
	_toasts = _toasts.filter(func(t): return t["time"] > 0.0)
	for t in _toasts:
		w.append({"text": t["text"], "color": t["color"]})
	if state == S.FLYING:
		if not sim.armed and not sim.power_lost and cfg["rx_enabled"]:
			w.append({"text": "DISARMED - press %s to arm" % Pad.glyph("arm"), "color": Hud.AMBER, "blink": true})
		if not cfg["rx_enabled"]:
			w.append({"text": "NO RX LINK", "color": Hud.RED, "blink": true})
		elif not sim.rx_link:
			w.append({"text": "SIGNAL LOST - FAILSAFE", "color": Hud.RED, "blink": true})
		if sim.power_lost:
			w.append({"text": "POWER LOSS - BATTERY EMPTY", "color": Hud.RED, "blink": true})
		elif sim.low_voltage_warn:
			w.append({"text": "LOW BATTERY", "color": Hud.RED, "blink": true})
		if sim.limiting:
			w.append({"text": "CURRENT LIMIT", "color": Hud.AMBER})
		if runner and runner.jam_level > 0.2:
			w.append({"text": "JAMMING DETECTED", "color": Hud.RED, "blink": true})
		if not cfg["vtx_enabled"]:
			w.append({"text": "NO VIDEO - VTX UART OFF", "color": Hud.RED})
		elif _deg_cache > 0.55:
			w.append({"text": "VIDEO SIGNAL WEAK", "color": Hud.AMBER, "blink": true})
	hud.warnings = w


func _project(p: Vector3) -> Dictionary:
	var on := not cam.is_position_behind(p)
	var sp := cam.unproject_position(p) if on else Vector2.ZERO
	if on:
		# map the viewport position into the 1920x1080 HUD space
		var vs := get_viewport().get_visible_rect().size
		sp = sp * Vector2(1920.0 / vs.x, 1080.0 / vs.y)
		on = sp.x > 0 and sp.x < 1920 and sp.y > 0 and sp.y < 1080
	if not on:
		var lp := cam.global_transform.affine_inverse() * p
		var dir := Vector2(lp.x, -lp.y).normalized()
		sp = Vector2(960, 540) + dir * 420.0
	return {"p": sp, "on": on}


func _update_markers() -> void:
	var ms: Array = []
	if runner and state in [S.FLYING, S.COUNTDOWN, S.CINEMATIC]:
		for t in runner.targets:
			if t.escaped:
				continue
			var c: Vector3 = t.center()
			var dist := cam.global_position.distance_to(c)
			if dist > 1100.0 and not t.objective:
				continue
			var pr := _project(c)
			ms.append({"p": pr["p"], "on": pr["on"], "dist": dist, "name": t.title, "hp": t.hp / t.max_hp, "obj": t.objective, "scan": t.scanned, "dead": t.dead, "recon": mtype == "recon"})
		var gp: Vector3 = runner.guide_point(sim.pos)
		if gp != Vector3.INF and (runner.phase == "rtb" or mtype in ["strike", "recon"]):
			var pr2 := _project(gp + Vector3(0, 2, 0))
			var to := gp - sim.pos
			hud.guide = {"p": pr2["p"], "on": pr2["on"], "dist": to.length(), "text": "LAUNCH" if runner.phase == "rtb" else "OBJ",
				"bearing": fposmod(rad_to_deg(atan2(to.x, -to.z)), 360.0), "bearing_ok": true}
		else:
			hud.guide = {}
		if pods_left > 0 and cam_mode == 0 or (pods_left > 0 and cam_mode == 1):
			var ip := runner.predict_impact(sim)
			var pr3 := _project(ip)
			var hot := false
			for t in runner.targets:
				if not t.dead and t.distance_to_box(ip) < float(stats.get("payload_radius", 3.0)) * 0.6:
					hot = true
			hud.reticle = {"p": pr3["p"], "on": pr3["on"], "hot": hot}
		else:
			hud.reticle = {}
	hud.markers = ms
