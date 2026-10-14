extends Node
## Visual smoke-test driver (not part of the game). Run under xvfb:
##   godot --path . res://tests/driver.tscn -- <out_dir> <step> [<step> ...]

var out_dir := ""
var main: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	for step in args.slice(1):
		print("STEP ", step)
		await call(step)
	print("DRIVER DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])


func full_build() -> Dictionary:
	return DroneVisual.default_placement()


func all_wires() -> Array:
	return Parts.WIRES.keys()


func menu() -> void:
	Game.goto("menu")
	await _frames(40)
	await shot("menu")


func build_empty() -> void:
	Game.placed = {}
	Game.broken = {}
	Game.wires = []
	Game.goto("workshop", {"stage": "build"})
	await _frames(40)
	await shot("build_empty")


func build_partial() -> void:
	var f := full_build()
	Game.placed = {}
	for k in ["frame", "motor_1", "motor_2", "motor_3", "motor_4", "prop_1", "esc", "fc"]:
		Game.placed[k] = f[k]
	Game.wires = []
	Game.goto("workshop", {"stage": "build"})
	await _frames(40)
	await shot("build_partial")


func build_full() -> void:
	Game.placed = full_build()
	Game.broken = {"prop_2": true}
	Game.wires = []
	Game.goto("workshop", {"stage": "build"})
	await _frames(40)
	await shot("build_full_broken")
	Game.broken = {}


func wire() -> void:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = ["m1", "m2", "bat_pos"]
	Game.goto("workshop", {"stage": "wire"})
	await _frames(90)
	await shot("wire")


func setup_tabs() -> void:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = all_wires()
	Game.goto("workshop", {"stage": "setup"})
	await _frames(40)
	var tabs: TabContainer = _find(main, "TabContainer")
	for i in 5:
		tabs.current_tab = i
		await _frames(25)
		await shot("setup_%d" % i)


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _fly_node() -> FlyStage:
	for c in main.get_children():
		if c is FlyStage:
			return c
	return null


func fly() -> void:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = all_wires()
	Game.mission = "free_flight"
	Game.goto("fly")
	await _frames(40)
	var fs := _fly_node()
	await shot("fly_pad")
	fs._toggle_arm()
	fs.thr_stick = 0.5
	await _frames(120)
	await shot("fly_up")
	fs.sim.pos = Vector3(200, fs.sim.pos.y + 20, -150)
	await _frames(20)
	await shot("fly_far")
	fs.sim.pos = Vector3(420, fs.sim.pos.y + 40, -300)
	await _frames(20)
	await shot("fly_farther")


func fly_gates() -> void:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = all_wires()
	Game.mission = "gate_race"
	Game.goto("fly")
	await _frames(60)
	var fs := _fly_node()
	await shot("gates_countdown")
	fs.countdown = 0.0
	await _frames(10)
	fs.sim.pos = Vector3(0, fs.sim.pos.y + 6, -60)
	fs._toggle_arm()
	await _frames(30)
	await shot("gates_air")


func crash() -> void:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = all_wires()
	Game.mission = "free_flight"
	Game.goto("fly")
	await _frames(40)
	var fs := _fly_node()
	fs._toggle_arm()
	fs.thr_stick = 0.4
	await _frames(100)
	fs.thr_stick = 0.0
	fs.sim.vel = Vector3(15, -14, -6)
	fs.sim.pos.y += 30
	await _frames(240)
	await shot("crash_replay")
	await _frames(300)
	await shot("crash_result")


# ---- real-input interaction test --------------------------------------------------------------
func _mouse_move(p: Vector2) -> void:
	Input.warp_mouse(p)
	await _frames(3)


func _mouse_btn(p: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = p
	ev.global_position = p
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(ev)
	await _frames(2)


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)
	await _frames(2)
	ev = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = false
	get_viewport().push_input(ev)
	await _frames(1)


func _ws() -> Workshop:
	for c in main.get_children():
		if c is Workshop:
			return c
	return null


func _drag_part(bs: BuildStage, part_id: String, slot_name: String, rotate_to_zero: bool = true) -> void:
	var ws := _ws()
	var item: Dictionary = {}
	for it in bs._tray_items:
		if it["id"] == part_id:
			item = it
	if item.is_empty():
		print("  !! tray item not found: ", part_id)
		return
	var start: Vector2 = bs._tray_container.position + bs._tray_cam.unproject_position(item["pivot"].position)
	var fid: String = Game.placed.get("frame", "frame_5")
	var s := Parts.slot_by_name(fid, slot_name)
	var target: Vector2 = ws.camera.unproject_position(ws.drone_root.to_global(s["pos"] + Vector3(0, 1.0, 0)))
	await _mouse_move(start)
	await _mouse_btn(start, true)
	var steps := 6
	for i in range(1, steps + 1):
		await _mouse_move(start.lerp(target, float(i) / steps))
	if rotate_to_zero and Parts.needs_orientation(Parts.part(part_id)["cat"]):
		var guard := 0
		while bs.held_step != 0 and guard < 5:
			await _key(KEY_R)
			guard += 1
	await _frames(12)
	await _mouse_btn(target, false)
	await _frames(25)


func interaction() -> void:
	Game.placed = {}
	Game.broken = {}
	Game.wires = []
	Game.goto("workshop", {"stage": "build"})
	await _frames(40)
	var ws := _ws()
	var bs := ws.build
	var ok := 0
	var bad := 0
	# 1. drag everything in, in the right order
	var plan := [
		["frame", "frame_5", "frame"],
		["motor", "motor_2306_ccw", "motor_1"], ["motor", "motor_2306_cw", "motor_2"],
		["motor", "motor_2306_cw", "motor_3"], ["motor", "motor_2306_ccw", "motor_4"],
		["prop", "prop_5143_ccw", "prop_1"], ["prop", "prop_5143_cw", "prop_2"],
		["prop", "prop_5143_cw", "prop_3"], ["prop", "prop_5143_ccw", "prop_4"],
		["esc", "esc_4in1", "esc"], ["fc", "fc_f4", "fc"], ["vtx", "vtx_25", "vtx"],
		["cam", "cam_fpv", "cam"], ["battery", "bat_1500", "battery"],
	]
	# wrong things first: motor with wrong spin must bounce, prop before motor must bounce
	bs.show_category("frame")
	await _drag_part(bs, "frame_5", "frame")
	print("CHECK frame placed: ", Game.placed.get("frame", "none"))
	bs.show_category("motor")
	await _drag_part(bs, "motor_2306_cw", "motor_1")
	print("CHECK wrong-spin motor rejected: ", not Game.placed.has("motor_1"), "  hint='", bs._hint.text, "'")
	bs.show_category("prop")
	await _drag_part(bs, "prop_5143_ccw", "prop_1")
	print("CHECK prop-before-motor rejected: ", not Game.placed.has("prop_1"))
	for step in plan:
		bs.show_category(step[0])
		await _frames(3)
		await _drag_part(bs, step[1], step[2])
		var placed_ok: bool = Game.placed.get(step[2], "") == step[1]
		if placed_ok:
			ok += 1
		else:
			bad += 1
			print("  !! failed to place ", step[1], " on ", step[2], "  hint='", bs._hint.text, "'")
	print("CHECK drag placement: ok=", ok, " bad=", bad, "  complete=", Game.stats()["complete"])
	await shot("interaction_built")
	# 2. wrong spin prop on a motor
	var removed := "prop_2"
	Game.placed.erase(removed)
	bs._restore_from_game()
	bs._rebuild_markers()
	bs.show_category("prop")
	await _frames(3)
	await _drag_part(bs, "prop_5143_ccw", "prop_2")
	print("CHECK wrong-spin prop rejected: ", not Game.placed.has("prop_2"), " hint='", bs._hint.text, "'")
	await _drag_part(bs, "prop_5143_cw", "prop_2")
	print("CHECK right-spin prop accepted: ", Game.placed.get("prop_2", "") == "prop_5143_cw")
	# 3. wiring
	ws.switch_stage("wire")
	await _frames(80)
	var wr := ws.wire
	var bad_pairs := [["fc.M1", "esc.S2"], ["bat.RED", "esc.CBAT"], ["bat.RED", "fc.M1"], ["esc.BATP", "esc.BATN"]]
	for pr in bad_pairs:
		var before := Game.wires.size()
		await _click_pad(wr, pr[0])
		await _click_pad(wr, pr[1])
		print("CHECK bad wire ", pr, " rejected: ", Game.wires.size() == before)
	for wid in Parts.WIRES:
		var w: Dictionary = Parts.WIRES[wid]
		await _click_pad(wr, w["a"])
		await _click_pad(wr, w["b"])
	print("CHECK wires placed: ", Game.wires.size(), " / ", Parts.WIRES.size(), " complete=", Game.wiring_complete())
	await shot("interaction_wired")
	ws.switch_stage("setup")
	await _frames(30)
	print("CHECK reached setup: ", ws.stage)


func _click_pad(wr: WireStage, pid: String) -> void:
	var ws := _ws()
	var p := ws.camera.unproject_position(wr._pad_world(pid))
	await _mouse_move(p)
	await _mouse_btn(p, true)
	await _mouse_btn(p, false)


func _setup_fly(mission: String) -> FlyStage:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = all_wires()
	Game.cfg = FlightMath.default_cfg()
	Game.mission = mission
	Game.goto("fly")
	await _frames(60)
	return _fly_node()


func race_complete() -> void:
	SaveData.data["best_times"] = {}
	var fs := await _setup_fly("gate_race")
	print("CHECK gate race built: gates=", fs.gates.size(), " par=", snappedf(fs.par_time, 0.1), " limit=", snappedf(fs.time_limit, 0.1), " trees=", fs.world.tree_count)
	fs.countdown = 0.0
	await _frames(5)
	print("CHECK countdown finished -> flying: ", fs.state == FlyStage.S.FLYING)
	for g in fs.gates:
		fs.sim.pos = g["pos"] - g["normal"] * 0.5
		fs.sim.vel = g["normal"] * 240.0      # 1 m per 1/240 s step: crosses the ring plane inside one step
		await get_tree().physics_frame
		await get_tree().physics_frame
	await _frames(5)
	print("CHECK all gates passed -> result: gate_idx=", fs.gate_idx, " state_is_result=", fs.state == FlyStage.S.RESULT, " best=", SaveData.best_time("gate_race") > 0.0, " unlocked_whoop=", SaveData.is_unlocked("frame_3"))


func gate_miss() -> void:
	var fs := await _setup_fly("gate_race")
	fs.countdown = 0.0
	await _frames(5)
	var g: Dictionary = fs.gates[0]
	fs.sim.pos = g["pos"] - g["normal"] * 0.5 + Vector3(0, 8, 0)   # well outside the ring
	fs.sim.vel = g["normal"] * 240.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("CHECK a gate flown past outside the ring does not count: ", fs.gate_idx == 0)


func battery_complete() -> void:
	var fs := await _setup_fly("battery_challenge")
	print("CHECK route built: points=", fs.route.size())
	fs.countdown = 0.0
	await _frames(5)
	for p in fs.route:
		fs.sim.vel = Vector3.ZERO
		fs.sim.pos = p
		await get_tree().physics_frame
		await get_tree().physics_frame
	await _frames(5)
	print("CHECK route finished: idx=", fs.route_idx, " result=", fs.state == FlyStage.S.RESULT, " unlocked_7in=", SaveData.is_unlocked("frame_7"))


func battery_flat() -> void:
	var fs := await _setup_fly("free_flight")
	fs._toggle_arm()
	fs.thr_stick = 0.4
	await _frames(60)
	fs.sim.used_mah = fs.sim.capacity_mah * 0.985    # nearly empty
	var t0 := Time.get_ticks_msec()
	var lost := false
	for i in 1500:
		await get_tree().physics_frame
		if fs.sim.power_lost:
			lost = true
			break
	print("CHECK battery cutoff cuts power: ", lost, " v_filt=", snappedf(fs.sim.v_filt, 0.01), " cmd0=", fs.sim.cmd[0])
	for i in 6000:
		await get_tree().physics_frame
		if fs.state == FlyStage.S.RESULT or fs.state == FlyStage.S.REPLAY:
			break
	print("CHECK flat battery ends the flight (replay/result): ", fs.state == FlyStage.S.RESULT or fs.state == FlyStage.S.REPLAY, " state=", fs.state)


func rx_off() -> void:
	Game.cfg = FlightMath.default_cfg()
	var fs := await _setup_fly("free_flight")
	fs.cfg["rx_enabled"] = false
	fs.sim.rx_link = false
	fs._toggle_arm()
	print("CHECK cannot arm with receiver UART off: ", not fs.sim.armed)
	fs.cfg["rx_enabled"] = true
	fs.cfg["vtx_enabled"] = false
	await _frames(5)
	print("CHECK vtx off -> static_only param: ", fs.fx_mat.get_shader_parameter("static_only"))


func crash_breaks_prop() -> void:
	var fs := await _setup_fly("free_flight")
	fs._toggle_arm()
	fs.thr_stick = 0.4
	await _frames(40)
	var broken_before: int = Game.stats()["broken_props"]
	fs.sim.pos.y = fs.world.height(fs.sim.pos.x, fs.sim.pos.z) + 25.0
	fs.sim.vel = Vector3(0, -22, 0)
	fs.thr_stick = 0.0
	for i in 2000:
		await get_tree().physics_frame
		if fs.state == FlyStage.S.REPLAY:
			break
	print("CHECK crash triggers replay: ", fs.state == FlyStage.S.REPLAY, "  broken props: ", broken_before, " -> ", Game.stats()["broken_props"])
	# a gentle landing must NOT break anything
	Game.broken = {}


func soft_landing() -> void:
	var fs := await _setup_fly("free_flight")
	fs._toggle_arm()
	fs.thr_stick = 0.3
	await _frames(40)
	fs.sim.pos.y = fs.world.height(fs.sim.pos.x, fs.sim.pos.z) + 0.5
	fs.sim.vel = Vector3(0, -2.5, 0)
	fs.thr_stick = 0.0
	for i in 1500:
		await get_tree().physics_frame
	print("CHECK soft landing (3 m/s) is not a crash: ", fs.state == FlyStage.S.FLYING, " broken=", Game.stats()["broken_props"], " onground=", fs.sim.on_ground)


func wire_interaction() -> void:
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = []
	Game.goto("workshop", {"stage": "wire"})
	await _frames(70)
	var ws := _ws()
	var wr := ws.wire
	# every pad must be on screen and not under the UI
	var offscreen := 0
	for pid in wr._pads:
		var p := ws.camera.unproject_position(wr._pad_world(pid))
		if p.x < 0 or p.x > 1920 or p.y < 70 or p.y > 1075 or (p.x < 500 and p.y < 500) or (p.x < 700 and p.y > 1000):
			offscreen += 1
			print("  !! pad hidden/offscreen: ", pid, " ", p)
	print("CHECK all pads reachable on screen: ", offscreen == 0)
	var bad_pairs := [["fc.M1", "esc.S2"], ["bat.RED", "esc.CBAT"], ["bat.RED", "fc.M1"], ["esc.BATP", "esc.BATN"], ["vtx.UART", "fc.CAM"], ["esc.M1", "fc.M1"]]
	for pr in bad_pairs:
		var before := Game.wires.size()
		await _click_pad(wr, pr[0])
		await _click_pad(wr, pr[1])
		print("CHECK bad wire ", pr, " rejected: ", Game.wires.size() == before, "  msg-shown")
	for wid in Parts.WIRES:
		var w: Dictionary = Parts.WIRES[wid]
		await _click_pad(wr, w["a"])
		await _click_pad(wr, w["b"])
		if not Game.wires.has(wid):
			print("  !! wire not placed: ", wid)
	print("CHECK wires placed: ", Game.wires.size(), " / ", Parts.WIRES.size(), " complete=", Game.wiring_complete())
	await shot("interaction_wired")
	# unplug one by clicking a connected pad
	await _click_pad(wr, "fc.M1")
	print("CHECK click on a connected pad unplugs it: ", not Game.wires.has("m1"))
	await _click_pad(wr, "fc.M1")
	await _click_pad(wr, "esc.S1")
	ws.switch_stage("setup")
	await _frames(20)
	print("CHECK reached setup: ", ws.stage)


func click_mode() -> void:
	Game.placed = {}
	Game.broken = {}
	Game.wires = []
	Game.goto("workshop", {"stage": "build"})
	await _frames(40)
	var ws := _ws()
	var bs := ws.build
	bs.show_category("frame")
	await _frames(3)
	var item: Dictionary = bs._tray_items[1]
	var start: Vector2 = bs._tray_container.position + bs._tray_cam.unproject_position(item["pivot"].position)
	await _mouse_move(start)
	await _mouse_btn(start, true)
	await _mouse_btn(start, false)          # click, no drag -> carry mode
	print("CHECK click picks the part up (carry mode): ", bs.hold_mode == 2, " held=", bs.held_id)
	var target: Vector2 = ws.camera.unproject_position(ws.drone_root.to_global(Vector3(0, 1, 0)))
	await _mouse_move(target)
	while bs.held_step != 0:
		await _key(KEY_R)
	await _mouse_btn(target, true)           # second click places it
	await _mouse_btn(target, false)
	await _frames(20)
	print("CHECK second click places it: ", Game.placed.get("frame", ""), " mode=", bs.hold_mode)
	# click an installed part to pick it back up
	var back: Vector2 = ws.camera.unproject_position(ws.drone_root.to_global(Vector3(0, 1, 0)))
	await _mouse_move(back)
	await _mouse_btn(back, true)
	await _mouse_btn(back, false)
	print("CHECK clicking an installed part removes it: ", not Game.placed.has("frame"), " carrying=", bs.hold_mode == 2)
	# Esc cancels carry
	await _key(KEY_ESCAPE)
	print("CHECK Esc cancels carrying: ", bs.held == null)


func _mon() -> String:
	return "fps=%d proc=%.1fms phys=%.1fms draws=%d objs=%d prims=%d nodes=%d mem=%.0fMB" % [
		Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]


func perf() -> void:
	var t0 := Time.get_ticks_msec()
	Game.goto("menu")
	await _frames(30)
	print("PERF menu ", _mon())
	Game.placed = full_build()
	Game.broken = {}
	Game.wires = all_wires()
	t0 = Time.get_ticks_msec()
	Game.goto("workshop", {"stage": "build"})
	await _frames(2)
	print("PERF workshop load ms=", Time.get_ticks_msec() - t0)
	await _frames(60)
	print("PERF build ", _mon())
	_ws().switch_stage("wire")
	await _frames(60)
	print("PERF wire ", _mon())
	_ws().switch_stage("setup")
	await _frames(60)
	print("PERF setup ", _mon())
	Game.mission = "free_flight"
	t0 = Time.get_ticks_msec()
	Game.goto("fly")
	while _fly_node() == null or _fly_node().state == FlyStage.S.LOADING:
		await get_tree().process_frame
	print("PERF fly load ms=", Time.get_ticks_msec() - t0, " trees=", _fly_node().world.tree_count)
	await _frames(90)
	print("PERF fly ", _mon())


func fly_preset(n: int) -> void:
	Settings.graphics_preset = n
	await fly()
	print("PERF preset ", n, " ", _mon())


func fly_low() -> void:
	await fly_preset(0)


func fly_medium() -> void:
	await fly_preset(1)
