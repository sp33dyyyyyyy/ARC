class_name FlyStage
extends Node
## FLY stage: first-person FPV flight, live power budget, missions, crash replay.

enum S { LOADING, COUNTDOWN, FLYING, REPLAY, RESULT }

const VTX_RANGES := [Vector2(40, 280), Vector2(100, 600), Vector2(180, 1000)]   # clear-until / dead-at (m)
const RX_FAILSAFE_DIST := 900.0
const REPLAY_FRAMES := 260
const CAM_OFFSET := Vector3(0, 0.02, -0.08)

var state: int = S.LOADING
var mission: String = "free_flight"

var world: FlyWorld
var sim: DroneSim
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

# crash / replay
var _rec_pos: Array = []
var _rec_basis: Array = []
var _rec_tick := 0
var _replay_pos := 0.0
var _replay_start := 0
var _replay_hold := 0.0
var _crash: Dictionary = {}
var _shards: Array = []
var _powerloss_t := 0.0
var _result_timer := -1.0
var _result_btn_back: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mission = Game.mission
	var ready: Dictionary = Game.ready_to_fly()
	if not ready["ok"]:
		Game.goto("workshop", {"stage": "build", "message": ready["reason"]})
		return
	stats = Game.stats()
	cfg = Game.cfg
	loading_label = UITheme.label("LOADING FIELD...", 40, Color.WHITE)
	var ll := CanvasLayer.new()
	ll.layer = 30
	add_child(ll)
	var bgc := ColorRect.new()
	bgc.color = Color(0.05, 0.05, 0.07)
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ll.add_child(bgc)
	loading_label.position = Vector2(760, 500)
	ll.add_child(loading_label)
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
	if mission == "gate_race":
		world.exclusions = Missions.exclusions()
	add_child(world)
	world.progress.connect(func(f: float, what: String):
		loading_label.text = "LOADING FIELD...  %s" % what
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
	sim.water_level = FlyWorld.WATER_LEVEL
	sim.water_test = world.is_water
	sim.pos = world.start_position() + Vector3(0, 0.03, 0)
	sim.rx_link = cfg["rx_enabled"]
	sim.angle_mode = cfg.get("angle_mode", false)

	drone_vis = DroneVisual.assemble(Game.placed, {})
	drone_vis.visible = false
	add_child(drone_vis)

	_build_overlay_ui()
	_build_mission()
	_update_camera(0.0)
	if mission == "free_flight":
		state = S.FLYING
	else:
		state = S.COUNTDOWN
		countdown = 3.4
	_toast("SPACE arm  •  W/S throttle  •  arrows pitch/roll  •  A/D yaw  •  V self-level mode", 7.0, Hud.WHITE)


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
	if mission == "gate_race":
		var g := Missions.gate_race(world)
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
	if mission != "free_flight":
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
	if mission == "gate_race":
		for i in gate_nodes.size():
			gate_nodes[i].material_override = _gate_mats["done"] if i < gate_idx else (_gate_mats["next"] if i == gate_idx else _gate_mats["wait"])
		if gate_idx < gates.size():
			_beam.position = gates[gate_idx]["pos"] + Vector3(0, 80, 0)
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
		if pause_ui != null:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if state == S.REPLAY and (event.is_action_pressed("arm") or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER)):
		_replay_pos = REPLAY_FRAMES + 99.0
		_replay_hold = 0.0
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
		_toast("%s mode" % ("ANGLE (self-level)" if sim.angle_mode else "ACRO (rate)"), 2.0, Hud.GREEN)
		Audio.play("beep")
	elif event.is_action_pressed("restart"):
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
	elif thr_stick > 0.06:
		_toast("Throttle must be low to arm  (S)", 2.5)
		Audio.play("error")
	else:
		sim.armed = true
		Audio.play("arm")
		_toast("ARMED", 1.5, Hud.GREEN)


func _read_controls(dt: float) -> void:
	var prec := 0.45 if Input.is_action_pressed("kb_precision") else 1.0
	thr_stick = clampf(thr_stick + Input.get_axis("throttle_down", "throttle_up") * (0.75 if _pad_active else 0.55) * dt, 0.0, 1.0)
	var yaw_t := Input.get_axis("yaw_left", "yaw_right") * prec
	var roll_t := Input.get_axis("roll_left", "roll_right") * prec
	var pitch_t := Input.get_axis("pitch_back", "pitch_forward") * prec
	if Settings.mouse_stick:
		var mp := get_viewport().get_mouse_position()
		var r := 300.0 / maxf(Settings.mouse_sens, 0.1)
		roll_t += clampf((mp.x - 960.0) / r, -1.0, 1.0)
		pitch_t += clampf(-(mp.y - 540.0) / r, -1.0, 1.0)
	roll_t = clampf(roll_t, -1.0, 1.0)
	pitch_t = clampf(pitch_t, -1.0, 1.0)
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
	if state == S.COUNTDOWN:
		countdown -= dt
		if countdown <= 0.0:
			state = S.FLYING
			_timer_running = true
			Audio.play("gate", 1.5)
			_toast("GO!", 1.2, Hud.GREEN)
		return
	if state != S.FLYING:
		return
	_read_controls(dt)
	sim.stick_throttle = thr_stick
	sim.stick_roll = roll_s
	sim.stick_pitch = pitch_s
	sim.stick_yaw = yaw_s
	var dist_h := Vector2(sim.pos.x, sim.pos.z).length()
	sim.rx_link = cfg["rx_enabled"] and dist_h < RX_FAILSAFE_DIST and absf(sim.pos.x) < FlyWorld.HALF - 4.0 and absf(sim.pos.z) < FlyWorld.HALF - 4.0
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
		if _rec_pos.size() > 420:
			_rec_pos.pop_front()
			_rec_basis.pop_front()
	if sim.impact_kind != "":
		_on_impact()
		return
	_mission_tick(prev)
	# battery flat -> glide down, then back to the workshop
	if sim.power_lost:
		_powerloss_t += dt
		var gh := world.height(sim.pos.x, sim.pos.z)
		if (sim.on_ground and sim.speed() < 1.5 and _powerloss_t > 1.0) or _powerloss_t > 25.0:
			_end_flight("BATTERY FLAT", "The pack hit its voltage cut-off and the drone lost power.", "Battery flat after %s - recharged and back at the bench." % _fmt(flight_time), false)
		elif sim.pos.y < gh - 5.0:
			_end_flight("BATTERY FLAT", "The pack hit its voltage cut-off and the drone lost power.", "Battery flat - recharged and back at the bench.", false)


func _mission_tick(prev: Vector3) -> void:
	if _ended:
		return
	if mission == "gate_race" and gate_idx < gates.size() and _timer_running:
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
				_toast("Gate %d / %d" % [gate_idx, gates.size()], 1.2, Hud.GREEN)
				_refresh_mission_markers()
				if gate_idx >= gates.size():
					_complete_mission()
		if race_time > time_limit and not _ended:
			_end_flight("TIME OVER", "You ran out of time (limit %s)." % _fmt(time_limit), "Gate race: out of time.", false)
	elif mission == "battery_challenge" and route_idx < route.size() and _timer_running:
		if sim.pos.distance_to(route[route_idx]) < route_radius:
			route_idx += 1
			Audio.play("gate")
			_toast("Checkpoint %d / %d" % [route_idx, route.size()], 1.2, Hud.GREEN)
			_refresh_mission_markers()
			if route_idx >= route.size():
				_complete_mission()


func _complete_mission() -> void:
	_ended = true
	var res := SaveData.record_run(mission, race_time, sim.used_mah)
	var lines := ["Time  %s" % _fmt(race_time)]
	if mission == "gate_race":
		lines.append("Par   %s" % _fmt(par_time))
	lines.append("Battery used  %d mAh   (%d%% left)" % [int(sim.used_mah), int(sim.soc() * 100.0)])
	if res["new_best"]:
		lines.append("NEW BEST TIME!")
	if not res["unlocked"].is_empty():
		var names: Array = []
		for id in res["unlocked"]:
			names.append(Parts.part(id)["name"])
		lines.append("Unlocked: " + ", ".join(names))
	Audio.play("success")
	_show_result("%s COMPLETE" % Parts.MISSION_NAMES[mission].to_upper(), lines, true, false)


# --- crash & replay ------------------------------------------------------------------------------------------
func _on_impact() -> void:
	var kind := sim.impact_kind
	var speed := sim.impact_speed
	var n := sim.impact_normal
	var broken_now: Array = []
	if kind != "water" or speed > DroneSim.CRASH_SPEED:
		var count := clampi(1 + int((speed - DroneSim.CRASH_SPEED) / 3.5), 1, 4)
		var ranked: Array = []
		for i in 4:
			var mp: Vector2 = sim.motor_pos[i]
			var dir := (sim.basis * Vector3(mp.x, 0, mp.y)).normalized()
			ranked.append([dir.dot(-n) + randf() * 0.05, i])
		ranked.sort_custom(func(a, b): return a[0] > b[0])
		for k in count:
			var slot := "prop_%d" % (ranked[k][1] + 1)
			Game.broken[slot] = true
			broken_now.append(slot)
	Game.save_drone()
	var place: String = {"ground": "the ground", "tree": "a tree", "water": "the lake"}.get(kind, "something")
	var kmh := int(speed * 3.6)
	var text := "Hit %s at %d km/h." % [place, kmh]
	if kind == "water" and broken_now.is_empty():
		text = "Splashdown! The drone was fished out of the lake."
	elif not broken_now.is_empty():
		text += "  %d prop%s broke." % [broken_now.size(), "" if broken_now.size() == 1 else "s"]
	_crash = {"text": text, "broken": broken_now, "pos": sim.impact_point, "normal": n, "kind": kind}
	Audio.play("crash")
	Audio.motor_level = 0.0
	_ended = true
	_start_replay()


func _start_replay() -> void:
	state = S.REPLAY
	_replay_start = maxi(0, _rec_pos.size() - REPLAY_FRAMES)
	_replay_pos = float(_replay_start)
	_replay_hold = 0.0
	hud.show_hud = false
	hud.warnings = []
	hud.overlay_title = "REPLAY"
	hud.overlay_sub = "Enter / Space: skip"
	drone_vis.visible = true
	fx_mat.set_shader_parameter("intensity", 0.0)
	cam.fov = 70.0


func _process_replay(dt: float) -> void:
	_replay_pos += dt * 60.0 * 0.55
	var last := _rec_pos.size() - 1
	if _replay_pos >= last:
		_replay_pos = last
		if _replay_hold == 0.0:
			_spawn_shards()
			_swap_broken_visual()
		_replay_hold += dt
	var i0 := clampi(int(_replay_pos), 0, last)
	var i1 := mini(i0 + 1, last)
	var f := _replay_pos - float(i0)
	var p: Vector3 = (_rec_pos[i0] as Vector3).lerp(_rec_pos[i1], f)
	var b: Basis = (_rec_basis[i0] as Basis).slerp(_rec_basis[i1], f)
	drone_vis.global_transform = Transform3D(b * Basis.from_scale(Vector3.ONE * 0.03), p)
	# chase camera: behind the direction of travel, a little above
	var back_i := maxi(i0 - 10, 0)
	var travel: Vector3 = p - (_rec_pos[back_i] as Vector3)
	if travel.length() < 0.2:
		travel = Vector3(0, 0, -1)
	travel = travel.normalized()
	var want := p - travel * 4.5 + Vector3(0, 1.8, 0)
	cam.global_position = cam.global_position.lerp(want, minf(dt * 4.0, 1.0)) if _replay_pos > _replay_start + 1 else want
	var gh := world.height(cam.global_position.x, cam.global_position.z) + 0.6
	cam.global_position.y = maxf(cam.global_position.y, gh)
	cam.look_at(p, Vector3.UP)
	# shards
	for s in _shards:
		s["v"].y -= 9.81 * dt
		s["n"].position += s["v"] * dt
		s["n"].rotation += s["spin"] * dt
	if _replay_hold > 1.6 or (_replay_pos >= _replay_start + REPLAY_FRAMES + 50):
		hud.overlay_title = ""
		hud.overlay_sub = ""
		_end_flight("CRASHED", _crash["text"], _workshop_crash_message(), true)


func _workshop_crash_message() -> String:
	var t: String = _crash["text"]
	if not _crash["broken"].is_empty():
		t += "  Scrap the broken props and fit fresh ones."
	return t


func _swap_broken_visual() -> void:
	var t := drone_vis.global_transform
	drone_vis.queue_free()
	drone_vis = DroneVisual.assemble(Game.placed, Game.broken)
	add_child(drone_vis)
	drone_vis.global_transform = t


func _spawn_shards() -> void:
	for k in range(_crash["broken"].size() * 3):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.012, 0.025)
		mi.mesh = bm
		mi.material_override = MeshFactory.mat(Color(1.0, 0.85, 0.0), 0.0, 0.4, 0.3)
		add_child(mi)
		mi.global_position = _crash["pos"] + Vector3(0, 0.1, 0)
		var v := Vector3(randf_range(-1, 1), randf_range(1.0, 3.5), randf_range(-1, 1)) * 1.5
		_shards.append({"n": mi, "v": v, "spin": Vector3(randf() * 20, randf() * 20, randf() * 20)})


func _end_flight(title: String, sub: String, workshop_msg: String, crashed: bool) -> void:
	if state == S.RESULT:
		return
	_ended = true
	state = S.RESULT
	drone_vis.visible = true
	var lines := [sub, "", "Flight time  %s     Top speed  %d km/h" % [_fmt(flight_time), int(top_speed * 3.6)], "Battery used  %d mAh" % int(sim.used_mah)]
	if crashed and not _crash["broken"].is_empty():
		lines.append("Broken: " + ", ".join(_crash["broken"]).replace("prop_", "prop "))
	SaveData.note_speed(top_speed * 3.6)
	Game.last_result = {"msg": workshop_msg}
	_show_result(title, lines, false, crashed, workshop_msg)
	_result_timer = 9.0


# --- result / pause UI --------------------------------------------------------------------------------------------
func _show_result(title: String, lines: Array, success: bool, crashed: bool, msg: String = "") -> void:
	state = S.RESULT
	_ended = true
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
	p.custom_minimum_size = Vector2(820, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var col := UITheme.GOOD if success else (UITheme.BAD if crashed else UITheme.ACCENT)
	v.add_child(UITheme.label(title, 44, col))
	for l in lines:
		var lab := UITheme.label(l, 22)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lab)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var message := msg
	if message == "":
		message = "Back at the bench." if not success else "Great flying!"
	_result_btn_back = UITheme.accent_button("BACK TO WORKSHOP", func(): _go_workshop(message), Vector2(300, 56))
	h.add_child(_result_btn_back)
	if not crashed and Game.stats()["broken_props"] == 0:
		h.add_child(UITheme.button("Fly again", func(): Game.goto("fly"), Vector2(200, 56)))


func _go_workshop(msg: String) -> void:
	Game.save_drone()
	var stage := "build" if Game.stats()["broken_props"] > 0 else "setup"
	Game.goto("workshop", {"stage": stage, "message": msg})


func _pause() -> void:
	if state == S.REPLAY or state == S.RESULT:
		return
	get_tree().paused = true
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
	v.add_child(UITheme.accent_button("Resume", _resume, Vector2(360, 54)))
	v.add_child(UITheme.button("Restart", func():
		get_tree().paused = false
		Game.goto("fly"), Vector2(360, 54)))
	v.add_child(UITheme.button("Options", func():
		var o := OptionsMenu.new()
		pause_ui.add_child(o), Vector2(360, 54)))
	v.add_child(UITheme.button("Return to workshop", func():
		get_tree().paused = false
		_go_workshop("Back at the bench."), Vector2(360, 54)))
	v.add_child(UITheme.button("Main menu", func():
		get_tree().paused = false
		Game.goto("menu"), Vector2(360, 54)))


func _resume() -> void:
	get_tree().paused = false
	if pause_ui:
		pause_ui.get_parent().queue_free()
		pause_ui = null
	hud.show_hud = Settings.hud_on


# --- per-frame ----------------------------------------------------------------------------------------------------------
func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _toast(text: String, seconds: float, color: Color = Hud.RED) -> void:
	_toasts.append({"text": text, "time": seconds, "color": color})
	if _toasts.size() > 3:
		_toasts.pop_front()


func _process(dt: float) -> void:
	if state == S.LOADING or world == null:
		return
	if get_tree().paused:
		return
	_fx_time += dt
	if state == S.REPLAY:
		_process_replay(dt)
		return
	if state == S.RESULT:
		if _result_timer > 0.0:
			_result_timer -= dt
			if _result_timer <= 0.0 and result_ui:
				_result_btn_back.pressed.emit()
		_update_camera(dt)
		return
	_update_camera(dt)
	_update_hud(dt)
	_update_fx()
	# audio
	var avg: float = (sim.w[0] + sim.w[1] + sim.w[2] + sim.w[3]) * 0.25
	Audio.motor_level = 0.0 if (not sim.armed and avg < 0.01) else clampf(0.25 + avg, 0.0, 1.0)
	Audio.motor_pitch = avg
	# mouse mode
	if Settings.mouse_stick and state == S.FLYING:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_camera(_dt: float) -> void:
	if state == S.REPLAY:
		return
	if state == S.RESULT:
		# hover over the wreck
		drone_vis.global_transform = Transform3D(sim.basis * Basis.from_scale(Vector3.ONE * 0.03), sim.pos)
		var p := sim.pos + Vector3(2.5, 1.6, 3.0)
		cam.global_position = p
		cam.look_at(sim.pos, Vector3.UP)
		return
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(cfg["cam_angle"]))
	var jitter: float = 0.0007 * (sim.w[0] + sim.w[1] + sim.w[2] + sim.w[3])
	var shake := Basis.from_euler(Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter), randf_range(-jitter, jitter)))
	var b := sim.basis * tilt * shake
	cam.global_transform = Transform3D(b, sim.pos + sim.basis * CAM_OFFSET)
	cam.fov = Settings.fov + clampf(sim.speed() * 0.12, 0.0, 5.0)


func _video_degrade() -> float:
	var vr: Vector2 = VTX_RANGES[clampi(cfg["vtx_power"], 0, 2)]
	var d := Vector2(sim.pos.x, sim.pos.z).distance_to(Vector2.ZERO)
	d = sim.pos.distance_to(world.start_position())
	var deg := clampf((d - vr.x) / (vr.y - vr.x), 0.0, 1.0)
	deg = pow(deg, 1.2)
	# terrain between pilot and drone blocks the signal
	var origin := world.start_position() + Vector3(0, 1.7, 0)
	var blocked := 0.0
	for k in [0.35, 0.65]:
		var pt: Vector3 = origin.lerp(sim.pos, k)
		if world.height(pt.x, pt.z) > pt.y - 0.5:
			blocked += 0.3
	return clampf(deg + blocked * clampf(d / 60.0, 0.0, 1.0), 0.0, 1.0)


func _update_fx() -> void:
	var deg := _video_degrade()
	_deg_cache = deg
	fx_mat.set_shader_parameter("degrade", deg)
	fx_mat.set_shader_parameter("tcount", _fx_time)
	fx_mat.set_shader_parameter("static_only", 0.0 if cfg["vtx_enabled"] else 1.0)
	fx_mat.set_shader_parameter("intensity", 1.0)
	# the screen-copy the shader needs costs fill-rate: on Low only pay for it once the link degrades
	fx_rect.visible = (Settings.graphics_preset > 0) or deg > 0.03 or not cfg["vtx_enabled"]
	hud.link_text = "VTX %s  •  %d m" % [["25mW", "200mW", "600mW"][clampi(cfg["vtx_power"], 0, 2)], int(sim.pos.distance_to(world.start_position()))]


func _update_hud(dt: float) -> void:
	hud.speed_kmh = sim.speed() * 3.6
	hud.altitude = maxf(sim.pos.y - world.height(sim.pos.x, sim.pos.z) - DroneSim.DRONE_RADIUS, 0.0)
	hud.volts = sim.v_term
	hud.vcell = sim.v_cell()
	hud.batt_frac = clampf((sim.v_cell() - 3.2) / 1.0, 0.0, 1.0)
	hud.mah_used = sim.used_mah
	hud.soc = sim.soc()
	hud.has_current_sensor = Game.wires.has("cur")
	hud.amps_total = sim.total_amps
	hud.motor_amps = sim.amps
	hud.throttle = thr_stick
	hud.armed = sim.armed
	hud.mode_text = "ANGLE" if sim.angle_mode else "ACRO"
	# mission lines
	var lines: Array = []
	if mission == "free_flight":
		lines = ["FREE FLIGHT", "Flight  %s" % _fmt(flight_time), "Best speed  %d km/h" % int(top_speed * 3.6)]
	elif mission == "gate_race":
		lines = ["GATE RACE   %s" % _fmt(race_time), "Gate  %d / %d" % [mini(gate_idx + 1, gates.size()), gates.size()], "Par %s   Best %s" % [_fmt(par_time), _fmt(SaveData.best_time(mission)) if SaveData.best_time(mission) > 0.0 else "--"]]
	else:
		lines = ["BATTERY CHALLENGE   %s" % _fmt(race_time), "Checkpoint  %d / %d" % [mini(route_idx + 1, route.size()), route.size()], "Used %d mAh of %d" % [int(sim.used_mah), int(sim.capacity_mah)]]
	hud.mission_lines = lines
	hud.countdown_text = ""
	if state == S.COUNTDOWN:
		hud.countdown_text = str(maxi(ceili(countdown - 0.4), 1)) if countdown > 0.4 else ""
	# warnings
	var w: Array = []
	for t in _toasts:
		t["time"] -= dt
	_toasts = _toasts.filter(func(t): return t["time"] > 0.0)
	for t in _toasts:
		w.append({"text": t["text"], "color": t["color"]})
	if state == S.FLYING:
		if not sim.armed and not sim.power_lost and cfg["rx_enabled"]:
			w.append({"text": "DISARMED - press SPACE to arm", "color": Hud.AMBER, "blink": true})
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
		if not cfg["vtx_enabled"]:
			w.append({"text": "NO VIDEO - VTX UART OFF", "color": Hud.RED})
		elif _deg_cache > 0.55:
			w.append({"text": "VIDEO SIGNAL WEAK", "color": Hud.AMBER, "blink": true})
	hud.warnings = w
