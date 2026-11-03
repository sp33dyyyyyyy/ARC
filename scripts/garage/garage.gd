class_name Garage
extends Node
## The walkable home garage / drone factory hub. Builds the room, the outdoor lot and
## every piece of interactive equipment, runs deliveries, and hands off to the workbench,
## the Workshop OS computer, the test station and deployment.

const IN_MIN := Vector3(-5.0, -0.5, -6.0)
const IN_MAX := Vector3(5.0, 3.2, 4.0)
const DOOR_W := 5.0
const DOOR_H := 2.5
const BENCH_POS := Vector3(0, 0, -5.52)
const DROP_POS := Vector3(0.9, 0.0, 7.6)

var spawn := "door"
var message := ""

var world: Node3D
var player: GaragePlayer
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var tube_lights: Array = []
var lights_on := true
var door: Node3D
var door_body: AnimatableBody3D
var door_open := false
var _door_tw: Tween
var bench: Dictionary
var drawer_open: Array = [false, false, false]
var cupboard_open: Array = [false, false]
var desk: Dictionary
var rack: Dictionary
var rack_items: Dictionary = {}       # drone id -> Interactable
var charger: Dictionary
var dock_items: Array = []            # per dock: Interactable
var dock_models: Array = []           # per dock: Node3D battery model or null
var dock_labels: Array = []
var test_station: Dictionary
var test_item: Interactable
var printer: Dictionary
var case_: Dictionary
var assembly: Dictionary
var shelf_labels: Array = []
var pickables: Array = []
var _roster_sig := ""

# delivery van
var van: Node3D
var _van_order: Dictionary = {}
var _van_busy := false

# UI
var ui: Control
var _prompt: RichTextLabel
var _cap_re := RegEx.create_from_string("\\[([^\\]\\n]{1,14})\\]")
var _crosshair: Control
var _info: RichTextLabel
var _guide: Label
var _guide_title: Label
var _guide_card: PanelContainer
var _guide_bar: ProgressBar
var _beacon: Node3D
var _beacon_label: Label3D
var _held_lbl: Label
var _toasts: VBoxContainer
var overlay: Control = null
var _overlay_layer: CanvasLayer
var _overlay_root: Control
var _fade: ColorRect
var _busy := false   # transitions
var _loaded := false
var _loading: LoadingScreen
var _built_level := 1


func _ready() -> void:
	_built_level = Career.level()
	world = Node3D.new()
	world.name = "GarageWorld"
	add_child(world)
	_build_ui()
	_loading = LoadingScreen.new()
	_loading.title = "THE GARAGE"
	_fade.get_parent().add_child(_loading)
	# built over several frames; each step is logged so a crash on a particular PC can be located in godot.log
	for step in [["environment", _build_environment], ["room", _build_room], ["outside", _build_outside],
			["equipment", _build_equipment], ["items", _spawn_pickables]]:
		print("[garage] building %s" % step[0])
		_loading.set_progress(float(["environment", "room", "outside", "equipment", "items"].find(step[0])) / 5.0, "Setting up the %s..." % step[0])
		await get_tree().process_frame
		if not is_inside_tree():
			return
		(step[1] as Callable).call()
	print("[garage] player + ui")
	player = GaragePlayer.new()
	world.add_child(player)
	_place_player()
	player.hover_changed.connect(func(_h): _update_prompt())
	Career.notify.connect(_on_notify)
	Career.changed.connect(_on_career_changed)
	lights_on = Career.data["layout"].get("lights_on", true)
	_set_lights(lights_on, false)
	_set_door(Career.data["layout"].get("door_open", false), false)
	Settings.apply_to_viewport(get_viewport())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_time_of_day()
	_sync_rack()
	_loaded = true
	_loading.finish()
	print("[garage] ready")
	_fade_in()
	_maybe_tutorial()
	if message != "":
		_on_notify(message, "info")


## Called by main.gd just before the screen is swapped (children are still in the tree).
func before_exit() -> void:
	if not _loaded:
		Career.save()
		return
	_save_layout()
	Career.save()
	Audio.engine_level = 0.0


# =====================================================================================
# world
# =====================================================================================
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.7, 0.72, 0.75)
	env.glow_enabled = Settings.quality()["glow"]
	env.glow_intensity = 0.4
	Settings.apply_env(env)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Settings.quality()["shadows"]
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.04
	world.add_child(sun)


func _update_time_of_day() -> void:
	var mins := float(Career.data["clock"])
	var h := mins / 60.0
	var day := clampf(sin((h - 6.0) / 14.0 * PI), -1.0, 1.0)     # >0 between 06:00 and 20:00
	var elev := lerpf(-10.0, 62.0, clampf(day, 0.0, 1.0))
	sun.rotation_degrees = Vector3(-maxf(elev, 3.0), -35.0 + (h - 13.0) * 12.0, 0)
	var dusk := 1.0 - clampf(day * 3.0, 0.0, 1.0)
	sun.light_energy = clampf(day * 1.6, 0.0, 1.25)
	sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.58, 0.35), dusk)
	var night := clampf(-day * 2.5 + 0.15, 0.0, 1.0)
	sky_mat.sky_top_color = Color(0.25, 0.42, 0.72).lerp(Color(0.25, 0.2, 0.42), dusk).lerp(Color(0.02, 0.03, 0.07), night)
	sky_mat.sky_horizon_color = Color(0.7, 0.78, 0.86).lerp(Color(1.0, 0.56, 0.42), dusk).lerp(Color(0.05, 0.06, 0.1), night)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.18, 0.17, 0.16).lerp(Color(0.02, 0.02, 0.03), night)
	env.ambient_light_energy = lerpf(0.42, 0.08, night)
	env.fog_light_color = sky_mat.sky_horizon_color


func _build_room() -> void:
	var floor_m := GarageKit.concrete(Vector2(5, 5))
	GarageKit.block(world, Vector3(10.4, 0.2, 10.4), Vector3(0, -0.1, -1.0), floor_m)
	var wall := GarageKit.block_wall(Vector2(4, 1.2))
	# back, left, right walls
	GarageKit.block(world, Vector3(10.4, 3.2, 0.2), Vector3(0, 1.6, -6.1), wall)
	GarageKit.block(world, Vector3(0.2, 3.2, 10.2), Vector3(-5.1, 1.6, -1.0), wall)
	GarageKit.block(world, Vector3(0.2, 3.2, 10.2), Vector3(5.1, 1.6, -1.0), wall)
	# front wall segments + lintel around the door opening
	var seg := (10.4 - DOOR_W) * 0.5
	GarageKit.block(world, Vector3(seg, 3.2, 0.2), Vector3(-DOOR_W * 0.5 - seg * 0.5, 1.6, 4.1), wall)
	GarageKit.block(world, Vector3(seg, 3.2, 0.2), Vector3(DOOR_W * 0.5 + seg * 0.5, 1.6, 4.1), wall)
	GarageKit.block(world, Vector3(DOOR_W, 3.2 - DOOR_H, 0.2), Vector3(0, DOOR_H + (3.2 - DOOR_H) * 0.5, 4.1), wall)
	# ceiling + roof
	GarageKit.block(world, Vector3(10.4, 0.15, 10.4), Vector3(0, 3.27, -1.0), GarageKit.m(Color(0.72, 0.72, 0.7), 0.0, 0.95))
	GarageKit.box(world, Vector3(11.2, 0.25, 11.0), Vector3(0, 3.48, -1.0), GarageKit.m(Color(0.3, 0.2, 0.17), 0.1, 0.8))
	# skirting stripe + floor safety tape
	var yel := GarageKit.m(Color(0.95, 0.75, 0.1), 0.0, 0.6)
	GarageKit.box(world, Vector3(5.0, 0.004, 0.08), Vector3(0, 0.003, 3.3), yel)
	for x in [-2.5, 2.5]:
		GarageKit.box(world, Vector3(0.08, 0.004, 2.0), Vector3(x, 0.003, 2.3), yel)
	# door tracks
	var dark := GarageKit.m(Color(0.25, 0.25, 0.27), 0.6, 0.4)
	for x in [-DOOR_W * 0.5 - 0.06, DOOR_W * 0.5 + 0.06]:
		GarageKit.box(world, Vector3(0.06, DOOR_H, 0.08), Vector3(x, DOOR_H * 0.5, 3.92), dark)
		GarageKit.box(world, Vector3(0.06, 0.08, 3.2), Vector3(x, DOOR_H + 0.15, 2.4), dark)
	# lights
	var safe: bool = Settings.quality()["safe"]
	var light_spots := [Vector3(0, 3.15, -3.4), Vector3(0, 3.15, 1.0)] if safe else [Vector3(-2.4, 3.15, -3.8), Vector3(2.4, 3.15, -3.8), Vector3(-2.4, 3.15, 0.6), Vector3(2.4, 3.15, 0.6)]
	for p in light_spots:
		var tl := GarageKit.tube_light(world, p)
		(tl["light"] as OmniLight3D).shadow_enabled = false
		if safe:
			(tl["light"] as OmniLight3D).omni_range = 9.0
		tube_lights.append(tl)
	if Career.level() >= 4 and not safe:
		for p in [Vector3(0, 3.1, -1.6)]:
			var tl := GarageKit.tube_light(world, p)
			(tl["light"] as OmniLight3D).light_energy = 2.0
			tube_lights.append(tl)
	# garage door
	door = GarageKit.garage_door(DOOR_W, DOOR_H)
	door.position = Vector3(0, 0, 3.97)
	world.add_child(door)
	door_body = AnimatableBody3D.new()
	door_body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(DOOR_W, DOOR_H, 0.08)
	cs.shape = bs
	cs.position = Vector3(0, DOOR_H * 0.5, 0)
	door_body.add_child(cs)
	door.add_child(door_body)
	var door_it := Interactable.make(door, Vector3(DOOR_W, DOOR_H, 0.1), Vector3(0, DOOR_H * 0.5, -0.05), "Garage door",
		func() -> String: return "Close garage door" if door_open else "Open garage door", func(_p): toggle_door())
	door_it.highlight_root = door
	# light switch / door controls on the front wall (inside)
	var sw := Node3D.new()
	sw.position = Vector3(-3.4, 1.3, 3.98)
	world.add_child(sw)
	GarageKit.box(sw, Vector3(0.09, 0.13, 0.02), Vector3.ZERO, GarageKit.m(Color(0.92, 0.92, 0.9), 0.0, 0.5))
	var rocker := GarageKit.box(sw, Vector3(0.03, 0.06, 0.02), Vector3(0, 0, -0.015), GarageKit.m(Color(0.8, 0.8, 0.78), 0.0, 0.5))
	rocker.name = "Rocker"
	var sw_it := Interactable.make(sw, Vector3(0.14, 0.18, 0.06), Vector3(0, 0, -0.02), "Light switch",
		func() -> String: return "Lights off" if lights_on else "Lights on", func(_p): _set_lights(not lights_on, true))
	sw_it.highlight_root = sw
	GarageKit.label(sw, "LIGHTS", 22, Vector3(0, 0.12, -0.012), Color(0.2, 0.2, 0.2), PI)
	var dc := Node3D.new()
	dc.position = Vector3(3.3, 1.3, 3.98)
	world.add_child(dc)
	GarageKit.box(dc, Vector3(0.12, 0.2, 0.04), Vector3.ZERO, GarageKit.m(Color(0.2, 0.2, 0.22), 0.3, 0.5))
	GarageKit.box(dc, Vector3(0.05, 0.05, 0.02), Vector3(0, 0.04, -0.025), GarageKit.m(Color(0.1, 0.8, 0.2), 0.0, 0.4, 1.0))
	GarageKit.box(dc, Vector3(0.05, 0.05, 0.02), Vector3(0, -0.04, -0.025), GarageKit.m(Color(0.85, 0.1, 0.1), 0.0, 0.4, 1.0))
	var dc_it := Interactable.make(dc, Vector3(0.16, 0.24, 0.08), Vector3(0, 0, -0.03), "Door control",
		func() -> String: return "Close garage door" if door_open else "Open garage door", func(_p): toggle_door())
	dc_it.highlight_root = dc
	GarageKit.label(dc, "DOOR", 22, Vector3(0, 0.15, -0.025), Color(0.85, 0.85, 0.85), PI)
	# decoration with a function: posters / sign
	GarageKit.label(world, "KALVARIAN VOLUNTEER WORKSHOP", 64, Vector3(0, 2.75, -5.99), Color(1.0, 0.65, 0.2))
	GarageKit.label(world, "LEVEL %d - %s" % [Career.level(), Career.level_info()["name"].to_upper()], 40, Vector3(0, 2.55, -5.99), Color(0.85, 0.85, 0.85))
	_build_details()
	# a few non-functional props for atmosphere (bin, extinguisher)
	GarageKit.cyl(world, 0.22, 0.6, Vector3(4.5, 0.3, 3.4), GarageKit.m(Color(0.2, 0.35, 0.25), 0.2, 0.6))
	GarageKit.solid(world, Vector3(0.44, 0.6, 0.44), Vector3(4.5, 0.3, 3.4))
	GarageKit.cyl(world, 0.08, 0.5, Vector3(4.9, 0.55, 2.8), GarageKit.m(Color(0.8, 0.05, 0.05), 0.2, 0.4))


func _build_outside() -> void:
	# driveway, lawn, road, neighbours, fence
	GarageKit.block(world, Vector3(6.0, 0.1, 13.0), Vector3(0, -0.05, 10.6), GarageKit.concrete(Vector2(3, 6)))
	GarageKit.block(world, Vector3(60.0, 0.1, 30.0), Vector3(0, -0.11, 10.0), GarageKit.grass())
	# the wider neighbourhood: fields, distant tree lines and roofs so the horizon isn't empty
	GarageKit.box(world, Vector3(700.0, 0.1, 700.0), Vector3(0, -0.2, 0.0), GarageKit.grass(Vector2(80, 80)))
	var far_tree := GarageKit.m(Color(0.16, 0.28, 0.13), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(45.0, 160.0)
		var tp := Vector3(cos(a) * r, 0, sin(a) * r)
		if tp.z > 14.0 and tp.z < 28.0:
			continue
		var h := rng.randf_range(5.0, 11.0)
		MeshFactory.cyl(world, h * 0.35, h, tp + Vector3(0, h * 0.5, 0), far_tree, Vector3.ZERO, 6, 0.0)
	for i in 9:
		var hx := -70.0 + i * 18.0
		var col := Color.from_hsv(rng.randf_range(0.04, 0.1), 0.25, rng.randf_range(0.6, 0.8))
		GarageKit.box(world, Vector3(10, 5.5, 9), Vector3(hx, 2.75, 34.0), GarageKit.m(col, 0.0, 0.9))
		GarageKit.box(world, Vector3(10.6, 1.6, 9.6), Vector3(hx, 6.2, 34.0), GarageKit.m(Color(0.32, 0.16, 0.12), 0.0, 0.8))
	GarageKit.block(world, Vector3(160.0, 0.1, 7.0), Vector3(0, -0.04, 20.5), GarageKit.asphalt(Vector2(30, 1.5)))
	for z in [17.4, 23.6]:
		GarageKit.block(world, Vector3(160.0, 0.14, 0.4), Vector3(0, 0.0, z), GarageKit.concrete(Vector2(40, 0.2)))
	var white := GarageKit.m(Color(0.9, 0.9, 0.85), 0.0, 0.6)
	for i in 24:
		GarageKit.box(world, Vector3(2.0, 0.005, 0.12), Vector3(-70 + i * 6.0, 0.015, 20.5), white)
	# the house next to the garage
	var house := GarageKit.block_wall(Vector2(3, 1))
	GarageKit.block(world, Vector3(9.0, 5.6, 9.0), Vector3(10.0, 2.8, -1.5), GarageKit.m(Color(0.75, 0.7, 0.62), 0.0, 0.9))
	GarageKit.box(world, Vector3(9.8, 0.4, 9.8), Vector3(10.0, 5.8, -1.5), GarageKit.m(Color(0.35, 0.18, 0.14), 0.0, 0.8))
	for wx in [7.5, 10.0, 12.5]:
		for wy in [1.6, 4.0]:
			GarageKit.box(world, Vector3(1.0, 1.1, 0.05), Vector3(wx, wy, 3.02), GarageKit.m(Color(0.25, 0.32, 0.4), 0.5, 0.15, 0.25 if wy > 3.0 else 0.0))
	GarageKit.box(world, Vector3(1.0, 2.1, 0.05), Vector3(13.6, 1.05, 3.02), GarageKit.m(Color(0.32, 0.18, 0.1), 0.0, 0.7))
	var fence := GarageKit.m(Color(0.42, 0.3, 0.2), 0.0, 0.85)
	for z in range(-8, 17, 2):
		GarageKit.box(world, Vector3(0.08, 1.2, 0.08), Vector3(-18, 0.6, z), fence)
		GarageKit.box(world, Vector3(0.08, 1.2, 0.08), Vector3(26, 0.6, z), fence)
	GarageKit.box(world, Vector3(0.05, 0.1, 25.0), Vector3(-18, 1.0, 4.0), fence)
	GarageKit.box(world, Vector3(0.05, 0.1, 25.0), Vector3(26, 1.0, 4.0), fence)
	# invisible bounds so the player stays on the lot
	GarageKit.solid(world, Vector3(0.3, 4, 40), Vector3(-18.2, 2, 4))
	GarageKit.solid(world, Vector3(0.3, 4, 40), Vector3(26.2, 2, 4))
	GarageKit.solid(world, Vector3(50, 4, 0.3), Vector3(4, 2, 17.0))
	GarageKit.solid(world, Vector3(50, 4, 0.3), Vector3(4, 2, -6.4))
	# trees
	var trunk := GarageKit.m(Color(0.3, 0.2, 0.12), 0.0, 0.9)
	var leaf := GarageKit.m(Color(0.2, 0.36, 0.15), 0.0, 0.9)
	for tp in [Vector3(-10, 0, 8), Vector3(-14, 0, -2), Vector3(20, 0, 12), Vector3(-7, 0, 14), Vector3(22, 0, -4)]:
		GarageKit.cyl(world, 0.18, 2.2, tp + Vector3(0, 1.1, 0), trunk, Vector3.ZERO, 8)
		var cone := MeshFactory.cyl(world, 1.6, 3.6, tp + Vector3(0, 3.6, 0), leaf, Vector3.ZERO, 8, 0.05)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		GarageKit.solid(world, Vector3(0.4, 4, 0.4), tp + Vector3(0, 2, 0))
	# outdoor test pad + course gates
	var pad := Node3D.new()
	pad.position = Vector3(9.0, 0.0, 9.5)
	world.add_child(pad)
	GarageKit.cyl(pad, 1.3, 0.06, Vector3(0, 0.03, 0), GarageKit.m(Color(0.18, 0.2, 0.22), 0.1, 0.8), Vector3.ZERO, 24)
	var hl := GarageKit.label(pad, "H", 220, Vector3(0, 0.065, 0), Color(1, 0.8, 0.2), 0)
	hl.rotation_degrees.x = -90
	GarageKit.label(pad, "TEST PAD", 60, Vector3(0, 0.9, -1.4), Color(1, 0.8, 0.3), 0, true)
	var pad_it := Interactable.make(pad, Vector3(2.6, 0.3, 2.6), Vector3(0, 0.15, 0), "Outdoor test pad", func() -> String: return "Test flights (active drone)", func(_p): _test_pad_menu())
	pad_it.highlight_root = pad
	for g in [[Vector3(13, 0, 13), 0.4], [Vector3(17, 0, 7), 1.3], [Vector3(13, 0, 2), 2.2], [Vector3(20, 0, 14), -0.5]]:
		GarageKit.test_gate(world, g[0], g[1])
	# delivery van (parked off-screen until needed)
	van = GarageKit.van()
	van.position = Vector3(-90, 0, 20.5)
	van.visible = false
	world.add_child(van)


func _build_equipment() -> void:
	# --- workbench ---------------------------------------------------------------
	bench = GarageKit.workbench(world)
	var br: Node3D = bench["root"]
	br.position = BENCH_POS
	var peg := GarageKit.pegboard(world)
	peg.position = Vector3(0, 1.75, -5.98)
	var bench_it := Interactable.make(br, Vector3(3.0, 0.06, 0.85), Vector3(0, 0.95, 0), "Workbench",
		func() -> String: return "Work at the bench" + (" (%s)" % Game.bench_name if Game.bench_name != "" else ""), func(_p): _use_bench())
	bench_it.highlight_root = br
	bench_it.alt_prompt_fn = func() -> String: return "Load a drone from the rack"
	bench_it.alt_fn = func(_p): _bench_load_menu()
	bench_it.accepts_fn = func(h) -> String: return "Put %s on the workbench" % h.title if h.kind == "drone" else ""
	bench_it.give_fn = func(_p, h): _drone_to_bench(h)
	# bench lamp
	var lamp := OmniLight3D.new()
	lamp.position = BENCH_POS + Vector3(-0.9, 1.6, 0.15)
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 1.4
	lamp.omni_range = 2.8
	world.add_child(lamp)
	if Settings.quality()["safe"]:
		lamp.visible = false
	GarageKit.cyl(world, 0.12, 0.12, lamp.position + Vector3(0, 0.08, 0), GarageKit.m(Color(0.9, 0.5, 0.1), 0.3, 0.4), Vector3.ZERO, 12)
	GarageKit.cyl(world, 0.015, 0.7, BENCH_POS + Vector3(-0.9, 1.3, -0.3), GarageKit.m(Color(0.15, 0.15, 0.15), 0.6, 0.4), Vector3(35, 0, 0), 6)
	var lamp_it := Interactable.make(world, Vector3(0.3, 0.2, 0.3), lamp.position + Vector3(0, 0.08, 0), "Bench lamp", func() -> String: return "Lamp " + ("off" if lamp.visible else "on"), func(_p):
		lamp.visible = not lamp.visible
		Audio.play("switch"))
	lamp_it.highlight_root = null
	# drawers
	for i in 3:
		var d: Node3D = bench["drawers"][i]
		var it := Interactable.make(d, Vector3(1.4, 0.22, 0.06), Vector3(0, 0, 0.41), "Drawer", func() -> String: return ("Close" if drawer_open[i] else "Open") + " drawer", func(_p): _toggle_drawer(i))
		it.highlight_root = d
	# cupboard doors
	for i in 2:
		var hinge: Node3D = bench["doors"][i]
		var sgn := 1.0 if i == 0 else -1.0
		var it := Interactable.make(hinge, Vector3(0.68, 0.76, 0.05), Vector3(0.34 * sgn, 0, 0), "Cupboard", func() -> String: return ("Close" if cupboard_open[i] else "Open") + " cupboard", func(_p): _toggle_cupboard(i))
		it.highlight_root = hinge
	# --- computer desk -----------------------------------------------------------
	desk = GarageKit.desk_with_pc(world)
	var dr: Node3D = desk["root"]
	dr.position = Vector3(-4.5, 0, -3.3)
	dr.rotation_degrees.y = 90
	var pc_it := Interactable.make(desk["monitor"], Vector3(0.7, 0.45, 0.12), Vector3(0, 0.42, 0), "Workshop computer", func() -> String: return "Use WORKSHOP OS", func(_p): open_computer())
	pc_it.highlight_root = desk["monitor"]
	# --- storage shelves ----------------------------------------------------------
	var shelf_count := 2 if (Career.level() >= 2 or Career.has_upgrade("extra_shelf")) else 1
	for si in shelf_count:
		var sh := GarageKit.shelving(world, 1.8)
		sh.position = Vector3(4.72, 0, -4.4 + si * 2.0)
		sh.rotation_degrees.y = -90
		_fill_shelf(sh, si)
	# --- drone rack -----------------------------------------------------------------
	rack = GarageKit.drone_rack(world, int(Career.level_info()["rack"]))
	var rr: Node3D = rack["root"]
	rr.position = Vector3(-4.72, 0, 0.0)
	rr.rotation_degrees.y = 90
	GarageKit.label(rr, "DRONE RACK", 48, Vector3(0, 2.2, -0.19), Color(1, 0.7, 0.3))
	var rack_it := Interactable.make(rr, Vector3(rack["width"], 1.9, 0.06), Vector3(0, 1.15, -0.2), "Drone rack", func() -> String: return "", Callable())
	rack_it.accepts_fn = func(h) -> String: return "Return %s to the rack" % h.title if h.kind == "drone" else ""
	rack_it.give_fn = func(_p, h): _drone_to_rack(h)
	# --- charging station ---------------------------------------------------------------
	charger = GarageKit.charger(world, Career.dock_count())
	var cr: Node3D = charger["root"]
	cr.position = Vector3(-3.4, 0, -5.55)
	for i in Career.dock_count():
		var p: Vector3 = charger["docks"][i]
		var it := Interactable.make(cr, Vector3(0.16, 0.12, 0.2), p + Vector3(0, 0.05, 0), "Charging dock %d" % (i + 1), func() -> String: return _dock_prompt(i), func(_p): _dock_use(i))
		it.accepts_fn = func(h) -> String: return "Dock %s's battery" % Career.get_drone(h.data.get("drone", "")).get("name", "?") if h.kind == "battery" and _dock_free(i) else ""
		it.give_fn = func(_p, h): _battery_to_dock(h, i)
		dock_items.append(it)
		dock_models.append(null)
		var l := GarageKit.label(cr, "", 26, p + Vector3(0, 0.16, 0.1), Color(0.6, 1, 0.6), 0, true)
		dock_labels.append(l)
	# --- test station ---------------------------------------------------------------------
	test_station = GarageKit.test_station(world)
	var tr: Node3D = test_station["root"]
	tr.position = Vector3(4.15, 0, 1.2)
	tr.rotation_degrees.y = -90
	GarageKit.label(tr, "TEST STATION", 40, Vector3(0, 1.35, -0.3), Color(0.6, 1, 0.7), 0, true)
	test_item = Interactable.make(tr, Vector3(1.2, 0.3, 0.7), Vector3(0, 0.95, 0), "Test station", func() -> String: return _test_prompt(), func(_p): _test_use())
	test_item.highlight_root = tr
	test_item.accepts_fn = func(h) -> String: return "Connect %s and run diagnostics" % h.title if h.kind == "drone" and _test_drone().is_empty() else ""
	test_item.give_fn = func(_p, h): _drone_to_test(h)
	test_item.pick_prompt_fn = func() -> String: return "Pick up %s" % _test_drone()["name"] if not _test_drone().is_empty() else ""
	test_item.pick_fn = func(_p) -> bool: return _pick_test_drone()
	# --- 3D printer (level 2) ---------------------------------------------------------------
	if Career.level() >= 2:
		printer = GarageKit.printer(world)
		var pr: Node3D = printer["root"]
		pr.position = Vector3(4.6, 0, -0.9)
		pr.rotation_degrees.y = -90
		var pit := Interactable.make(pr, Vector3(0.7, 1.3, 0.6), Vector3(0, 0.65, 0), "3D printer", func() -> String: return _printer_prompt(), func(_p): _printer_menu())
		pit.highlight_root = pr
	else:
		_locked_bay(Vector3(4.4, 0, -0.9), "3D PRINTER BAY\nGARAGE LEVEL 2")
	# --- automated assembly (level 3) -----------------------------------------------------------
	if Career.level() >= 3:
		assembly = GarageKit.assembly_station(world)
		var ar: Node3D = assembly["root"]
		ar.position = Vector3(1.6, 0, -2.4)
		var ait := Interactable.make(ar, Vector3(1.8, 0.9, 0.8), Vector3(0, 0.45, 0), "Assembly station", func() -> String: return "Production jobs (FACTORY ORDERS)", func(_p): open_computer("factory"))
		ait.highlight_root = ar
	else:
		_locked_bay(Vector3(1.6, 0, -2.4), "AUTO-ASSEMBLY BAY\nGARAGE LEVEL 3")
	# --- deployment case ------------------------------------------------------------------------
	case_ = GarageKit.deploy_case(world)
	var cr2: Node3D = case_["root"]
	cr2.position = Vector3(-3.4, 0, 2.7)
	cr2.rotation_degrees.y = 20
	var case_it := Interactable.make(cr2, Vector3(0.75, 0.3, 0.5), Vector3(0, 0.15, 0), "Deployment case", func() -> String: return "Deploy a drone (DEPLOYMENT MAP)", func(_p): open_computer("deploy"))
	case_it.highlight_root = cr2
	case_it.accepts_fn = func(h) -> String: return "Pack %s for deployment" % h.title if h.kind == "drone" else ""
	case_it.give_fn = func(_p, h):
		_drone_to_rack(h)
		Career.data["active_drone"] = h.data["drone"]
		open_computer("deploy")


func _locked_bay(pos: Vector3, text: String) -> void:
	var yel := GarageKit.m(Color(0.95, 0.75, 0.1), 0.0, 0.6)
	for d in [Vector3(1.6, 0.004, 0.06), Vector3(0.06, 0.004, 1.0)]:
		for s in [-1, 1]:
			var off := Vector3(0, 0, 0.5 * s) if d.x > 1 else Vector3(0.8 * s, 0, 0)
			GarageKit.box(world, d, pos + off + Vector3(0, 0.003, 0), yel)
	var l := GarageKit.label(world, text, 42, pos + Vector3(0, 0.01, 0), Color(0.95, 0.75, 0.2))
	l.rotation_degrees.x = -90


func _fill_shelf(sh: Node3D, index: int) -> void:
	# labelled bins per category; the labels show live stock counts
	var cats: Array = ["frame", "motor", "prop", "esc", "fc", "rx", "battery", "vtx"]
	if index > 0:
		cats = ["antenna", "cam_mount", "cam", "guard", "payload"]
	for k in cats.size():
		var row := k / 2
		var col := k % 2
		var b := GarageKit.bin(sh, Color.from_hsv(0.05 + k * 0.12, 0.45, 0.6))
		b.position = Vector3(-0.42 + col * 0.84, 0.14 + row * 0.58, 0.02)
		var l := GarageKit.label(sh, "", 44, b.position + Vector3(0, 0.27, 0.2), Color(1, 0.95, 0.8))
		l.set_meta("cat", cats[k])
		shelf_labels.append(l)
		var it := Interactable.make(sh, Vector3(0.36, 0.24, 0.4), b.position + Vector3(0, 0.1, 0), "%s bin" % Parts.CAT_NAMES[cats[k]], func() -> String: return "Inspect %s stock" % Parts.CAT_NAMES[cats[k]].to_lower(), func(_p): _inspect_cat(cats[k]))
		it.highlight_root = b
	_refresh_shelf_labels()


func _refresh_shelf_labels() -> void:
	for l in shelf_labels:
		var cat: String = l.get_meta("cat")
		var n := 0
		for id in Career.data["inventory"]:
			if Parts.part(id)["cat"] == cat:
				n += int(Career.data["inventory"][id])
		l.text = "%s  x%d" % [Parts.CAT_NAMES[cat].to_upper(), n]


# =====================================================================================
# pickables
# =====================================================================================
func _spawn_pickables() -> void:
	for p in Career.data["parcels"]:
		if p.get("opened", false):
			continue
		var pos := Vector3.ZERO
		if p.get("where", "") == "cupboard":
			pos = BENCH_POS + Vector3(-0.75, 0.6, 0.02)
		else:
			var a: Array = p.get("pos", [DROP_POS.x, 0.3, DROP_POS.z])
			pos = Vector3(a[0], a[1], a[2])
		_make_parcel(p, pos)
	# tools in the drawers + tool case
	var t1 := _make_tool("Precision hex driver", "Hex driver for motor and stack screws. The workbench uses it automatically.", Vector3(0.025, 0.025, 0.22), Color(0.1, 0.1, 0.12))
	_put_in_drawer(t1, 0, Vector3(-0.3, -0.06, 0.0))
	var t2 := _make_tool("Prop wrench", "Four-way prop-nut wrench.", Vector3(0.09, 0.02, 0.09), Color(0.85, 0.3, 0.05))
	_put_in_drawer(t2, 0, Vector3(0.25, -0.07, 0.05))
	var t3 := _make_tool("Multimeter", "Simulated multimeter - the test station does the real checks.", Vector3(0.09, 0.04, 0.16), Color(0.95, 0.7, 0.1))
	_put_in_drawer(t3, 1, Vector3(-0.1, -0.06, 0.0))
	var t4 := _make_tool("Cable ties", "A bag of cable ties.", Vector3(0.12, 0.02, 0.08), Color(0.9, 0.9, 0.9))
	_put_in_drawer(t4, 2, Vector3(0.2, -0.07, 0.0))
	var case_model := Node3D.new()
	GarageKit.box(case_model, Vector3(0.45, 0.12, 0.3), Vector3.ZERO, GarageKit.m(Color(0.75, 0.1, 0.08), 0.2, 0.5))
	GarageKit.box(case_model, Vector3(0.14, 0.03, 0.02), Vector3(0, 0.075, 0), GarageKit.m(Color(0.1, 0.1, 0.1), 0.3, 0.5))
	var tc := Pickable.make(world, "tool", "Tool case", Vector3(0.45, 0.12, 0.3), case_model, 3.0)
	tc.describe_fn = func() -> String: return "Tool case: spare hex keys, side cutters and a soldering-free crimp kit."
	tc.global_position = _layout_pos("toolcase", BENCH_POS + Vector3(1.0, 1.0, 0.1))
	tc.set_meta("layout", "toolcase")
	pickables.append(tc)
	# loose items from the saved layout (batteries)
	for it in Career.data["layout"].get("items", []):
		if it.get("kind", "") == "battery" and not Career.get_drone(it.get("drone", "")).is_empty():
			var d := Career.get_drone(it["drone"])
			if d.get("battery_in", true) or Career.data["docks"].has(it["drone"]):
				continue
			var b := _make_battery(it["drone"])
			b.global_position = Vector3(it["pos"][0], it["pos"][1] + 0.05, it["pos"][2])
	# batteries out of their drone that aren't docked or saved anywhere: put them on the charger top
	for d in Career.roster():
		if not d.get("battery_in", true) and not Career.data["docks"].has(d["id"]) and not _has_battery_item(d["id"]):
			var b := _make_battery(d["id"])
			b.global_position = charger["root"].position + Vector3(0, 1.05, 0.15)
	# drones left on the floor / benches
	for d in Career.roster():
		if d["location"] == "floor" and d.get("pos") is Array:
			var p := _make_drone_pickable(d)
			p.global_position = Vector3(d["pos"][0], d["pos"][1] + 0.05, d["pos"][2])
		elif d["location"] == "hand":
			d["location"] = "rack"


func _has_battery_item(drone_id: String) -> bool:
	for p in pickables:
		if is_instance_valid(p) and p.kind == "battery" and p.data.get("drone", "") == drone_id:
			return true
	return false


func _layout_pos(key: String, def: Vector3) -> Vector3:
	var l: Dictionary = Career.data["layout"].get("pos", {})
	if l.has(key) and l[key] is Array and l[key].size() == 3:
		return Vector3(l[key][0], l[key][1] + 0.05, l[key][2])
	return def


func _make_tool(title: String, desc: String, size: Vector3, color: Color) -> Pickable:
	var mdl := Node3D.new()
	GarageKit.box(mdl, size, Vector3.ZERO, GarageKit.m(color, 0.4, 0.4))
	var p := Pickable.make(world, "tool", title, size, mdl, 0.3)
	p.describe_fn = func() -> String: return desc
	pickables.append(p)
	return p


func _put_in_drawer(p: Pickable, drawer: int, local: Vector3) -> void:
	var key := "tool_%s" % p.title.to_snake_case()
	p.set_meta("layout", key)
	var l: Dictionary = Career.data["layout"].get("pos", {})
	if l.has(key):
		p.global_position = _layout_pos(key, Vector3.ZERO)
		return
	var d: Node3D = bench["drawers"][drawer]
	p.freeze = true
	p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.reparent(d, false)
	p.position = local + Vector3(0, p.half_height, 0)
	p.set_meta("in_drawer", true)


func _make_parcel(parcel: Dictionary, pos: Vector3) -> Pickable:
	var starter: bool = parcel["id"] == "starter"
	var size := Vector3(0.5, 0.3, 0.4) if starter else Vector3(0.42, 0.26, 0.34)
	var mdl := GarageKit.cardboard_box(size)
	var lab := GarageKit.label(mdl, parcel.get("label", "PARCEL"), 40, Vector3(0, size.y * 0.5 + 0.004, 0), Color(0.15, 0.1, 0.05))
	lab.rotation_degrees.x = -90
	lab.outline_size = 0
	var p := Pickable.make(world, "parcel", "Starter kit" if starter else "Parcel", size, mdl, 2.0)
	p.data = {"parcel": parcel["id"]}
	p.describe_fn = func() -> String: return _parcel_text(parcel)
	p.use_prompt_fn = func() -> String: return "Open " + p.title.to_lower()
	p.use_fn = func(_pl): _open_parcel(p)
	if starter and parcel.get("where", "") == "cupboard":
		p.freeze = true
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.global_position = pos
	pickables.append(p)
	return p


func _parcel_text(parcel: Dictionary) -> String:
	var lines: Array = []
	for id in parcel["items"]:
		lines.append("%d x %s" % [parcel["items"][id], Parts.part(id).get("name", id)])
	return "%s contents:\n%s" % [parcel.get("label", "Parcel"), "\n".join(lines)]


func _make_battery(drone_id: String) -> Pickable:
	var d := Career.get_drone(drone_id)
	var bid: String = d.get("placed", {}).get("battery", "bat_1500")
	var mdl := MeshFactory.make_battery(bid)
	for l in mdl.find_children("*", "Label3D", true, false):
		l.visible = false
	mdl.scale = Vector3.ONE * 0.01
	mdl.position = Vector3(0, -0.014, 0)
	var p := Pickable.make(world, "battery", "%s battery" % d.get("name", "?"), Vector3(0.04, 0.03, 0.08), mdl, 0.2)
	p.data = {"drone": drone_id}
	p.describe_fn = func() -> String: return "%s - %d %% charged. Dock it on the charger or refit it to %s on the rack." % [Parts.part(bid).get("name", "Pack"), int(float(Career.get_drone(drone_id).get("charge", 0.0)) * 100.0), d.get("name", "?")]
	pickables.append(p)
	return p


func _make_drone_model(d: Dictionary) -> Node3D:
	var mdl := DroneVisual.assemble(d["placed"], d.get("broken", {}), d.get("cond", {}), Career.paint_of(d))
	mdl.scale = Vector3.ONE * 0.01
	return mdl


func _make_drone_pickable(d: Dictionary) -> Pickable:
	var holder := Node3D.new()
	var mdl := _make_drone_model(d)
	mdl.position = Vector3(0, -0.04, 0)
	holder.add_child(mdl)
	var p := Pickable.make(world, "drone", d["name"], Vector3(0.26, 0.08, 0.26), holder, 0.6)
	p.data = {"drone": d["id"]}
	p.describe_fn = func() -> String: return _drone_summary(d)
	pickables.append(p)
	return p


# =====================================================================================
# rack, docks, test station
# =====================================================================================
func _on_career_changed() -> void:
	if not _loaded:
		return
	_refresh_shelf_labels()
	var sig := ""
	for d in Career.roster():
		sig += "%s:%s:%s:%s:%s;" % [d["id"], d["location"], d.get("battery_in", true), str(d.get("cond", {}).hash()), str(d["placed"].hash())]
	sig += str(Career.data["docks"])
	if sig != _roster_sig:
		_sync_rack()


func _sync_rack() -> void:
	var sig := ""
	for d in Career.roster():
		sig += "%s:%s:%s:%s:%s;" % [d["id"], d["location"], d.get("battery_in", true), str(d.get("cond", {}).hash()), str(d["placed"].hash())]
	sig += str(Career.data["docks"])
	_roster_sig = sig
	for id in rack_items:
		if is_instance_valid(rack_items[id]):
			rack_items[id].queue_free()
	rack_items.clear()
	var slots: Array = rack["slots"]
	var i := 0
	for d in Career.roster():
		if d["location"] != "rack":
			continue
		if i >= slots.size():
			break
		var it := Interactable.make(rack["root"], Vector3(0.5, 0.16, 0.38), slots[i] + Vector3(0, 0.08, 0), d["name"], func() -> String: return "Options for %s" % d["name"], func(_p): _drone_menu(d["id"]))
		var mdl := _make_drone_model(d)
		mdl.position = Vector3(0, -0.07, 0)
		mdl.rotation_degrees.y = 180
		if not d.get("battery_in", true):
			var bn := mdl.get_node_or_null("battery")
			if bn:
				bn.visible = false
		it.add_child(mdl)
		it.highlight_root = mdl
		var tag := GarageKit.label(it, "%s%s" % [d["name"], "  ★" if Career.data["active_drone"] == d["id"] else ""], 30, Vector3(0, 0.3, 0.22), Color(1, 0.9, 0.7) if d.get("certified", false) else Color(1, 0.55, 0.4))
		tag.rotation_degrees.y = 0
		it.pick_prompt_fn = func() -> String: return "Pick up %s" % d["name"]
		it.pick_fn = func(pl) -> bool:
			d["location"] = "hand"
			var p := _make_drone_pickable(d)
			p.global_transform = it.global_transform
			pl.hold(p)
			_sync_rack()
			return true
		it.accepts_fn = func(h) -> String: return "Refit battery" if h.kind == "battery" and h.data.get("drone", "") == d["id"] else ""
		it.give_fn = func(pl, h): _battery_to_drone(pl, h, d["id"])
		it.alt_prompt_fn = func() -> String: return "Inspect"
		it.alt_fn = func(_p): _inspect_drone(d["id"])
		rack_items[d["id"]] = it
		i += 1
	# docks
	for k in dock_items.size():
		if dock_models[k] != null and is_instance_valid(dock_models[k]):
			dock_models[k].queue_free()
		dock_models[k] = null
		var did: String = Career.data["docks"][k] if k < Career.data["docks"].size() else ""
		if did != "" and not Career.get_drone(did).is_empty():
			var bid: String = Career.get_drone(did)["placed"].get("battery", "bat_1500")
			var mdl := MeshFactory.make_battery(bid)
			for l in mdl.find_children("*", "Label3D", true, false):
				l.visible = false
			mdl.scale = Vector3.ONE * 0.01
			mdl.position = charger["docks"][k] + Vector3(0, 0.01, 0)
			charger["root"].add_child(mdl)
			dock_models[k] = mdl
	# test station drone
	var tnode = test_station.get("drone_node")
	if tnode != null and is_instance_valid(tnode):
		tnode.queue_free()
	test_station.erase("drone_node")
	var td := _test_drone()
	if not td.is_empty():
		var mdl := _make_drone_model(td)
		mdl.position = test_station["pad"] + Vector3(0, 0.0, 0)
		test_station["root"].add_child(mdl)
		test_station["drone_node"] = mdl


func _drone_menu(id: String) -> void:
	var d := Career.get_drone(id)
	if d.is_empty():
		return
	var st := Career.drone_stats(d)
	var opts: Array = []
	opts.append(["Set as active drone for deployment", func():
		Career.data["active_drone"] = id
		Career.mark_dirty()
		_on_notify("%s is now the active drone." % d["name"], "good")])
	opts.append(["Take to the workbench (edit / repair)", func(): _bench_with(id)])
	opts.append(["Inspect build & damage", func(): _inspect_drone(id)])
	if d.get("battery_in", true):
		opts.append(["Remove battery (to charge it)", func():
			d["battery_in"] = false
			Career.mark_dirty()
			var b := _make_battery(id)
			b.global_position = player.cam.global_position
			player.hold(b)
			_sync_rack()])
	opts.append(["Pick it up", func(): rack_items[id].pick(player)])
	_context_menu("%s   (%s, %d %% battery%s)" % [d["name"], "certified" if d.get("certified", false) else "NOT certified", int(float(d.get("charge", 1.0)) * 100), "" if st.get("complete", false) else ", incomplete"], opts)


func _dock_free(i: int) -> bool:
	return i >= Career.data["docks"].size() or Career.data["docks"][i] == ""


func _dock_prompt(i: int) -> String:
	if _dock_free(i):
		return ""
	var d := Career.get_drone(Career.data["docks"][i])
	return "Take %s's battery (%d %%)" % [d.get("name", "?"), int(float(d.get("charge", 0.0)) * 100.0)]


func _dock_use(i: int) -> void:
	if _dock_free(i):
		_on_notify("Empty dock: remove a battery from a drone on the rack and bring it here.", "info")
		return
	var id: String = Career.data["docks"][i]
	Career.data["docks"][i] = ""
	Career.mark_dirty()
	var b := _make_battery(id)
	b.global_position = player.cam.global_position
	player.hold(b)
	Audio.play("snap")
	_sync_rack()


func _battery_to_dock(h: Pickable, i: int) -> void:
	var id: String = h.data["drone"]
	var docks: Array = Career.data["docks"]
	while docks.size() < Career.dock_count():
		docks.append("")
	docks[i] = id
	Career.get_drone(id)["battery_in"] = false
	Career.mark_dirty()
	player.release()
	pickables.erase(h)
	h.queue_free()
	Audio.play("snap")
	Pad.rumble(0.3, 0.1, 0.1)
	_sync_rack()


func _battery_to_drone(_pl, h: Pickable, id: String) -> void:
	var d := Career.get_drone(id)
	d["battery_in"] = true
	Career.mark_dirty()
	player.release()
	pickables.erase(h)
	h.queue_free()
	Audio.play("snap")
	_on_notify("Battery refitted to %s (%d %%)." % [d["name"], int(float(d["charge"]) * 100.0)], "good")
	_sync_rack()


func _test_drone() -> Dictionary:
	for d in Career.roster():
		if d["location"] == "test":
			return d
	return {}


func _test_prompt() -> String:
	var d := _test_drone()
	if d.is_empty():
		return "Diagnostics (bring a drone here)"
	return "Run diagnostics on %s" % d["name"]


func _test_use() -> void:
	var d := _test_drone()
	if d.is_empty():
		_on_notify("Pick a drone up from the rack (F) and press E on the test station to connect it.", "info")
		return
	_open_diagnostics(d["id"], true)


func _drone_to_test(h: Pickable) -> void:
	var id: String = h.data["drone"]
	var d := Career.get_drone(id)
	player.release()
	pickables.erase(h)
	h.queue_free()
	d["location"] = "test"
	Career.mark_dirty()
	Audio.play("snap")
	_sync_rack()
	_open_diagnostics(id, true)


func _pick_test_drone() -> bool:
	var d := _test_drone()
	if d.is_empty():
		return false
	d["location"] = "hand"
	var p := _make_drone_pickable(d)
	p.global_position = test_station["root"].to_global(test_station["pad"])
	player.hold(p)
	_sync_rack()
	return true


func _drone_to_rack(h: Pickable) -> void:
	var id: String = h.data["drone"]
	var d := Career.get_drone(id)
	if Career.rack_drones().size() >= int(Career.level_info()["rack"]):
		_on_notify("The rack is full - upgrade the garage or disassemble a drone.", "bad")
		return
	player.release()
	pickables.erase(h)
	h.queue_free()
	d["location"] = "rack"
	Career.mark_dirty()
	Audio.play("snap")
	_sync_rack()


func _drone_to_bench(h: Pickable) -> void:
	var id: String = h.data["drone"]
	player.release()
	pickables.erase(h)
	h.queue_free()
	_bench_with(id)


func _bench_with(id: String) -> void:
	Career.move_to_bench(id)
	_sync_rack()
	_use_bench()


func _bench_load_menu() -> void:
	var opts: Array = []
	for d in Career.roster():
		if d["location"] in ["rack", "test", "floor"]:
			var did: String = d["id"]
			opts.append([d["name"], func(): _bench_with(did)])
	if opts.is_empty():
		_on_notify("No drones on the rack yet.", "info")
		return
	_context_menu("Load which drone onto the workbench?", opts)


# =====================================================================================
# doors, drawers, lights
# =====================================================================================
func toggle_door() -> void:
	_set_door(not door_open, true)


func _set_door(open: bool, animate: bool) -> void:
	door_open = open
	Career.data["layout"]["door_open"] = open
	var closed_t := Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.97))
	var open_t := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)), Vector3(0, DOOR_H + 0.12, 3.9))
	var target := open_t if open else closed_t
	if _door_tw:
		_door_tw.kill()
	if not animate:
		door.transform = target
		return
	Audio.play("door")
	Pad.rumble(0.2, 0.35, 0.6)
	_door_tw = create_tween()
	# roll up: first lift, then swing into the ceiling track
	if open:
		_door_tw.tween_property(door, "position", Vector3(0, 1.4, 3.97), 1.2).set_trans(Tween.TRANS_SINE)
		_door_tw.tween_property(door, "transform", open_t, 1.2).set_trans(Tween.TRANS_SINE)
	else:
		_door_tw.tween_property(door, "transform", Transform3D(Basis.IDENTITY, Vector3(0, 1.4, 3.97)), 1.2).set_trans(Tween.TRANS_SINE)
		_door_tw.tween_property(door, "position", Vector3(0, 0, 3.97), 1.2).set_trans(Tween.TRANS_SINE)


func _set_lights(on: bool, sound: bool) -> void:
	lights_on = on
	Career.data["layout"]["lights_on"] = on
	for tl in tube_lights:
		(tl["light"] as OmniLight3D).visible = on
		(tl["tube_mat"] as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.0
	if sound:
		Audio.play("switch")
		if on:
			# fluorescent flicker on
			for tl in tube_lights:
				var l: OmniLight3D = tl["light"]
				var tw := create_tween()
				for k in 3:
					tw.tween_property(l, "light_energy", 0.2, 0.05)
					tw.tween_property(l, "light_energy", 1.5, 0.07)


func _toggle_drawer(i: int) -> void:
	drawer_open[i] = not drawer_open[i]
	var d: Node3D = bench["drawers"][i]
	var tw := create_tween()
	tw.tween_property(d, "position:z", 0.45 if drawer_open[i] else 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Audio.play("drawer", 1.0 if drawer_open[i] else 0.85)
	Pad.rumble(0.15, 0.0, 0.1)


func _toggle_cupboard(i: int) -> void:
	cupboard_open[i] = not cupboard_open[i]
	var hinge: Node3D = bench["doors"][i]
	var sgn := 1.0 if i == 0 else -1.0
	var tw := create_tween()
	tw.tween_property(hinge, "rotation:y", (-1.75 * sgn) if cupboard_open[i] else 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Audio.play("drawer", 0.7)


# =====================================================================================
# parcels & delivery van
# =====================================================================================
func is_inside(p: Vector3) -> bool:
	return p.x > IN_MIN.x and p.x < IN_MAX.x and p.z > IN_MIN.z and p.z < IN_MAX.z - 0.1


func _open_parcel(p: Pickable) -> void:
	if not is_inside(p.global_position):
		_on_notify("Bring the parcel inside the garage before opening it.", "bad")
		Audio.play("error")
		return
	var parcel := Career.parcel(p.data["parcel"])
	if parcel.is_empty():
		return
	var items: Dictionary = parcel["items"]
	if player.held == p:
		player.release()
	p.freeze = true
	Career.open_parcel(p.data["parcel"])
	Pad.rumble(0.4, 0.2, 0.25)
	# flaps open, parts pop out, the box flattens
	var vis := p.visual
	var tw := create_tween().set_parallel(true)
	for k in 2:
		var f := vis.get_node_or_null("Flap%d" % k)
		if f:
			tw.tween_property(f, "rotation:x", (1.9 if k == 0 else -1.9), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var k2 := 0
	for id in items:
		var mdl := MeshFactory.make_part(id, "frame_5")
		for l in mdl.find_children("*", "Label3D", true, false):
			l.visible = false
		mdl.scale = Vector3.ONE * 0.012
		world.add_child(mdl)
		mdl.global_position = p.global_position + Vector3(0, 0.1, 0)
		var dest := p.global_position + Vector3(cos(k2 * 1.3) * 0.25, 0.45 + (k2 % 3) * 0.08, sin(k2 * 1.3) * 0.25)
		var t2 := create_tween()
		t2.tween_interval(0.25 + k2 * 0.07)
		t2.tween_property(mdl, "global_position", dest, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.parallel().tween_property(mdl, "rotation:y", 3.0, 0.9)
		t2.tween_interval(0.8)
		t2.tween_property(mdl, "scale", Vector3.ONE * 0.0005, 0.3)
		t2.tween_callback(mdl.queue_free)
		k2 += 1
	var lines: Array = []
	for id in items:
		lines.append("+%d %s" % [items[id], Parts.part(id).get("name", id)])
	_on_notify("Unpacked into storage:\n" + "\n".join(lines.slice(0, 8)) + ("\n..." if lines.size() > 8 else ""), "delivery")
	var t3 := create_tween()
	t3.tween_interval(1.6)
	t3.tween_property(p, "scale", Vector3(1.2, 0.05, 1.2), 0.25)
	t3.tween_callback(func():
		pickables.erase(p)
		p.queue_free())


func _process_van(_dt: float) -> void:
	if _van_busy:
		return
	var due := Career.orders_due()
	if due.is_empty():
		return
	_van_busy = true
	_van_order = due[0]
	_van_order["status"] = "arriving"
	_on_notify("A SwiftParcel van is pulling into the driveway.", "delivery")
	van.visible = true
	var path := [Vector3(-90, 0, 20.5), Vector3(-9, 0, 20.5), Vector3(-2.2, 0, 17.0), Vector3(0, 0, 13.5), Vector3(0, 0, 10.8)]
	van.position = path[0]
	var tw := create_tween()
	Audio.play("van")
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var dir := (b - a).normalized()
		tw.tween_callback(func(): van.rotation.y = atan2(-dir.x, -dir.z) + PI)
		tw.tween_property(van, "position", b, a.distance_to(b) / (14.0 if i == 1 else 6.0)).set_trans(Tween.TRANS_SINE if i == path.size() - 1 else Tween.TRANS_LINEAR)
	tw.tween_callback(func():
		Audio.play("horn")
		var rd := van.get_node_or_null("RearDoor")
		if rd:
			create_tween().tween_property(rd, "rotation:y", -2.0, 0.6))
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		var pos := DROP_POS + Vector3(randf_range(-0.6, 0.6), 0.25, randf_range(-0.3, 0.3))
		var parcel := Career.order_delivered(_van_order, pos)
		var pk := _make_parcel(parcel, van.global_position + Vector3(0, 1.0, -2.6))
		pk.linear_velocity = Vector3(randf_range(-0.3, 0.3), 1.5, -1.6)
		_on_notify("Delivery on the driveway! Carry the parcel inside and open it.", "delivery")
		Pad.rumble(0.3, 0.0, 0.2))
	tw.tween_interval(1.2)
	tw.tween_callback(func():
		var rd := van.get_node_or_null("RearDoor")
		if rd:
			rd.rotation.y = 0.0)
	var away := [Vector3(0, 0, 14.5), Vector3(2.5, 0, 19.0), Vector3(12, 0, 20.5), Vector3(95, 0, 20.5)]
	var prev: Vector3 = path[path.size() - 1]
	for i in away.size():
		var b: Vector3 = away[i]
		var dir: Vector3 = (b - prev).normalized()
		var reverse := i == 0
		tw.tween_callback(func(): van.rotation.y = atan2(-dir.x, -dir.z) + (0.0 if reverse else PI))
		tw.tween_property(van, "position", b, prev.distance_to(b) / (3.0 if reverse else 9.0))
		prev = b
	tw.tween_callback(func():
		van.visible = false
		_van_busy = false)


# =====================================================================================
# bench / computer / test pad
# =====================================================================================
func _use_bench() -> void:
	if _busy:
		return
	_busy = true
	player.enabled = false
	var target := BENCH_POS + Vector3(0, 1.55, 0.9)
	var tw := create_tween()
	tw.tween_property(player.cam, "global_position", target, 0.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(player.cam, "global_rotation", Vector3(deg_to_rad(-45), 0, 0), 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_save_layout()
		Game.goto("workshop", {"stage": "build"}))


func open_computer(app: String = "") -> void:
	if overlay != null or _busy:
		return
	player.enabled = false
	var os := WorkshopOS.new()
	os.garage = self
	os.start_app = app
	_open_overlay(os)


func _test_pad_menu() -> void:
	var d := Career.active_drone()
	var opts: Array = []
	for mid in ["shakedown", "gate_race", "battery_challenge", "free_flight"]:
		var m := Campaign.mission(mid)
		if Career.mission_unlocked(m):
			opts.append(["%s%s" % [m["name"], "" if Career.mission_count(mid) > 0 or m["reward"] == 0 else "   (+%d cr)" % m["reward"]], func(): launch(mid, d.get("id", ""))])
	_context_menu("Test flight with %s" % d.get("name", "(no active drone)"), opts)


## Launches a career mission with a roster drone. Returns "" or the reason it can't.
func launch(mission_id: String, drone_id: String) -> String:
	var d := Career.get_drone(drone_id)
	var why := Career.deploy_check(d)
	if why != "":
		_on_notify(why, "bad")
		Audio.play("error")
		return why
	var m := Campaign.mission(mission_id)
	# rearm the mission module if pods were used
	var used := int(d.get("pods_used", 0))
	if used > 0 and d["placed"].has("payload"):
		var cost := int(float(Parts.part(d["placed"]["payload"])["price"]) * 0.35) * used
		if not Career.spend(cost, "Module rearm for %s" % d["name"]):
			return "Can't afford the module rearm (%d cr)." % cost
		d["pods_used"] = 0
	Career.data["active_drone"] = drone_id
	Game.flight = {"source": "roster", "drone_id": drone_id, "mission": mission_id}
	Game.mission = mission_id
	_save_layout()
	Career.save()
	close_overlay()
	_busy = true
	Audio.play("arm")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): Game.goto("fly"))
	return ""


# =====================================================================================
# overlays
# =====================================================================================
func _open_overlay(c: Control) -> void:
	close_overlay()
	overlay = c
	_overlay_root.add_child(c)
	player.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_prompt()


func close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	if Career.level() != _built_level and not _busy:
		# a garage expansion was just bought: rebuild the room with the new equipment
		_busy = true
		_save_layout()
		Game.goto("garage", {"spawn": "pc", "message": "Workshop expanded to Level %d - %s. New equipment installed." % [Career.level(), Career.level_info()["name"]]})
		return
	if not _busy:
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_prompt()


func _context_menu(title: String, options: Array) -> void:
	var cm := ContextMenu.new()
	cm.title = title
	cm.options = options
	cm.closed.connect(close_overlay)
	_open_overlay(cm)


func _inspect_cat(cat: String) -> void:
	var lines: Array = []
	for id in Parts.parts_in(cat):
		var n := Career.stock(id)
		if n > 0:
			lines.append("%2d x  %s" % [n, Parts.part(id)["name"]])
	if lines.is_empty():
		lines.append("(empty - order more in PARTS MARKET)")
	_info_panel("%s BIN" % Parts.CAT_NAMES[cat].to_upper(), "\n".join(lines))


func _inspect_drone(id: String) -> void:
	var d := Career.get_drone(id)
	if d.is_empty():
		return
	_info_panel(d["name"], _drone_summary(d))


func _drone_summary(d: Dictionary) -> String:
	var st := Career.drone_stats(d)
	var t: Array = []
	if not st.get("complete", false):
		t.append("INCOMPLETE: missing %s" % st.get("missing_text", "?"))
	if st.has("twr"):
		t.append("%s  •  %s  •  %s" % [st["frame_name"], st["motor_name"], st["prop_name"]])
		t.append("Weight %d g   TWR %.1f   Endurance ~%.1f min   Top ~%d km/h" % [int(st["mass_g"]), st["twr"], st["endurance_min"], int(st["top_kmh"])])
		t.append("Agility %d   Durability %d   Parts value %d cr" % [int(st["agility"]), int(st["durability_pct"]), st["cost"]])
		if st["payload_id"] != "":
			t.append("Module: %s" % Parts.part(st["payload_id"])["name"])
	t.append("Battery %d %% %s   •   %s" % [int(float(d.get("charge", 1.0)) * 100.0), "" if d.get("battery_in", true) else "(removed)", "CERTIFIED" if d.get("certified", false) else "not certified - run diagnostics"])
	var dmg: Array = []
	for slot in d.get("cond", {}):
		if float(d["cond"][slot]) < 0.95:
			dmg.append("%s %d %%" % [slot.replace("_", " "), int(float(d["cond"][slot]) * 100.0)])
	for slot in d.get("broken", {}):
		dmg.append("%s BROKEN" % slot.replace("_", " "))
	if not dmg.is_empty():
		t.append("Damage: " + ", ".join(dmg))
	t.append("Missions flown %d   Targets %d" % [int(d.get("missions", 0)), int(d.get("targets", 0))])
	return "\n".join(t)


func _info_panel(title: String, body: String) -> void:
	var cm := ContextMenu.new()
	cm.title = title
	cm.body = body
	cm.options = []
	cm.closed.connect(close_overlay)
	_open_overlay(cm)


func _open_diagnostics(id: String, certify: bool) -> void:
	var dp := DiagnosticsPanel.new()
	dp.drone_id = id
	dp.can_certify = certify
	dp.closed.connect(close_overlay)
	dp.motor_spin.connect(func(level: float):
		var n = test_station.get("drone_node")
		if n != null and is_instance_valid(n):
			for i in 4:
				var pn: Node3D = n.get_node_or_null("prop_%d" % (i + 1))
				if pn:
					pn.rotation.y += level * 1.4 * (1.0 if Parts.MOTOR_SPIN[i] == "CW" else -1.0))
	_open_overlay(dp)


func _printer_prompt() -> String:
	var pr: Dictionary = Career.data["printer"]
	if pr.has("item"):
		return "Printing %s - %d s left" % [Parts.part(pr["item"])["name"], int(pr["t"])]
	return "Print a part"


func _printer_menu() -> void:
	if Career.data["printer"].has("item"):
		_on_notify(_printer_prompt(), "info")
		return
	var opts: Array = []
	for id in Parts.db():
		var p: Dictionary = Parts.part(id)
		if p.has("print"):
			opts.append(["%s   (%d cr filament)" % [p["name"], p["print"]], func():
				var err := Career.start_print(id)
				if err != "":
					_on_notify(err, "bad")])
	_context_menu("3D printer - choose a part", opts)


# =====================================================================================
# player input
# =====================================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _busy or not _loaded:
		return
	if overlay != null:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or (event.is_action_pressed("tablet") and overlay is Tablet) or (event.is_action_pressed("inventory") and overlay is Tablet):
			if overlay.has_method("back") and overlay.back():
				get_viewport().set_input_as_handled()
				return
			close_overlay()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		_pause_menu()
	elif event.is_action_pressed("help"):
		open_help(0)
	elif event.is_action_pressed("tablet"):
		_open_tablet("status")
	elif event.is_action_pressed("inventory"):
		_open_tablet("inventory")
	elif event.is_action_pressed("use"):
		_do_use()
	elif event.is_action_pressed("pickup"):
		_do_pickup()
	elif event.is_action_pressed("place"):
		if player.held != null and not player.place():
			player.drop()
		_after_drop()
	elif event.is_action_pressed("secondary"):
		_do_secondary()
	else:
		return
	get_viewport().set_input_as_handled()
	_update_prompt()


func _do_use() -> void:
	var h := player.hovered
	var held := player.held
	if held != null:
		if h is Interactable and (h as Interactable).accepts(held) != "":
			(h as Interactable).give(player, held)
			return
		if held.kind == "parcel":
			_open_parcel(held)
			return
		if not player.place():
			player.drop()
		_after_drop()
		return
	if h is Pickable:
		if (h as Pickable).use_prompt() != "":
			(h as Pickable).use(player)
		else:
			_take(h)
	elif h is Interactable:
		(h as Interactable).use(player)


func _do_pickup() -> void:
	if player.held != null:
		player.drop()
		_after_drop()
		return
	var h := player.hovered
	if h is Pickable:
		_take(h)
	elif h is Interactable and (h as Interactable).pick_prompt() != "":
		(h as Interactable).pick(player)


func _take(p: Pickable) -> void:
	if p.has_meta("in_drawer") or p.get_parent() != world:
		p.remove_meta("in_drawer")
		p.reparent(world, true)
	if p.kind == "drone":
		var d := Career.get_drone(p.data["drone"])
		if not d.is_empty():
			d["location"] = "hand"
	if p.kind == "parcel" and p.data.get("parcel", "") == "starter":
		Career.set_flag("starter_picked")
		var parcel := Career.parcel("starter")
		parcel["where"] = "floor"
	player.hold(p)


func _after_drop() -> void:
	# bookkeeping for drones put down on the floor
	for p in pickables:
		if is_instance_valid(p) and p.kind == "drone" and not p.held:
			var d := Career.get_drone(p.data["drone"])
			if not d.is_empty() and d["location"] == "hand":
				d["location"] = "floor"
				d["pos"] = [p.global_position.x, p.global_position.y, p.global_position.z]
				Career.mark_dirty()


func _do_secondary() -> void:
	var held := player.held
	if held != null:
		if held.kind == "parcel":
			_info_panel(held.title, held.describe())
		else:
			_info_panel(held.title, held.describe())
		return
	var h := player.hovered
	if h is Interactable and (h as Interactable).alt_prompt() != "":
		(h as Interactable).alt(player)
	elif h is Pickable:
		_info_panel((h as Pickable).title, (h as Pickable).describe())


func _open_tablet(tab: String) -> void:
	var t := Tablet.new()
	t.start_tab = tab
	t.garage = self
	t.closed.connect(close_overlay)
	_open_overlay(t)


func _pause_menu() -> void:
	_context_menu("PAUSED", [
		["Resume", func(): pass],
		["Workshop tablet", func(): call_deferred("_open_tablet", "status")],
		["How to play", func(): call_deferred("open_help", 0)],
		["Options", func():
			call_deferred("_open_options")],
		["Save & main menu", func():
			_save_layout()
			Career.save()
			Game.goto("menu")],
	])


func _open_options() -> void:
	var o := OptionsMenu.new()
	_open_overlay(o)
	o.tree_exited.connect(func():
		if overlay == o:
			overlay = null
			close_overlay())


# =====================================================================================
# per-frame
# =====================================================================================
func _process(dt: float) -> void:
	if not _loaded:
		return
	_process_van(dt)
	# ambience: a faint fluorescent hum, and the van's engine when it is near
	var amb := 0.035 if lights_on else 0.015
	var pitch := 0.12
	if van.visible and player:
		var d := van.global_position.distance_to(player.global_position)
		var vl := clampf(18.0 / (d + 6.0), 0.0, 0.9)
		if vl > amb:
			amb = vl
			pitch = 0.45
	Audio.engine_level = amb
	Audio.engine_pitch = pitch
	Audio.engine_chop = 0.0
	if Engine.get_process_frames() % 30 == 0:
		_update_time_of_day()
	# charger LEDs and labels
	var docks: Array = Career.data["docks"]
	for i in dock_labels.size():
		var l: Label3D = dock_labels[i]
		var led: MeshInstance3D = charger["leds"][i]
		var mm := led.material_override as StandardMaterial3D
		if i < docks.size() and docks[i] != "":
			var c := float(Career.get_drone(docks[i]).get("charge", 0.0))
			l.text = "%d %%" % int(c * 100.0)
			var full := c >= 1.0
			mm.albedo_color = Color(0.2, 1.0, 0.3) if full else Color(1.0, 0.35, 0.1)
			mm.emission_enabled = true
			mm.emission = mm.albedo_color
			mm.emission_energy_multiplier = 2.0 if full or fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0 else 0.3
		else:
			l.text = ""
			mm.emission_energy_multiplier = 0.0
	# printer animation
	if not printer.is_empty():
		var pr: Dictionary = Career.data["printer"]
		var part: MeshInstance3D = printer["part"]
		if pr.has("item"):
			var k := 1.0 - float(pr["t"]) / maxf(float(pr.get("total", 30.0)), 1.0)
			printer["head"].position.x = sin(Time.get_ticks_msec() * 0.008) * 0.15
			printer["head"].position.z = cos(Time.get_ticks_msec() * 0.011) * 0.12
			printer["head"].position.y = 0.83 + k * 0.08
			part.visible = true
			part.scale = Vector3(1, maxf(k, 0.05) * 2.0, 1)
		else:
			part.visible = false
	# assembly arms
	if not assembly.is_empty():
		var busy: bool = Career.data["jobs"].any(func(j): return j["auto"] and int(j["done"]) < int(j["qty"]))
		for i in assembly["arms"].size():
			var a: Node3D = assembly["arms"][i]
			a.rotation.y = sin(Time.get_ticks_msec() * 0.002 + i * 2.0) * (1.2 if busy else 0.05)
	# monitor flicker
	_update_hud()


func _update_hud() -> void:
	if Engine.get_process_frames() % 8 == 0:
		var chip := func(t: String, c: String) -> String: return "[bgcolor=#0b0d10d8][color=%s] %s [/color][/bgcolor]  " % [c, t]
		var txt: String = chip.call("%d cr" % Career.credits(), "#ffa424") + chip.call("REP %d" % int(Career.data["rep"]), "#52c7bd") + chip.call("LV %d  %s" % [Career.level(), Career.level_info()["name"].to_upper()], "#c4a6ff")
		if Settings.opt.get("show_clock", true):
			txt += chip.call("DAY %d  %s" % [int(Career.data["day"]), Career.clock_text()], "#d0d4d8")
		var orders: Array = Career.data["orders"]
		if not orders.is_empty():
			txt += chip.call("DELIVERY %s%s" % [Career.eta_text(orders[0]), "  +%d" % (orders.size() - 1) if orders.size() > 1 else ""], "#8cc8ff")
		_info.text = txt
	var g := Career.guide_text()
	var hints: bool = Settings.opt.get("tutorial_hints", true)
	_guide.text = g
	_guide_title.text = "STEP %d / %d  -  %s     (%s  how to play)" % [int(Career.data["tutorial"]) + 1, Career.GUIDE.size(), Career.guide_title().to_upper(), Pad.glyph("help")]
	_guide_bar.value = int(Career.data["tutorial"])
	_guide_card.visible = g != "" and overlay == null and hints
	_update_beacon()
	if Engine.get_process_frames() % 6 == 0:
		_update_prompt()


func _update_prompt() -> void:
	if _prompt == null or player == null:
		return
	var t := ""
	var h := player.hovered
	var held := player.held
	if overlay != null:
		_prompt.text = ""
		_crosshair.visible = false
		_held_lbl.text = ""
		return
	_crosshair.visible = true
	if held != null:
		_held_lbl.text = "Holding: %s\n[%s] place   [%s] drop   hold [%s] rotate   [%s] %s" % [held.title, Pad.glyph("use") if Pad.using_pad else Pad.glyph("place"), Pad.glyph("pickup"), Pad.glyph("rotate_item"), Pad.glyph("secondary"), "inspect"]
		if h is Interactable and (h as Interactable).accepts(held) != "":
			t = "[%s] %s" % [Pad.glyph("use"), (h as Interactable).accepts(held)]
		elif held.kind == "parcel":
			t = "[%s] Open %s" % [Pad.glyph("use"), held.title.to_lower()] if is_inside(held.global_position) else "Carry it inside to open it"
	else:
		_held_lbl.text = ""
		if h is Pickable:
			var p := h as Pickable
			t = "%s\n[%s] Pick up" % [p.title, Pad.glyph("pickup")]
			if p.use_prompt() != "":
				t += "   [%s] %s" % [Pad.glyph("use"), p.use_prompt()]
			t += "   [%s] Inspect" % Pad.glyph("secondary")
		elif h is Interactable:
			var it := h as Interactable
			var parts: Array = []
			if it.prompt() != "":
				parts.append("[%s] %s" % [Pad.glyph("use"), it.prompt()])
			if it.pick_prompt() != "":
				parts.append("[%s] %s" % [Pad.glyph("pickup"), it.pick_prompt()])
			if it.alt_prompt() != "":
				parts.append("[%s] %s" % [Pad.glyph("secondary"), it.alt_prompt()])
			t = it.title + ("\n" + "   ".join(parts) if not parts.is_empty() else "")
	_crosshair.set_meta("hot", h != null and t != "")
	_crosshair.queue_redraw()
	# "[E] Open" -> boxed key caps
	t = _cap_re.sub(t, "[bgcolor=#ffffff2e][color=#ffd27a] $1 [/color][/bgcolor]", true)
	_prompt.text = "[center]" + t.replace("\n", "\n") + "[/center]"


# =====================================================================================
# UI
# =====================================================================================
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = UITheme.root_control()
	layer.add_child(ui)
	_crosshair = Control.new()
	_crosshair.position = Vector2(960, 540)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(func():
		if _crosshair.get_meta("hot", false):
			_crosshair.draw_arc(Vector2.ZERO, 13.0, 0, TAU, 28, Color(0, 0, 0, 0.5), 4.0, true)
			_crosshair.draw_arc(Vector2.ZERO, 13.0, 0, TAU, 28, UITheme.ACCENT, 2.0, true)
		_crosshair.draw_circle(Vector2.ZERO, 4.0, Color(0, 0, 0, 0.5))
		_crosshair.draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.9)))
	ui.add_child(_crosshair)
	_prompt = RichTextLabel.new()
	_prompt.bbcode_enabled = true
	_prompt.fit_content = true
	_prompt.scroll_active = false
	_prompt.position = Vector2(410, 580)
	_prompt.custom_minimum_size = Vector2(1100, 0)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("normal_font_size", 23)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	ui.add_child(_prompt)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info.custom_minimum_size = Vector2(1300, 0)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_font_size_override("normal_font_size", 19)
	_info.position = Vector2(24, 18)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	ui.add_child(_info)
	_guide_card = PanelContainer.new()
	_guide_card.position = Vector2(24, 900)
	_guide_card.custom_minimum_size = Vector2(760, 0)
	var gst := UITheme.flat(Color(0.05, 0.055, 0.06, 0.86), 8, Color(UITheme.ACCENT, 0.55), 1, 14)
	gst.border_width_left = 6
	_guide_card.add_theme_stylebox_override("panel", gst)
	_guide_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_guide_card)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 4)
	_guide_card.add_child(gv)
	_guide_title = UITheme.label("", 17, UITheme.ACCENT)
	_guide_title.add_theme_font_override("font", UITheme.font(true))
	gv.add_child(_guide_title)
	_guide = UITheme.label("", 20)
	_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide.custom_minimum_size = Vector2(730, 0)
	gv.add_child(_guide)
	_guide_bar = ProgressBar.new()
	_guide_bar.show_percentage = false
	_guide_bar.custom_minimum_size = Vector2(730, 6)
	_guide_bar.max_value = Career.GUIDE.size()
	gv.add_child(_guide_bar)
	_held_lbl = UITheme.label("", 19, UITheme.MUTED)
	_held_lbl.position = Vector2(24, 900)
	_held_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_held_lbl.add_theme_constant_override("outline_size", 6)
	ui.add_child(_held_lbl)
	var help := UITheme.label("", 16, UITheme.MUTED)
	help.position = Vector2(1500, 1040)
	help.text = "%s tablet  •  %s inventory  •  Esc pause" % [Pad.glyph("tablet"), Pad.glyph("inventory")]
	ui.add_child(help)
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(1420, 80)
	_toasts.custom_minimum_size = Vector2(480, 0)
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_toasts)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 20
	add_child(_overlay_layer)
	_overlay_root = UITheme.root_control()
	_overlay_layer.add_child(_overlay_root)
	var fl := CanvasLayer.new()
	fl.layer = 60
	add_child(fl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(_fade)


func _fade_in() -> void:
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)


func _on_notify(text: String, kind: String) -> void:
	if _toasts == null:
		return
	var col := UITheme.TEXT
	match kind:
		"good": col = UITheme.GOOD
		"bad": col = UITheme.BAD
		"delivery": col = Color(0.55, 0.8, 1.0)
		"guide": col = UITheme.ACCENT
	var l := UITheme.label(text, 19, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	var tst := UITheme.flat(Color(0.05, 0.055, 0.065, 0.9), 8, Color(col, 0.35), 1, 14)
	tst.border_width_left = 6
	tst.border_color = col
	l.add_theme_stylebox_override("normal", tst)
	_toasts.add_child(l)
	if _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
	if kind in ["delivery", "good"]:
		Audio.play("notify")
	var tw := l.create_tween()
	tw.tween_interval(7.0 if kind != "guide" else 10.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


# =====================================================================================
# placement / persistence
# =====================================================================================
func _place_player() -> void:
	match spawn:
		"bench":
			player.position = BENCH_POS + Vector3(0, 0, 1.4)
			player.yaw = 0.0
			player.pitch = deg_to_rad(-20)
		"rack":
			player.position = Vector3(-3.4, 0, 0.0)
			player.yaw = deg_to_rad(90)
		"outside":
			player.position = Vector3(6.5, 0, 9.0)
			player.yaw = deg_to_rad(160)
		"pc":
			player.position = Vector3(-2.8, 0, -2.0)
			player.yaw = deg_to_rad(110)
		_:
			player.position = Vector3(0.0, 0, 2.2)
			player.yaw = 0.0
	player.rotation.y = player.yaw


func _save_layout() -> void:
	var lay: Dictionary = Career.data["layout"]
	var pos: Dictionary = lay.get("pos", {})
	var items: Array = []
	for p in pickables:
		if not is_instance_valid(p):
			continue
		var gp: Vector3 = p.global_position
		match p.kind:
			"parcel":
				var parcel := Career.parcel(p.data["parcel"])
				if not parcel.is_empty() and parcel.get("where", "") != "cupboard":
					parcel["pos"] = [gp.x, maxf(gp.y, 0.2), gp.z]
			"battery":
				if p.held:
					var d := Career.get_drone(p.data["drone"])
					if not d.is_empty():
						d["battery_in"] = true
				else:
					items.append({"kind": "battery", "drone": p.data["drone"], "pos": [gp.x, gp.y, gp.z]})
			"drone":
				var d := Career.get_drone(p.data["drone"])
				if not d.is_empty():
					if p.held or d["location"] == "hand":
						d["location"] = "rack"
					elif d["location"] == "floor":
						d["pos"] = [gp.x, gp.y, gp.z]
			"tool":
				if p.has_meta("layout") and not p.has_meta("in_drawer"):
					pos[p.get_meta("layout")] = [gp.x, gp.y, gp.z]
	lay["pos"] = pos
	lay["items"] = items
	Career.mark_dirty()



# =====================================================================================
# tutorial: the How-to-play guide and the floating step beacon
# =====================================================================================
func open_help(chapter: int) -> void:
	var h := HowToPlay.new()
	h.start_chapter = chapter
	h.closed.connect(close_overlay)
	_open_overlay(h)


func _maybe_tutorial() -> void:
	if not Career.flag("seen_intro") and Settings.opt.get("tutorial_hints", true):
		Career.set_flag("seen_intro")
		open_help(0)


## World position the current career-guide step is about (Vector3.INF = none).
func _guide_target() -> Vector3:
	var step := int(Career.data["tutorial"])
	var held := player.held if player else null
	match step:
		0:
			for p in pickables:
				if is_instance_valid(p) and p.kind == "parcel" and p.data.get("parcel", "") == "starter":
					return p.global_position + Vector3(0, 0.5, 0) if cupboard_open[0] or cupboard_open[1] else BENCH_POS + Vector3(-0.75, 1.1, 0.5)
			return BENCH_POS + Vector3(-0.75, 1.1, 0.5)
		1, 7:
			for p in pickables:
				if is_instance_valid(p) and p.kind == "parcel" and not p.held:
					return p.global_position + Vector3(0, 0.6, 0)
			if held != null and held.kind == "parcel":
				return Vector3.INF
			return Vector3(-4.5, 1.9, -3.3) if step == 7 else Vector3.INF
		2, 3, 8:
			return BENCH_POS + Vector3(0, 1.6, 0.1)
		4:
			if held != null and held.kind == "drone":
				return test_station["root"].global_position + Vector3(0, 1.5, 0)
			if not rack_items.is_empty():
				return (rack_items.values()[0] as Node3D).global_position + Vector3(0, 0.5, 0)
			return test_station["root"].global_position + Vector3(0, 1.5, 0)
		5:
			return Vector3(3.3, 1.9, 3.9) if not door_open else Vector3(9.0, 1.6, 9.5)
		6, 9, 10:
			return Vector3(-4.5, 1.9, -3.3)
	return Vector3.INF


func _update_beacon() -> void:
	if _beacon == null:
		_beacon = Node3D.new()
		world.add_child(_beacon)
		var m := MeshFactory.mat(UITheme.ACCENT, 0.0, 0.4, 2.5)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		var cone := MeshFactory.cyl(_beacon, 0.12, 0.26, Vector3(0, 0.0, 0), m, Vector3(180, 0, 0), 10, 0.0)
		cone.name = "Cone"
		cone.set_meta("no_glow", true)
		var stem := MeshFactory.box(_beacon, Vector3(0.06, 0.2, 0.06), Vector3(0, 0.23, 0), m)
		stem.set_meta("no_glow", true)
		_beacon_label = Label3D.new()
		_beacon_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_beacon_label.no_depth_test = true
		_beacon_label.font_size = 40
		_beacon_label.pixel_size = 0.004
		_beacon_label.modulate = UITheme.ACCENT
		_beacon_label.outline_size = 8
		_beacon_label.position = Vector3(0, 0.55, 0)
		_beacon.add_child(_beacon_label)
	var t := _guide_target() if (Settings.opt.get("beacons", true) and Settings.opt.get("tutorial_hints", true) and overlay == null) else Vector3.INF
	_beacon.visible = t != Vector3.INF
	if not _beacon.visible:
		return
	var bob := sin(Time.get_ticks_msec() * 0.005) * 0.08
	_beacon.global_position = t + Vector3(0, bob, 0)
	_beacon.rotation.y += 0.05
	var d := player.global_position.distance_to(t) if player else 0.0
	_beacon_label.text = "STEP %d   %.0f m" % [int(Career.data["tutorial"]) + 1, d] if d > 2.5 else "STEP %d" % (int(Career.data["tutorial"]) + 1)



## Wall dressing that also teaches: a build-steps whiteboard, posters, a cabinet, a soldering station.
func _build_details() -> void:
	# whiteboard above the charger
	var wb := Node3D.new()
	wb.position = Vector3(-3.25, 1.95, -5.98)
	world.add_child(wb)
	GarageKit.box(wb, Vector3(2.2, 1.25, 0.03), Vector3.ZERO, GarageKit.m(Color(0.94, 0.95, 0.96), 0.0, 0.35))
	GarageKit.box(wb, Vector3(2.28, 0.05, 0.05), Vector3(0, -0.66, 0.02), GarageKit.m(Color(0.6, 0.6, 0.62), 0.6, 0.4))
	for x in [-1.13, 1.13]:
		GarageKit.box(wb, Vector3(0.04, 1.3, 0.04), Vector3(x, 0, 0.01), GarageKit.m(Color(0.6, 0.6, 0.62), 0.6, 0.4))
	var t := GarageKit.label(wb, "HOW TO BUILD A DRONE", 44, Vector3(0, 0.5, 0.025), Color(0.05, 0.25, 0.6))
	t.outline_size = 0
	var steps := GarageKit.label(wb, "1  Frame   2  Motors (CW / CCW)   3  Props\n4  ESC > FC > receiver > VTX > antenna\n5  Cam mount > camera > battery\n6  Tighten EVERY screw\n7  WIRE  >  SETUP  >  SAVE DRONE\n8  Test station, then the test pad!", 30, Vector3(-1.02, 0.08, 0.025), Color(0.1, 0.1, 0.12))
	steps.outline_size = 0
	steps.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	steps.position.x = -1.02
	steps.offset = Vector2(0, 0)
	steps.width = 800
	steps.autowrap_mode = TextServer.AUTOWRAP_OFF
	var red := GarageKit.label(wb, "CERTIFY BEFORE YOU FLY", 28, Vector3(0.45, -0.5, 0.025), Color(0.8, 0.1, 0.08))
	red.outline_size = 0
	# posters on the left wall
	var posters := [["FLY SAFE", "Land at the launch point\nto recover your drone", Color(0.95, 0.6, 0.12)],
		["CHARGE IT", "Dock batteries between\nflights", Color(0.32, 0.78, 0.74)]]
	for i in posters.size():
		var pnode := Node3D.new()
		pnode.position = Vector3(-4.98, 1.9, 1.9 + i * 1.0)
		pnode.rotation_degrees.y = 90
		world.add_child(pnode)
		GarageKit.box(pnode, Vector3(0.7, 0.95, 0.01), Vector3.ZERO, GarageKit.m(Color(0.12, 0.13, 0.15), 0.0, 0.8))
		GarageKit.box(pnode, Vector3(0.7, 0.18, 0.012), Vector3(0, 0.38, 0), GarageKit.m(posters[i][2], 0.0, 0.6))
		var h := GarageKit.label(pnode, posters[i][0], 40, Vector3(0, 0.38, 0.01), Color(0.06, 0.06, 0.07))
		h.outline_size = 0
		var b := GarageKit.label(pnode, posters[i][1], 22, Vector3(0, 0.0, 0.01), Color(0.9, 0.9, 0.9))
		b.outline_size = 0
	# wall cabinet on the back wall, right of the pegboard
	var cab := GarageKit.m(Color(0.5, 0.12, 0.1), 0.3, 0.5)
	GarageKit.box(world, Vector3(1.6, 0.75, 0.4), Vector3(2.6, 2.35, -5.78), cab)
	GarageKit.box(world, Vector3(0.02, 0.7, 0.01), Vector3(2.6, 2.35, -5.575), GarageKit.m(Color(0.2, 0.05, 0.04), 0.3, 0.5))
	for x in [2.5, 2.7]:
		GarageKit.box(world, Vector3(0.03, 0.15, 0.03), Vector3(x, 2.3, -5.56), GarageKit.m(Color(0.75, 0.75, 0.75), 0.9, 0.3))
	# soldering station and a reel of cable on the bench
	var ss := BENCH_POS + Vector3(-1.2, 0.92, 0.15)
	GarageKit.box(world, Vector3(0.22, 0.12, 0.16), ss + Vector3(0, 0.06, 0), GarageKit.m(Color(0.15, 0.15, 0.17), 0.4, 0.5))
	GarageKit.box(world, Vector3(0.08, 0.04, 0.005), ss + Vector3(0, 0.08, 0.081), GarageKit.m(Color(0.1, 0.8, 0.3), 0.0, 0.3, 1.5))
	GarageKit.cyl(world, 0.02, 0.18, ss + Vector3(0.18, 0.13, 0), GarageKit.m(Color(0.1, 0.1, 0.1), 0.3, 0.5), Vector3(0, 0, 35), 6)
	GarageKit.cyl(world, 0.12, 0.08, BENCH_POS + Vector3(1.35, 0.96, -0.2), GarageKit.m(Color(0.9, 0.5, 0.05), 0.0, 0.6), Vector3(90, 0, 0), 14)
	# ceiling beams
	for z in [-4.6, -2.2, 0.2, 2.6]:
		GarageKit.box(world, Vector3(10.2, 0.16, 0.14), Vector3(0, 3.12, z), GarageKit.m(Color(0.42, 0.42, 0.42), 0.5, 0.6))
