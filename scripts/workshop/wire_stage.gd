class_name WireStage
extends Node
## WIRE stage: the stack is shown exploded; click one pad then another to run a
## cable. Only correct pairings are accepted, wrong ones flash red.

const PART_OF := {"esc": "esc", "fc": "fc", "vtx": "vtx", "cam": "cam", "bat": "battery"}

var ws: Workshop
var active := false

var _ui: Control
var _check: Dictionary = {}       # wire id -> Label
var _next_btn: Button
var _tip: Label
var _pads: Dictionary = {}        # pad id -> {"node": MeshInstance3D, "mat": StandardMaterial3D, "part": Node3D}
var _cables: Dictionary = {}      # wire id -> MeshInstance3D
var _motor_leads: Array = []
var _flash: Array = []            # [{node, time}]
var _pending := ""
var _hover := ""
var _anim_time := 0.0
var _tween: Tween
var _t := 0.0


func _ready() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ws.ui_root.add_child(_ui)

	var cl := PanelContainer.new()
	cl.position = Vector2(20, 90)
	_ui.add_child(cl)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cl.add_child(cv)
	cv.add_child(UITheme.label("WIRING", 22, UITheme.ACCENT))
	for id in Parts.WIRES:
		var l := UITheme.label(Parts.WIRES[id]["label"], 17)
		l.custom_minimum_size = Vector2(430, 0)
		_check[id] = l
		cv.add_child(l)
	cv.add_child(UITheme.label("Click a pad, then the pad it connects to.\nClick a connected pad to unplug its wire.\nRight-drag orbit  •  Wheel zoom", 16, UITheme.MUTED))

	_tip = UITheme.label("", 18, Color.WHITE)
	_tip.add_theme_stylebox_override("normal", UITheme.flat(Color(0, 0, 0, 0.75), 5, Color(1, 1, 1, 0.15), 1, 8))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_tip)

	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 10)
	rb.position = Vector2(20, 1080 - 76)
	_ui.add_child(rb)
	rb.add_child(UITheme.button("<< BUILD", func(): ws.switch_stage("build"), Vector2(150, 48)))
	rb.add_child(UITheme.button("Unplug all", _clear_all, Vector2(150, 48)))
	_next_btn = UITheme.accent_button("NEXT: SETUP  >>", func(): ws.switch_stage("setup"), Vector2(250, 48))
	rb.add_child(_next_btn)
	set_active(false)


func _clear_all() -> void:
	Game.wires.clear()
	_refresh_cables()
	_refresh_checks()
	Game.save_drone()
	Audio.play("click")


# --- activation ----------------------------------------------------------------------------
func set_active(on: bool) -> void:
	if on == active and _ui.visible == on:
		return
	active = on
	_ui.visible = on
	if _tween:
		_tween.kill()
	if on:
		_explode()
		_make_pads()
		_make_motor_leads()
		_refresh_cables()
		_refresh_checks()
		ws.cam_target = Vector3(3.0, 5.0, 2.0)
		ws.cam_dist = 27.0
		ws.cam_pitch = deg_to_rad(-46.0)
		ws._update_camera()
		_anim_time = 1.2
	else:
		_collapse()


func _part_nodes() -> Dictionary:
	return ws.build.part_nodes


func _explode() -> void:
	var fid: String = Game.placed.get("frame", "frame_5")
	_tween = create_tween().set_parallel(true)
	for sn in _part_nodes():
		var n: Node3D = _part_nodes()[sn]
		var s := Parts.slot_by_name(fid, sn)
		if s.is_empty():
			continue
		var cat: String = s["cat"]
		_tween.tween_property(n, "position", s["pos"] + Parts.EXPLODE.get(cat, Vector3.ZERO), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if cat == "prop":
			n.visible = false
		for l in n.find_children("*", "Label3D", true, false):
			if l.is_in_group("pad_label") or l.is_in_group("chip_label"):
				l.visible = true
	var frame_n: Node3D = _part_nodes().get("frame")
	if frame_n:
		var tp: Node3D = frame_n.get_node_or_null("TopPlate")
		if tp:
			tp.visible = false


func _collapse() -> void:
	for pid in _pads:
		if is_instance_valid(_pads[pid]["node"]):
			_pads[pid]["node"].queue_free()
	_pads.clear()
	for c in _cables.values():
		if is_instance_valid(c):
			c.queue_free()
	_cables.clear()
	for c in _motor_leads:
		if is_instance_valid(c):
			c.queue_free()
	_motor_leads.clear()
	for f in _flash:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	_flash.clear()
	_pending = ""
	for n in _part_nodes().values():
		n.visible = true
		for l in n.find_children("*", "Label3D", true, false):
			if l.is_in_group("pad_label") or l.is_in_group("chip_label"):
				l.visible = false
	ws.build.reset_layout()
	ws.cam_target = Vector3(0, 2.5, 9.0)
	ws.cam_dist = 42.0
	ws.cam_pitch = deg_to_rad(-38.0)
	ws._update_camera()


# --- pads -------------------------------------------------------------------------------------
func _pad_color(kind: String) -> Color:
	match kind:
		"sig": return Color(0.3, 0.9, 1.0)
		"pwr+": return Color(1.0, 0.25, 0.2)
		"pwr-": return Color(0.55, 0.6, 0.85)
		"cur": return Color(1.0, 0.6, 0.15)
		"cap": return Color(0.7, 0.7, 0.7)
	return Color(0.55, 0.3, 0.7)


func _make_pads() -> void:
	for pid in Parts.PADS:
		var pd: Dictionary = Parts.PADS[pid]
		var part_slot: String = PART_OF[pid.get_slice(".", 0)]
		var part: Node3D = _part_nodes().get(part_slot)
		if part == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = _pad_color(pd["kind"])
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 1.4
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var s := MeshFactory.sphere(part, 0.3, pd["pos"] + Vector3(0, 0.28, 0), m)
		s.material_override = m
		_pads[pid] = {"node": s, "mat": m, "part": part, "base": m.albedo_color}


func _pad_world(pid: String) -> Vector3:
	return _pads[pid]["node"].global_position


func _pad_local(pid: String) -> Vector3:
	return ws.drone_root.to_local(_pad_world(pid))


func _pad_at(mp: Vector2) -> String:
	var o := ws.camera.project_ray_origin(mp)
	var d := ws.camera.project_ray_normal(mp)
	var r := maxf(0.55, ws.cam_dist * 0.021)
	var best := ""
	var best_d := r * r
	for pid in _pads:
		var c := _pad_world(pid)
		var oc := c - o
		var t := oc.dot(d)
		if t < 0.0:
			continue
		var d2 := oc.length_squared() - t * t
		if d2 <= best_d:
			best_d = d2
			best = pid
	return best


# --- cables -----------------------------------------------------------------------------------
func _connected_wire(pid: String) -> String:
	for id in Game.wires:
		var w: Dictionary = Parts.WIRES[id]
		if w["a"] == pid or w["b"] == pid:
			return id
	return ""


func _wire_path(id: String) -> PackedVector3Array:
	var w: Dictionary = Parts.WIRES[id]
	var a := _pad_local(w["a"])
	var b := _pad_local(w["b"])
	var dir: Vector3 = w["dir"]
	var bulge: float = w["bulge"]
	return MeshFactory.bezier(a, a + dir * bulge, b + dir * bulge, b, 18)


func _refresh_cables() -> void:
	for id in _cables.keys():
		if is_instance_valid(_cables[id]):
			_cables[id].queue_free()
	_cables.clear()
	if not active or _pads.is_empty():
		return
	for id in Game.wires:
		var w: Dictionary = Parts.WIRES[id]
		var radius := 0.17 if id.begins_with("bat") else 0.1
		var mat := MeshFactory.mat(w["color"], 0.0, 0.5)
		var tube := MeshFactory.tube(_wire_path(id), radius, mat)
		ws.drone_root.add_child(tube)
		_cables[id] = tube
	# lit pad markers for connected pads
	for pid in _pads:
		var conn := _connected_wire(pid) != ""
		var m: StandardMaterial3D = _pads[pid]["mat"]
		m.emission_energy_multiplier = 0.4 if conn else 1.4
		m.albedo_color = (_pads[pid]["base"] as Color).darkened(0.5) if conn else _pads[pid]["base"]


func _make_motor_leads() -> void:
	# Motor leads are pre-soldered: three thin cables from each ESC M pad running along the arm.
	var fid: String = Game.placed.get("frame", "frame_5")
	var copper := MeshFactory.mat(Color(0.8, 0.42, 0.12), 0.6, 0.35)
	for i in 4:
		var pid := "esc.M%d" % (i + 1)
		if not _pads.has(pid):
			continue
		var pad_p := _pad_local(pid)
		var slot := Parts.slot_by_name(fid, "motor_%d" % (i + 1))
		var tip: Vector3 = slot["pos"]
		var dir := Vector3(tip.x, 0, tip.z).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		for k in 3:
			var off := side * (k - 1) * 0.28
			var pts := PackedVector3Array()
			pts.append(pad_p)
			pts.append(Vector3(pad_p.x, 0.75, pad_p.z) + off * 0.3)
			var start := Vector3(pad_p.x * 1.15, 0.65, pad_p.z * 1.0) + off
			pts.append(start)
			var n := 6
			for j in n + 1:
				var f := float(j) / n
				pts.append(start.lerp(Vector3(tip.x, 0.65, tip.z) - dir * 1.2 + off, f))
			var t := MeshFactory.tube(pts, 0.08, copper)
			ws.drone_root.add_child(t)
			_motor_leads.append(t)


func _refresh_checks() -> void:
	var done := true
	for id in Parts.WIRES:
		var ok := Game.wires.has(id)
		var l: Label = _check[id]
		var req: bool = Parts.WIRES[id]["required"]
		l.text = ("[x]  " if ok else ("[ ]  " if req else "[ ]  ")) + Parts.WIRES[id]["label"]
		l.add_theme_color_override("font_color", UITheme.GOOD if ok else (UITheme.TEXT if req else UITheme.MUTED))
		if req and not ok:
			done = false
	_next_btn.disabled = not done


# --- interaction ----------------------------------------------------------------------------
func cancel_pending() -> bool:
	if _pending == "":
		return false
	_set_pending("")
	return true


func _set_pending(pid: String) -> void:
	_pending = pid


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("interact"):
		_click(ws.get_viewport().get_mouse_position())


func _click(mp: Vector2) -> void:
	var pid := _pad_at(mp)
	if _pending == "":
		if pid == "":
			return
		var wid := _connected_wire(pid)
		if wid != "":
			Game.wires.erase(wid)
			_refresh_cables()
			_refresh_checks()
			Game.save_drone()
			Audio.play("snap", 0.8)
			ws.say("Unplugged: %s" % Parts.WIRES[wid]["label"])
			return
		_set_pending(pid)
		Audio.play("click", 1.3)
		ws.say("From %s - now click the pad it connects to." % _pad_name(pid), false, 2.5)
		return
	if pid == "":
		_set_pending("")
		return
	var a := _pending
	_set_pending("")
	var res := Parts.check_connection(a, pid)
	if not res["ok"]:
		_flash_bad(a, pid)
		ws.say(res["reason"], false, 4.0)
		Audio.play("error")
		return
	if Game.wires.has(res["wire"]):
		ws.say("Already connected.")
		return
	# the target pad of an existing wire could already be used by a different wire (not possible with the fixed harness)
	Game.wires.append(res["wire"])
	_refresh_cables()
	_refresh_checks()
	Game.save_drone()
	Audio.play("wire")
	if Game.wiring_complete():
		ws.say("Wiring complete - on to SETUP!", true)
	else:
		ws.say("Connected: %s" % Parts.WIRES[res["wire"]]["label"], true, 2.5)


func _pad_name(pid: String) -> String:
	return "%s %s" % [pid.get_slice(".", 0).to_upper().replace("BAT", "BATTERY"), Parts.PADS[pid]["label"]]


func _flash_bad(a: String, b: String) -> void:
	var path := MeshFactory.bezier(_pad_local(a), _pad_local(a) + Vector3(0, 1.5, 0), _pad_local(b) + Vector3(0, 1.5, 0), _pad_local(b), 10)
	var m := MeshFactory.mat(Color(1.0, 0.1, 0.1), 0.0, 0.5, 2.0)
	var t := MeshFactory.tube(path, 0.12, m)
	ws.drone_root.add_child(t)
	_flash.append({"node": t, "time": 0.7})
	for pid in [a, b]:
		_pads[pid]["mat"].albedo_color = Color(1.0, 0.0, 0.0)
		_pads[pid]["mat"].emission = Color(1.0, 0.0, 0.0)
		_pads[pid]["mat"].emission_energy_multiplier = 4.0
	get_tree().create_timer(0.7).timeout.connect(func():
		if active:
			for pid in [a, b]:
				if _pads.has(pid):
					_pads[pid]["mat"].emission = _pad_color(Parts.PADS[pid]["kind"])
			_refresh_cables())


func _process(dt: float) -> void:
	_t += dt
	if not active:
		return
	# keep cables attached while the stack is animating
	if _anim_time > 0.0:
		_anim_time -= dt
		_refresh_cables()
		for l in _motor_leads:
			l.queue_free()
		_motor_leads.clear()
		_make_motor_leads()
	for i in range(_flash.size() - 1, -1, -1):
		_flash[i]["time"] -= dt
		if _flash[i]["time"] <= 0.0:
			if is_instance_valid(_flash[i]["node"]):
				_flash[i]["node"].queue_free()
			_flash.remove_at(i)
	var mp := ws.get_viewport().get_mouse_position()
	_hover = _pad_at(mp)
	for pid in _pads:
		var n: MeshInstance3D = _pads[pid]["node"]
		var k := 1.0
		if pid == _hover:
			k = 1.7
		if pid == _pending:
			k = 1.5 + 0.35 * sin(_t * 9.0)
		n.scale = n.scale.lerp(Vector3.ONE * k, 0.35)
	if _hover != "":
		var wid := _connected_wire(_hover)
		_tip.text = "%s%s" % [_pad_name(_hover), ("   (click to unplug)" if wid != "" else "")]
		_tip.reset_size()
		_tip.position = mp + Vector2(18, 16)
		_tip.visible = true
	else:
		_tip.visible = false
