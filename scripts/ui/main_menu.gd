class_name MainMenu
extends Node
## Title screen with a slowly turning showcase drone.

var _drone: Node3D
var _status: Label
var _t := 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.16, 0.12, 0.3)
	psm.sky_horizon_color = Color(1.0, 0.55, 0.38)
	psm.ground_horizon_color = Color(0.9, 0.45, 0.35)
	psm.ground_bottom_color = Color(0.12, 0.08, 0.12)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -35, 0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 38
	add_child(cam)
	cam.position = Vector3(0, 11, 34)
	cam.look_at(Vector3(5, 2.5, 0))
	Settings.apply_to_viewport(get_viewport())

	var placed: Dictionary = Game.placed if Game.placed.has("frame") and Game.stats()["complete"] else DroneVisual.default_placement()
	_drone = DroneVisual.assemble(placed, {})
	_drone.position = Vector3(7, 0, 0)
	_drone.scale = Vector3.ONE * 0.62
	_drone.rotation_degrees = Vector3(18, 0, 0)
	add_child(_drone)

	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := UITheme.root_control()
	layer.add_child(ui)

	var left := VBoxContainer.new()
	left.position = Vector2(110, 120)
	left.add_theme_constant_override("separation", 14)
	ui.add_child(left)
	left.add_child(UITheme.label("PROPWASH", 96, Color.WHITE))
	var sub := UITheme.label("W O R K S H O P", 44, UITheme.ACCENT)
	left.add_child(sub)
	left.add_child(UITheme.label("Build.  Wire.  Tune.  Fly.", 24, UITheme.MUTED))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	left.add_child(sp)

	var has_build: bool = Game.placed.has("frame")
	left.add_child(UITheme.accent_button("ENTER WORKSHOP" if not has_build else "CONTINUE WORKSHOP", func(): Game.goto("workshop", {"stage": "build"}), Vector2(420, 62)))
	var ready: Dictionary = Game.ready_to_fly()
	var fly := UITheme.button("QUICK TO SETUP & FLY", func(): Game.goto("workshop", {"stage": "setup"}), Vector2(420, 54))
	fly.disabled = not ready["ok"]
	if not ready["ok"]:
		fly.tooltip_text = ready["reason"]
	left.add_child(fly)
	left.add_child(UITheme.button("NEW DRONE (clear build)", func():
		Game.reset_build()
		Game.cfg = Game.default_cfg()
		Game.save_drone()
		Game.goto("menu"), Vector2(420, 54)))
	left.add_child(UITheme.button("OPTIONS", _open_options, Vector2(420, 54)))
	left.add_child(UITheme.button("QUIT", func(): get_tree().quit(), Vector2(420, 54)))

	_status = UITheme.label(_status_text(), 20, UITheme.MUTED)
	_status.position = Vector2(110, 900)
	ui.add_child(_status)
	var hint := UITheme.label("F11 fullscreen   •   All controls are rebindable in OPTIONS", 18, UITheme.MUTED)
	hint.position = Vector2(110, 1020)
	ui.add_child(hint)

	# Records panel
	var panel := PanelContainer.new()
	panel.position = Vector2(1330, 90)
	panel.custom_minimum_size = Vector2(500, 0)
	ui.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	panel.add_child(pv)
	pv.add_child(UITheme.label("PILOT LOG", 26, UITheme.ACCENT))
	for m in ["gate_race", "battery_challenge"]:
		var bt := SaveData.best_time(m)
		pv.add_child(UITheme.label("%s   %s" % [Parts.MISSION_NAMES[m], "—" if bt <= 0.0 else _fmt(bt)], 21))
	pv.add_child(UITheme.label("Top speed   %.0f km/h" % float(SaveData.data["top_speed_kmh"]), 21))
	var total := Parts.db().size()
	pv.add_child(UITheme.label("Parts unlocked   %d / %d" % [SaveData.data["unlocked"].size(), total], 21))
	var tip := UITheme.label("Finish Gate Race: 3\" whoop, 2207 motors, 5040 props, 2200 mAh pack.\nFinish Battery Challenge: 7\" frame, 2806 motors.", 17, UITheme.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(470, 0)
	pv.add_child(tip)


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _status_text() -> String:
	var s: Dictionary = Game.stats()
	if not Game.placed.has("frame"):
		return "No drone yet - head to the workshop bench."
	if not s["complete"]:
		return "Drone in progress: missing %s." % s["missing_text"]
	var r: Dictionary = Game.ready_to_fly()
	return "Drone: %s · %s · %s · %s · %.0f g — %s" % [s["frame_name"], s["motor_name"], s["prop_name"], s["battery_name"], s["mass_g"],
		"ready to fly" if r["ok"] else r["reason"]]


func _open_options() -> void:
	var o := OptionsMenu.new()
	get_node("CanvasLayer2").add_child(o) if has_node("CanvasLayer2") else _add_overlay(o)


func _add_overlay(o: Control) -> void:
	var l := CanvasLayer.new()
	l.layer = 50
	add_child(l)
	l.add_child(o)
	o.closed.connect(func(): l.queue_free())


func _process(dt: float) -> void:
	_t += dt
	if _drone:
		_drone.rotation.y += dt * 0.35
		_drone.position.y = 3.0 + sin(_t * 1.3) * 0.6
