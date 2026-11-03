class_name BuildStage
extends Node
## BUILD stage: pick parts from a 3D tray (click or drag) and drop them on
## glowing slots. Blue marker = attach point, yellow marker = correct orientation.

const TRAY_H := 250.0
const SNAP_PX := 110.0
const HOLD_Y := 7.0

var ws: Workshop
var active := false

var category := "frame"
var part_nodes: Dictionary = {}     # slot name -> Node3D (installed parts)
var markers: Dictionary = {}        # slot name -> Node3D
var _marker_frame := ""

# tray
var _tray_container: SubViewportContainer
var _tray_vp: SubViewport
var _tray_cam: Camera3D
var _tray_items: Array = []
var _tray_labels: Control
var _tray_ready := false

# UI
var _ui: Control
var _check_labels: Dictionary = {}
var _cat_buttons: Dictionary = {}
var _info: Label
var _hint: Label
var _next_btn: Button
var _reset_btn: Button
var _reset_armed := false

# held part
var held: Node3D = null
var held_id := ""
var held_from := ""
var held_step := 0
var hold_mode := 0       # 0 none, 1 dragging, 2 carrying (click mode)
var _press_pos := Vector2.ZERO
var hover_slot := ""

var _fill_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D
var _yellow_mat: StandardMaterial3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var held_cond := 1.0            # condition of a part lifted off the drone
var repair_mode := false
var _repair_btn: Button
var _paint_btn: Button
var _fasten_slot := ""
var _fasten_t := 0.0
var _repair_slot := ""
var _repair_t := 0.0
var _screw_mat: StandardMaterial3D


func _ready() -> void:
	_rng.randomize()
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.albedo_color = Color(0.2, 0.55, 1.0, 0.22)
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mat = StandardMaterial3D.new()
	_line_mat.albedo_color = Color(0.25, 0.65, 1.0)
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_yellow_mat = StandardMaterial3D.new()
	_yellow_mat.albedo_color = Color(1.0, 0.9, 0.1)
	_yellow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screw_mat = MeshFactory.mat(Color(1.0, 0.8, 0.2), 0.9, 0.25, 1.2)
	_build_ui()
	_build_tray()
	_restore_from_game()
	_rebuild_markers()
	_auto_category()
	set_active(false)


# --- UI ----------------------------------------------------------------------------
func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ws.ui_root.add_child(_ui)

	# checklist (left)
	var cl := PanelContainer.new()
	cl.position = Vector2(20, 90)
	cl.custom_minimum_size = Vector2(250, 0)
	_ui.add_child(cl)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	cl.add_child(cv)
	cv.add_child(UITheme.label("PARTS", 22, UITheme.ACCENT))
	for c in Parts.CATEGORIES:
		var l := UITheme.label("", 20)
		_check_labels[c] = l
		cv.add_child(l)
	var help := UITheme.label("Drag or click a part,\nthen a glowing slot.\nR / R1  rotate held part\nGlowing screws: click\n(hold) the part to\ntighten them.\nRight-drag / R-stick orbit\nWheel / triggers zoom\nClick a tight part to\nremove it.", 15, UITheme.MUTED)
	cv.add_child(help)

	# info (right)
	var ip := PanelContainer.new()
	ip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ip.position = Vector2(1920 - 400 - 20, 90)
	ip.custom_minimum_size = Vector2(400, 0)
	ip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(ip)
	_info = UITheme.label("Hover a part for details.", 18, UITheme.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(370, 0)
	ip.add_child(_info)

	# category buttons above the tray
	var cb := HBoxContainer.new()
	cb.add_theme_constant_override("separation", 8)
	cb.position = Vector2(24, 1080 - TRAY_H - 54)
	_ui.add_child(cb)
	for c in Parts.CATEGORIES:
		var b := Button.new()
		b.text = Parts.CAT_NAMES[c]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(112, 42)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			Audio.play("click")
			show_category(c))
		_cat_buttons[c] = b
		cb.add_child(b)

	_hint = UITheme.label("", 22, UITheme.TEXT)
	_hint.position = Vector2(300, 1080 - TRAY_H - 100)
	_hint.add_theme_stylebox_override("normal", UITheme.flat(Color(0, 0, 0, 0.62), 6, Color(1, 1, 1, 0.1), 1, 10))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hint)

	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 10)
	rb.position = Vector2(1920 - 900, 1080 - TRAY_H - 172)
	_ui.add_child(rb)
	_repair_btn = UITheme.button("Repair tool: OFF", func():
		repair_mode = not repair_mode
		_repair_btn.text = "Repair tool: %s" % ("ON" if repair_mode else "OFF")
		_set_hint("Repair tool: click and hold a damaged part to restore it (costs credits)." if repair_mode else "", UITheme.ACCENT), Vector2(210, 48))
	rb.add_child(_repair_btn)
	_paint_btn = UITheme.button("Paint frame", _paint_next, Vector2(170, 48))
	rb.add_child(_paint_btn)
	_reset_btn = UITheme.button("Strip build", _on_reset, Vector2(160, 48))
	rb.add_child(_reset_btn)
	_next_btn = UITheme.accent_button("NEXT: WIRE  >>", func(): ws.switch_stage("wire"), Vector2(230, 48))
	rb.add_child(_next_btn)


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = "Really clear?"
		get_tree().create_timer(2.0).timeout.connect(func():
			_reset_armed = false
			_reset_btn.text = "Strip build")
		return
	_reset_armed = false
	_reset_btn.text = "Strip build"
	cancel_hold()
	for slot in Game.placed.keys():
		_stash(Game.placed[slot], 0.0 if Game.broken.get(slot, false) else float(Game.cond.get(slot, 1.0)))
	if Career.data["bench_drone"] != "":
		Career.remove_drone(Career.data["bench_drone"])
		Career.data["bench_drone"] = ""
	Game.reset_build()
	_restore_from_game()
	_rebuild_markers()
	_auto_category()
	refresh()
	say("Build stripped - parts are back in storage (damaged ones in the salvage bin).", true)


## Puts a part back into garage storage (or the salvage bin when damaged).
func _stash(id: String, c: float) -> void:
	if c >= 0.9:
		Career.give(id)
	else:
		Career.add_salvage(id, c)


func _paint_next() -> void:
	if not Game.placed.has("frame"):
		say("Install a frame first.")
		return
	var idx := 0
	for i in Campaign.PAINTS.size():
		if Game.paint.is_equal_approx(Campaign.PAINTS[i]["color"]):
			idx = i
	var nxt: Dictionary = Campaign.PAINTS[(idx + 1) % Campaign.PAINTS.size()]
	if not Career.spend(5, "Frame paint: %s" % nxt["name"]):
		say("Not enough credits for paint (5 cr).")
		return
	var pc: Color = nxt["color"]
	Game.paint = Color(pc.r, pc.g, pc.b, 1.0)
	_restore_from_game()
	_rebuild_markers()
	Audio.play("printer", 1.6)
	say("Frame painted %s." % nxt["name"], true)
	Game.save_drone()


func say(t: String, good: bool = false) -> void:
	ws.say(t, good)


func _set_hint(t: String, col: Color = UITheme.TEXT) -> void:
	_hint.text = t
	_hint.visible = t != ""
	_hint.add_theme_color_override("font_color", col)


# --- tray (separate 3D viewport so parts never clip into the scene) ---------------------
func _build_tray() -> void:
	_tray_container = SubViewportContainer.new()
	_tray_container.stretch = true
	_tray_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray_container.position = Vector2(0, 1080 - TRAY_H)
	_tray_container.size = Vector2(1920, TRAY_H)
	_ui.add_child(_tray_container)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.14, 0.18, 0.94)
	bg.position = _tray_container.position
	bg.size = _tray_container.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)
	_ui.move_child(bg, _tray_container.get_index())
	var edge := ColorRect.new()
	edge.color = Color(UITheme.ACCENT, 0.7)
	edge.position = _tray_container.position
	edge.size = Vector2(1920, 3)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(edge)

	_tray_vp = SubViewport.new()
	_tray_vp.own_world_3d = true
	_tray_vp.transparent_bg = true
	_tray_vp.msaa_3d = Viewport.MSAA_2X if Settings.graphics_preset >= 2 else Viewport.MSAA_DISABLED
	_tray_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_tray_vp.size = Vector2i(1920, int(TRAY_H))
	_tray_container.add_child(_tray_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_tray_vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	_tray_vp.add_child(light)
	_tray_cam = Camera3D.new()
	_tray_cam.fov = 24
	_tray_cam.position = Vector3(0, 0, 10)
	_tray_vp.add_child(_tray_cam)

	_tray_labels = Control.new()
	_tray_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray_labels.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_tray_labels)
	_tray_ready = true
	show_category(category)


func remaining(id: String) -> int:
	var r := Career.stock(id)
	if hold_mode != 0 and held_from == "" and held_id == id:
		r -= 1
	return maxi(r, 0)


func show_category(cat: String) -> void:
	category = cat
	for c in _cat_buttons:
		_cat_buttons[c].button_pressed = (c == cat)
	for it in _tray_items:
		it["pivot"].queue_free()
		it["name"].queue_free()
		it["count"].queue_free()
	_tray_items.clear()
	var ids := Parts.parts_in(cat)
	# stable, sensible order: by name
	ids.sort_custom(func(a, b): return Parts.part(a)["name"] < Parts.part(b)["name"])
	var n := ids.size()
	var spacing := 5.2
	for i in n:
		var id: String = ids[i]
		var p: Dictionary = Parts.part(id)
		var pivot := Node3D.new()
		pivot.position = Vector3((i - (n - 1) * 0.5) * spacing, 0.15, 0)
		_tray_vp.add_child(pivot)
		var holder := Node3D.new()
		pivot.add_child(holder)
		var model := MeshFactory.make_part(id, "frame_5")
		for l in model.find_children("*", "Label3D", true, false):
			l.visible = false
		var b := MeshFactory.bounds(id)
		var sc: float = 1.6 / b["r"]
		model.position = -b["c"]
		holder.add_child(model)
		holder.scale = Vector3.ONE * sc
		holder.rotation_degrees = Vector3({"frame": 50.0, "motor": 25.0, "prop": 62.0, "esc": 55.0, "fc": 55.0, "vtx": 55.0, "cam": 20.0, "battery": 38.0}.get(p["cat"], 30.0), 0, 0)
		var locked := false
		if locked:
			var ov := StandardMaterial3D.new()
			ov.albedo_color = Color(0.04, 0.04, 0.06, 0.72)
			ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				mi.material_overlay = ov
		var nl := UITheme.label(_short_name(id), 17, UITheme.TEXT if not locked else UITheme.MUTED)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.custom_minimum_size = Vector2(220, 0)
		_tray_labels.add_child(nl)
		var cl := UITheme.label("", 18, UITheme.ACCENT)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.custom_minimum_size = Vector2(80, 0)
		_tray_labels.add_child(cl)
		_tray_items.append({"id": id, "pivot": pivot, "holder": holder, "name": nl, "count": cl, "locked": locked})
	_update_tray_labels()


func _short_name(id: String) -> String:
	var n: String = Parts.part(id)["name"]
	return n.replace(" Carbon X-Frame", " X-Frame").replace(" Motor", "").replace(" Flight Controller", " FC")


func _update_tray_labels() -> void:
	if not _tray_ready:
		return
	for it in _tray_items:
		var sp: Vector2 = _tray_cam.unproject_position(it["pivot"].position)
		var nl: Label = it["name"]
		var cl: Label = it["count"]
		nl.position = _tray_container.position + sp + Vector2(-nl.custom_minimum_size.x * 0.5, 84)
		cl.position = _tray_container.position + sp + Vector2(-cl.custom_minimum_size.x * 0.5, -108)
		if it["locked"]:
			cl.text = "LOCKED"
			cl.add_theme_color_override("font_color", UITheme.BAD)
			cl.custom_minimum_size = Vector2(100, 0)
		else:
			var r := remaining(it["id"])
			cl.text = "x%d" % r if r > 0 else "none"
			cl.add_theme_color_override("font_color", UITheme.ACCENT if r > 0 else UITheme.MUTED)
		var dim: bool = it["locked"] or remaining(it["id"]) == 0
		it["holder"].visible = true
		it["pivot"].visible = true
		it["name"].modulate.a = 0.45 if dim else 1.0


# --- installed parts & markers --------------------------------------------------------
func _frame_id() -> String:
	return Game.placed.get("frame", "frame_5")


func _restore_from_game() -> void:
	for n in part_nodes.values():
		n.queue_free()
	part_nodes.clear()
	for slot_name in Game.placed:
		_spawn_installed(slot_name, Game.placed[slot_name])


func _spawn_installed(slot_name: String, id: String) -> Node3D:
	var fid: String = Game.placed.get("frame", id)
	var s := Parts.slot_by_name(fid, slot_name)
	if s.is_empty():
		return null
	var n := MeshFactory.make_part(id, fid, Game.broken.get(slot_name, false))
	n.name = slot_name
	n.position = s["pos"]
	ws.drone_root.add_child(n)
	_hide_pad_labels(n)
	part_nodes[slot_name] = n
	DroneVisual.apply_condition(n, float(Game.cond.get(slot_name, 1.0)), slot_name.hash())
	if slot_name == "frame" and Game.paint.a > 0.0:
		DroneVisual.apply_paint(ws.drone_root, Game.paint)
	if slot_name == "cam" and Game.placed.has("cam_mount"):
		DroneVisual.set_cam_tilt(ws.drone_root, float(Parts.part(Game.placed["cam_mount"]).get("tilt", 20.0)))
	_refresh_screws(slot_name)
	return n


## Local screw positions for a part category (cm).
func _screw_points(slot_name: String) -> Array:
	var id: String = Game.placed.get(slot_name, "")
	var cat: String = Parts.part(id).get("cat", "")
	var out: Array = []
	match cat:
		"motor":
			for k in 4:
				var a := PI * 0.25 + k * PI * 0.5
				out.append(Vector3(cos(a) * 1.7, 0.1, sin(a) * 1.7))
		"prop": out.append(Vector3(0, 0.8, 0))
		"esc", "fc":
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					out.append(Vector3(1.525 * sx, 0.3, 1.525 * sz))
		"vtx": out = [Vector3(-1.0, 0.3, -1.0), Vector3(1.0, 0.3, 1.0)]
		"antenna": out.append(Vector3(0, 0.0, 0.2))
		"cam_mount": out = [Vector3(-0.85, 0.28, 0.3), Vector3(0.85, 0.28, 0.3)]
		"cam": out = [Vector3(-1.25, 1.0, 0), Vector3(1.25, 1.0, 0)]
		"battery": out.append(Vector3(0, 3.0, 1.8))
		"payload": out = [Vector3(-1.4, 0.05, 0), Vector3(1.4, 0.05, 0)]
		"guard":
			var o: float = Parts.part(_frame_id()).get("arm", 7.95)
			for i in 4:
				var sg: Vector2 = Parts.MOTOR_SIGNS[i]
				out.append(Vector3(o * sg.x * 0.55, 0.6, o * sg.y * 0.55))
	return out


func _refresh_screws(slot_name: String) -> void:
	var n: Node3D = part_nodes.get(slot_name)
	if n == null:
		return
	for c in n.get_children():
		if c.name.begins_with("Screw"):
			c.queue_free()
	var left := int(Game.loose.get(slot_name, 0))
	if left <= 0:
		return
	var pts := _screw_points(slot_name)
	var first := pts.size() - left
	for k in range(maxi(first, 0), pts.size()):
		var sc := MeshFactory.cyl(n, 0.32, 0.25, pts[k] + Vector3(0, 0.55, 0), _screw_mat, Vector3.ZERO, 8)
		sc.name = "Screw%d" % k
		var slot := MeshFactory.box(sc, Vector3(0.5, 0.06, 0.1), Vector3(0, 0.13, 0), MeshFactory.mat(Color(0.1, 0.1, 0.1)))
		slot.name = "Slot"


## Drives the next loose screw of a part (with a quick screwdriver animation).
func _fasten(slot_name: String) -> void:
	var left := int(Game.loose.get(slot_name, 0))
	if left <= 0:
		return
	var n: Node3D = part_nodes.get(slot_name)
	var pts := _screw_points(slot_name)
	var count := left if Career.has_upgrade("power_driver") else 1
	for i in count:
		var k := pts.size() - left + i
		var sc: Node3D = n.get_node_or_null("Screw%d" % k) if n else null
		if sc:
			sc.name = "Driven%d" % k
			var tw := create_tween()
			tw.tween_property(sc, "position:y", sc.position.y - 0.5, 0.16).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(sc, "rotation:y", sc.rotation.y + TAU * 2.0, 0.16)
			tw.tween_callback(sc.queue_free)
	left -= count
	Audio.play("screw", randf_range(0.95, 1.1))
	Pad.rumble(0.25, 0.05, 0.07)
	if left <= 0:
		Game.loose.erase(slot_name)
		Audio.play("snap", 1.3)
		say("%s secured." % Parts.part(Game.placed[slot_name])["name"], true)
		if Game.loose.is_empty() and Game.stats()["complete"]:
			_set_hint("All parts secured - continue to WIRE.", UITheme.GOOD)
	else:
		Game.loose[slot_name] = left
	Game.save_drone()


func _hide_pad_labels(n: Node) -> void:
	for l in n.find_children("*", "Label3D", true, false):
		if l.is_in_group("pad_label") or l.is_in_group("chip_label"):
			l.visible = false


## Puts every installed part back at its slot (after the WIRE stage exploded them).
func reset_layout() -> void:
	for slot_name in part_nodes:
		var s := Parts.slot_by_name(_frame_id(), slot_name)
		if not s.is_empty():
			part_nodes[slot_name].position = s["pos"]
	if part_nodes.has("frame"):
		var tp: Node3D = part_nodes["frame"].get_node_or_null("TopPlate")
		if tp:
			tp.position = Vector3(0, 5.4, 0)
			tp.visible = true


func _rebuild_markers() -> void:
	for m in markers.values():
		m.queue_free()
	markers.clear()
	_marker_frame = _frame_id()
	for s in Parts.slots_for(_marker_frame):
		var m := _make_marker(s)
		m.position = s["pos"]
		ws.drone_root.add_child(m)
		markers[s["name"]] = m
	_update_marker_visibility()


func _make_marker(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	var cat: String = s["cat"]
	var f: Dictionary = Parts.part(_marker_frame)
	var round_r := 0.0
	var rect := Vector2.ZERO
	match cat:
		"motor": round_r = 1.9
		"prop": round_r = 3.4 * (f["prop_in"] / 5.0)
		"frame": rect = Vector2(18, 18)
		"esc", "fc": rect = Vector2(4.0, 4.0)
		"vtx": rect = Vector2(3.1, 3.1)
		"battery": rect = Vector2(4.2, 8.0)
		"cam": rect = Vector2(2.6, 2.2)
	var y := 0.05
	if round_r > 0.0:
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = round_r
		cm.bottom_radius = round_r
		cm.height = 0.04
		cm.radial_segments = 32
		cm.rings = 1
		disc.mesh = cm
		disc.material_override = _fill_mat
		disc.position.y = y
		root.add_child(disc)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = round_r - 0.16
		tm.outer_radius = round_r
		tm.rings = 32
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = _line_mat
		ring.position.y = y
		root.add_child(ring)
		var arrow := MeshFactory.spin_arrow(s["spin"] == "CW", round_r * (0.62 if cat == "prop" else 0.55), Color(1.0, 0.9, 0.1), 0.17 if cat == "prop" else 0.13, 1.0)
		for mi in arrow.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = _yellow_mat
		arrow.position.y = y + 0.1
		root.add_child(arrow)
	else:
		MeshFactory.box(root, Vector3(rect.x, 0.04, rect.y), Vector3(0, y, 0), _fill_mat)
		var t := 0.12
		MeshFactory.box(root, Vector3(rect.x, 0.06, t), Vector3(0, y, -rect.y * 0.5), _line_mat)
		MeshFactory.box(root, Vector3(rect.x, 0.06, t), Vector3(0, y, rect.y * 0.5), _line_mat)
		MeshFactory.box(root, Vector3(t, 0.06, rect.y), Vector3(-rect.x * 0.5, y, 0), _line_mat)
		MeshFactory.box(root, Vector3(t, 0.06, rect.y), Vector3(rect.x * 0.5, y, 0), _line_mat)
		var arrow := MeshFactory.flat_arrow(minf(rect.y * 0.45, 3.0), minf(rect.x * 0.45, 2.2), Color(1.0, 0.9, 0.1), 1.0, 0.1)
		for mi in arrow.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = _yellow_mat
		arrow.position = Vector3(0, y + 0.08, -rect.y * 0.5 - minf(rect.y * 0.45, 3.0) * 0.5 - 0.3)
		root.add_child(arrow)
	return root


func _slot_enabled(s: Dictionary) -> bool:
	if Game.placed.has(s["name"]) and not Game.broken.get(s["name"], false):
		return false
	for r in s["requires"]:
		if not Game.placed.has(r):
			return false
	return true


func _update_marker_visibility() -> void:
	if _marker_frame != _frame_id():
		_rebuild_markers()
		return
	for s in Parts.slots_for(_marker_frame):
		var m: Node3D = markers.get(s["name"])
		if m == null:
			continue
		var vis := _slot_enabled(s) and active
		if hold_mode != 0 and held_id != "":
			vis = vis and Parts.part(held_id)["cat"] == s["cat"]
		m.visible = vis


# --- activation -------------------------------------------------------------------------
func set_active(on: bool) -> void:
	active = on
	_ui.visible = on
	if _tray_container:
		_tray_container.visible = on
		_tray_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		reset_layout()
		_restore_if_needed()
		refresh()
		_set_hint("")
		var s := Game.stats()
		if s["broken_props"] > 0:
			_set_hint("%d broken prop(s): click them to scrap, then drop fresh props on the glowing slots." % s["broken_props"], UITheme.BAD)
		elif s["complete"]:
			_set_hint("Build complete!  Continue to WIRE.", UITheme.GOOD)
	else:
		cancel_hold()
	for m in markers.values():
		m.visible = false
	if on:
		_update_marker_visibility()
	for n in part_nodes.values():
		n.visible = on or ws.stage in ["wire"] or true


func _restore_if_needed() -> void:
	# keep the nodes in sync if Game.placed was changed elsewhere
	if part_nodes.size() != Game.placed.size():
		_restore_from_game()
		_rebuild_markers()


func refresh() -> void:
	var s := Game.stats()
	for c in Parts.CATEGORIES:
		var have := 0
		for slot in Game.placed:
			if Parts.part(Game.placed[slot])["cat"] == c and not Game.broken.get(slot, false):
				have += 1
		var need: int = Parts.CAT_QUOTA[c]
		var l: Label = _check_labels[c]
		var opt: bool = c in Parts.OPTIONAL_CATS
		l.text = "%s   %d / %d%s" % [Parts.CAT_NAMES[c], have, need, "  (opt.)" if opt else ""]
		l.add_theme_color_override("font_color", UITheme.GOOD if have >= need else (UITheme.MUTED if opt else UITheme.TEXT))
	_next_btn.disabled = not (s["complete"] and s["broken_props"] == 0 and Game.loose.is_empty())
	_update_tray_labels()
	_update_marker_visibility()


func _auto_category() -> void:
	var order: Array = Parts.CATEGORIES
	var start := order.find(category)
	for k in order.size():
		var c: String = order[(start + k) % order.size()]
		var have := 0
		for slot in Game.placed:
			if Parts.part(Game.placed[slot])["cat"] == c and not Game.broken.get(slot, false):
				have += 1
		if have < Parts.CAT_QUOTA[c] and not (c in Parts.OPTIONAL_CATS):
			show_category(c)
			return
	show_category(category)


# --- input --------------------------------------------------------------------------------
func _mouse() -> Vector2:
	return ws.get_viewport().get_mouse_position()


func _in_tray(mp: Vector2) -> bool:
	return mp.y >= 1080.0 - TRAY_H


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("interact"):
		_on_press()
	elif event.is_action_released("interact"):
		_on_release()
	elif event.is_action_pressed("build_rotate") and held != null:
		held_step = (held_step + 1) % 4
		var tw := create_tween()
		tw.tween_property(held, "rotation:y", held_step * PI * 0.5, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Audio.play("click", 1.4)
		get_viewport().set_input_as_handled()


func _on_press() -> void:
	var mp := _mouse()
	if hold_mode == 2:
		_drop_held(mp)
		return
	if held != null:
		return
	if _in_tray(mp):
		var it := _tray_item_at(mp)
		if it.is_empty():
			return
		if it["locked"]:
			say("Locked.  %s" % Parts.unlock_text(it["id"]))
			Audio.play("error")
			return
		if remaining(it["id"]) <= 0:
			say("None in storage - order more in the PARTS MARKET (garage computer).")
			Audio.play("error")
			return
		_begin_hold(it["id"], "", mp)
		return
	var slot_name := _installed_at(mp)
	if slot_name != "":
		if repair_mode:
			_begin_repair(slot_name)
			return
		if int(Game.loose.get(slot_name, 0)) > 0:
			_fasten_slot = slot_name
			_fasten_t = 0.0
			_fasten(slot_name)
			return
		_pick_installed(slot_name, mp)


func _on_release() -> void:
	_fasten_slot = ""
	if _repair_slot != "":
		_repair_slot = ""
		_set_hint("Repair interrupted.", UITheme.MUTED)
	if held == null or hold_mode != 1:
		return
	var mp := _mouse()
	if mp.distance_to(_press_pos) > 14.0:
		_drop_held(mp)
	else:
		hold_mode = 2   # a click: keep carrying until the next click
		_set_hint("Carrying %s - click a glowing slot to place it (R rotates, Esc cancels)." % Parts.part(held_id)["name"], UITheme.ACCENT)


func cancel_hold() -> bool:
	if held == null:
		return false
	if held_from != "":
		_stash(held_id, held_cond)
		held_from = ""
	held.queue_free()
	held = null
	held_id = ""
	hold_mode = 0
	hover_slot = ""
	_set_hint("")
	refresh()
	return true


func _begin_hold(id: String, from_slot: String, mp: Vector2) -> void:
	held_id = id
	held_from = from_slot
	var fid: String = id if Parts.part(id)["cat"] == "frame" else _frame_id()
	held = MeshFactory.make_part(id, fid)
	_hide_pad_labels(held)
	ws.world.add_child(held)
	var cat: String = Parts.part(id)["cat"]
	held_step = 0
	if from_slot == "" and Parts.needs_orientation(cat):
		held_step = _rng.randi_range(1, 3)
	held.rotation.y = held_step * PI * 0.5
	held.scale = Vector3.ONE * 0.2
	create_tween().tween_property(held, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hold_mode = 1
	_press_pos = mp
	_place_held(mp)
	Audio.play("click", 1.2)
	if Parts.needs_orientation(cat) and from_slot == "":
		_set_hint("Press R to rotate until the part's white arrow matches the yellow marker.", UITheme.ACCENT)
	refresh()


func _pick_installed(slot_name: String, mp: Vector2) -> void:
	var id: String = Game.placed[slot_name]
	var was_broken: bool = Game.broken.get(slot_name, false)
	var c := float(Game.cond.get(slot_name, 1.0))
	var gone: Array = Parts.dependents(Game.placed, slot_name)
	for g in gone:
		_stash(Game.placed[g], 0.0 if Game.broken.get(g, false) else float(Game.cond.get(g, 1.0)))
		_remove_installed(g)
	_remove_installed(slot_name)
	Audio.play("screw", 0.8)
	if was_broken:
		Career.add_salvage(id, 0.0)
		Career.set_flag("repaired")
		say("Broken prop scrapped into the salvage bin. Drop a fresh one on the glowing slot.", true)
		Audio.play("snap", 0.7)
	else:
		_begin_hold(id, slot_name, mp)
		held_cond = c
		if c < 0.9:
			Career.set_flag("repaired")
			say("Damaged part removed (%d %%) - put it back, or drop it in the tray to send it to the salvage bin." % int(c * 100.0))
		if not gone.is_empty():
			say("%d dependent part(s) went back into storage." % gone.size())
	Game.save_drone()
	_update_marker_visibility()
	refresh()


func _remove_installed(slot_name: String) -> void:
	if part_nodes.has(slot_name):
		part_nodes[slot_name].queue_free()
		part_nodes.erase(slot_name)
	Game.placed.erase(slot_name)
	Game.broken.erase(slot_name)
	Game.cond.erase(slot_name)
	Game.loose.erase(slot_name)
	if slot_name == "frame":
		Game.wires.clear()
	elif slot_name in ["esc", "fc", "vtx", "cam", "battery"]:
		Game.wires = Game.wires.filter(func(w): return not _wire_uses(w, slot_name))


func _wire_uses(wire_id: String, slot_name: String) -> bool:
	var w: Dictionary = Parts.WIRES[wire_id]
	var pc: String = {"esc": "esc", "fc": "fc", "vtx": "vtx", "cam": "cam", "battery": "bat"}.get(slot_name, "")
	return w["a"].begins_with(pc + ".") or w["b"].begins_with(pc + ".")


func _place_held(mp: Vector2) -> void:
	if held == null:
		return
	var o := ws.camera.project_ray_origin(mp)
	var d := ws.camera.project_ray_normal(mp)
	if absf(d.y) < 0.001:
		return
	var t := (HOLD_Y - o.y) / d.y
	if t < 0.0:
		return
	held.global_position = o + d * t


func _process(dt: float) -> void:
	_t += dt
	if not active:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_fill_mat.albedo_color.a = 0.14 + 0.16 * pulse
	_line_mat.albedo_color = Color(0.25, 0.65, 1.0).lerp(Color(0.7, 0.9, 1.0), pulse)
	_yellow_mat.albedo_color = Color(1.0, 0.9, 0.1).lerp(Color(1.0, 1.0, 0.6), pulse)
	for i in _tray_items.size():
		var it: Dictionary = _tray_items[i]
		it["pivot"].rotation.y += dt * 0.6
	_update_tray_labels()
	if _fasten_slot != "" and Input.is_action_pressed("interact"):
		_fasten_t += dt
		if _fasten_t > 0.22:
			_fasten_t = 0.0
			_fasten(_fasten_slot)
			if not Game.loose.has(_fasten_slot):
				_fasten_slot = ""
	if _repair_slot != "":
		_repair_t += dt
		_set_hint("Repairing %s...  %d %%" % [Parts.part(Game.placed.get(_repair_slot, ""))["name"], int(_repair_t / 1.4 * 100.0)], UITheme.ACCENT)
		if Engine.get_process_frames() % 14 == 0:
			Audio.play("screw", 1.3)
		if _repair_t >= 1.4:
			_finish_repair()
	var mp := _mouse()
	if held != null:
		_place_held(mp)
		hover_slot = _nearest_slot(mp)
		for sn in markers:
			var m: Node3D = markers[sn]
			var target := 1.18 if sn == hover_slot else 1.0
			m.scale = m.scale.lerp(Vector3.ONE * target, 0.3)
		_update_marker_visibility()
	else:
		hover_slot = ""
		_update_hover_info(mp)


func _update_hover_info(mp: Vector2) -> void:
	var id := ""
	var extra := ""
	if _in_tray(mp):
		var it := _tray_item_at(mp)
		if not it.is_empty():
			id = it["id"]
			if it["locked"]:
				extra = "\n\nLOCKED - %s" % Parts.unlock_text(id)
	else:
		var sn := _installed_at(mp)
		if sn != "":
			id = Game.placed[sn]
			var cnd := float(Game.cond.get(sn, 1.0))
			var state := "BROKEN - click to scrap" if Game.broken.get(sn, false) else ("%d loose screw(s) - click to tighten" % int(Game.loose[sn]) if Game.loose.has(sn) else "Click to remove.")
			extra = "\n\nInstalled at %s.  %s\nCondition %d %%%s" % [sn, state, int(cnd * 100.0), "" if cnd >= 0.999 or Game.broken.get(sn, false) else "  -  repair %d cr (Repair tool)" % Career.repair_cost(id, cnd)]
	if id == "":
		_info.text = "Hover a part for details."
		_info.add_theme_color_override("font_color", UITheme.MUTED)
	else:
		_info.text = _info_text(id) + extra
		_info.add_theme_color_override("font_color", UITheme.TEXT)


func _info_text(id: String) -> String:
	var p: Dictionary = Parts.part(id)
	var t: String = p["name"] + "\n" + p.get("desc", "") + "\n"
	t += "\nMass: %.0f g" % p["mass"]
	match p["cat"]:
		"frame": t += "\nMotor-to-motor: %.0f mm\nProp size: %.0f\"" % [p["arm"] * 2.0 * 1.414 * 10.0, p["prop_in"]]
		"motor": t += "\nKV: %d\nSpin: %s" % [p["kv"], p["spin"]]
		"prop": t += "\nBlades: %d   Diameter: %.1f\"\nSpin: %s" % [p["blades"], p["diam"], p["spin"]]
		"battery": t += "\nCapacity: %d mAh (4S)" % int(p["mah"])
	t += "\nPrice %d cr  •  in storage %d" % [int(p.get("price", 0)), Career.stock(id)]
	return t


# --- picking ---------------------------------------------------------------------------------
func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := c - o
	var t := oc.dot(d)
	if t < 0.0:
		return -1.0
	var dist2 := oc.length_squared() - t * t
	return t if dist2 <= r * r else -1.0


func _tray_item_at(mp: Vector2) -> Dictionary:
	var local := mp - _tray_container.position
	var o := _tray_cam.project_ray_origin(local)
	var d := _tray_cam.project_ray_normal(local)
	for it in _tray_items:
		var c: Vector3 = it["pivot"].position
		if _ray_sphere(o, d, c, 1.9) >= 0.0:
			return it
	return {}


func _installed_at(mp: Vector2) -> String:
	var o := ws.camera.project_ray_origin(mp)
	var d := ws.camera.project_ray_normal(mp)
	var best := ""
	var best_r := 1e9
	var best_t := 1e9
	for sn in part_nodes:
		var n: Node3D = part_nodes[sn]
		var id: String = Game.placed.get(sn, "")
		if id == "":
			continue
		var b := MeshFactory.bounds(id)
		var r: float = b["r"]
		if Parts.part(id)["cat"] == "prop":
			r = n.get_meta("radius", r)
		var t := _ray_sphere(o, d, n.global_position + b["c"], r * 0.8)
		if t >= 0.0 and (r < best_r - 0.01 or (absf(r - best_r) <= 0.01 and t < best_t)):
			best = sn
			best_r = r
			best_t = t
	return best


func _nearest_slot(mp: Vector2) -> String:
	var best := ""
	var best_d := SNAP_PX
	var fid := _frame_id()
	for s in Parts.slots_for(fid):
		if not Game.placed.has("frame") and s["name"] != "frame":
			continue
		var wp: Vector3 = ws.drone_root.to_global(s["pos"] + Vector3(0, 1.0, 0))
		if ws.camera.is_position_behind(wp):
			continue
		var sp := ws.camera.unproject_position(wp)
		var dist := sp.distance_to(mp)
		# prefer slots matching the held part's category
		if held_id != "" and Parts.part(held_id)["cat"] != s["cat"]:
			dist += 40.0
		if dist < best_d:
			best_d = dist
			best = s["name"]
	return best


# --- dropping ------------------------------------------------------------------------------------
func _drop_held(mp: Vector2) -> void:
	if held == null:
		return
	var slot_name := _nearest_slot(mp)
	if slot_name == "" or _in_tray(mp):
		_return_to_tray()
		return
	var s := Parts.slot_by_name(_frame_id() if Game.placed.has("frame") else "frame_5", slot_name)
	var cat: String = Parts.part(held_id)["cat"]
	var err := ""
	var replacing_broken: bool = Game.placed.has(slot_name) and Game.broken.get(slot_name, false) and cat == "prop"
	if Game.placed.has(slot_name) and not replacing_broken:
		err = "That slot is already occupied."
	if err == "":
		var tmp := Game.placed.duplicate()
		tmp.erase(slot_name)
		err = Parts.check_place(tmp, s, held_id)
	if err == "" and Parts.needs_orientation(cat) and held_step % 4 != 0:
		err = "Rotate the part (R) so its white arrow matches the yellow arrow."
	if err != "":
		_bounce(err)
		return
	_install(slot_name, s)


func _return_to_tray() -> void:
	if held_from != "":
		_stash(held_id, held_cond)
		say("%s returned to %s." % [Parts.part(held_id)["name"], "storage" if held_cond >= 0.9 else "the salvage bin"])
		held_from = ""
	var n := held
	held = null
	held_id = ""
	hold_mode = 0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector3.ONE * 0.05, 0.2)
	tw.tween_property(n, "global_position", ws.camera.project_position(Vector2(960, 1100), ws.cam_dist * 0.6), 0.2)
	tw.chain().tween_callback(n.queue_free)
	_set_hint("")
	refresh()


func _bounce(msg: String) -> void:
	Audio.play("error")
	say(msg)
	if held_from != "":
		_stash(held_id, held_cond)
		held_from = ""
	_set_hint(msg, UITheme.BAD)
	var n := held
	held = null
	held_id = ""
	hold_mode = 0
	var ov := StandardMaterial3D.new()
	ov.albedo_color = Color(1.0, 0.1, 0.1, 0.5)
	ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = ov
	var base := n.global_position
	var tw := create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(n):
			n.global_position = base + Vector3(sin(k * 60.0) * 0.8 * (1.0 - k), 0, cos(k * 47.0) * 0.5 * (1.0 - k)), 0.0, 1.0, 0.4)
	tw.tween_property(n, "global_position", ws.camera.project_position(Vector2(960, 1100), ws.cam_dist * 0.6), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.05, 0.28)
	tw.tween_callback(n.queue_free)
	refresh()


func _install(slot_name: String, s: Dictionary) -> void:
	var id := held_id
	var cat: String = Parts.part(id)["cat"]
	if part_nodes.has(slot_name):
		part_nodes[slot_name].queue_free()
		part_nodes.erase(slot_name)
	var n := held
	held = null
	held_id = ""
	hold_mode = 0
	n.queue_free()
	if held_from == "":
		if not Career.take(id):
			say("That part is no longer in storage.")
			refresh()
			return
		Game.cond.erase(slot_name)
		if cat == "battery":
			Game.bench_charge = 1.0
	else:
		if held_cond < 0.999:
			Game.cond[slot_name] = held_cond
		else:
			Game.cond.erase(slot_name)
	held_cond = 1.0
	held_from = ""
	if Game.broken.get(slot_name, false):
		Career.add_salvage(Game.placed[slot_name], 0.0)
	Game.placed[slot_name] = id
	Game.broken.erase(slot_name)
	var screws := int(Parts.SCREWS.get(cat, 0))
	if screws > 0:
		Game.loose[slot_name] = screws
	if cat == "cam_mount":
		Game.cfg["cam_angle"] = float(Parts.part(id).get("tilt", 20.0))
	var node := _spawn_installed(slot_name, id)
	if node:
		node.scale = Vector3.ONE * 1.18
		create_tween().tween_property(node, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if cat == "frame":
		_rebuild_markers()
	Audio.play("snap")
	Game.save_drone()
	_set_hint("")
	refresh()
	_advance_if_done()
	var st := Game.stats()
	if screws > 0:
		_set_hint("Click (or hold) the %s to drive its %d glowing screw%s." % [Parts.part(id)["name"], screws, "" if screws == 1 else "s"], UITheme.ACCENT)
	if st["complete"] and st["broken_props"] == 0 and Game.loose.is_empty():
		_set_hint("Build complete and secured!  Continue to WIRE.", UITheme.GOOD)
		say("Build complete - on to WIRE!", true)


func _advance_if_done() -> void:
	var have := 0
	for slot in Game.placed:
		if Parts.part(Game.placed[slot])["cat"] == category and not Game.broken.get(slot, false):
			have += 1
	if have >= Parts.CAT_QUOTA[category]:
		_auto_category()


# --- repair tool --------------------------------------------------------------------------
func _begin_repair(slot_name: String) -> void:
	var id: String = Game.placed[slot_name]
	if Game.broken.get(slot_name, false):
		say("Broken props can't be repaired - turn the Repair tool off, scrap it and fit a new one.")
		Audio.play("error")
		return
	var c := float(Game.cond.get(slot_name, 1.0))
	if c >= 0.999:
		say("%s is in perfect condition." % Parts.part(id)["name"])
		return
	if Career.credits() < Career.repair_cost(id, c):
		say("Repair needs %d cr." % Career.repair_cost(id, c))
		Audio.play("error")
		return
	_repair_slot = slot_name
	_repair_t = 0.0


func _finish_repair() -> void:
	var slot_name := _repair_slot
	_repair_slot = ""
	var id: String = Game.placed.get(slot_name, "")
	if id == "":
		return
	var c := float(Game.cond.get(slot_name, 1.0))
	if not Career.spend(Career.repair_cost(id, c), "Bench repair: %s" % Parts.part(id)["name"]):
		return
	Game.cond.erase(slot_name)
	Career.set_flag("repaired")
	if part_nodes.has(slot_name):
		part_nodes[slot_name].queue_free()
		part_nodes.erase(slot_name)
	_spawn_installed(slot_name, id)
	Audio.play("success")
	Pad.rumble(0.3, 0.1, 0.15)
	say("%s repaired to 100 %%." % Parts.part(id)["name"], true)
	_set_hint("")
	Game.save_drone()
