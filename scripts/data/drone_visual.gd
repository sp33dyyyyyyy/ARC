class_name DroneVisual
extends RefCounted
## Assembles a complete drone model from a placement dictionary.


static func default_placement() -> Dictionary:
	var d := {"frame": "frame_5", "esc": "esc_4in1", "fc": "fc_f4", "rx": "rx_24", "vtx": "vtx_25", "antenna": "ant_pagoda",
		"cam_mount": "mount_20", "cam": "cam_fpv", "battery": "bat_1500"}
	for i in 4:
		var dir: String = Parts.MOTOR_SPIN[i].to_lower()
		d["motor_%d" % (i + 1)] = "motor_2306_%s" % dir
		d["prop_%d" % (i + 1)] = "prop_5143_%s" % dir
	return d


## Returns a Node3D whose children are named after their slots and sit at the slot positions.
## `cond` (slot -> 0..1) darkens and bends damaged parts; `paint` tints the frame.
static func assemble(placed: Dictionary, broken: Dictionary = {}, cond: Dictionary = {}, paint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var root := Node3D.new()
	if not placed.has("frame"):
		return root
	var frame_id: String = placed["frame"]
	for s in Parts.slots_for(frame_id):
		if not placed.has(s["name"]):
			continue
		var node := MeshFactory.make_part(placed[s["name"]], frame_id, broken.get(s["name"], false))
		node.name = s["name"]
		node.position = s["pos"]
		for l in node.find_children("*", "Label3D", true, false):
			l.visible = false
		root.add_child(node)
		apply_condition(node, float(cond.get(s["name"], 1.0)), s["name"].hash())
	if placed.has("cam") and placed.has("cam_mount"):
		set_cam_tilt(root, float(Parts.part(placed["cam_mount"]).get("tilt", 20.0)))
	if paint.a > 0.0:
		apply_paint(root, paint)
	return root


static func set_cam_tilt(root: Node3D, deg: float) -> void:
	var cam := root.get_node_or_null("cam")
	if cam == null:
		return
	var t := cam.get_node_or_null("Tilt")
	if t:
		t.rotation_degrees.x = deg


## Tints the frame's carbon parts with a paint colour.
static func apply_paint(root: Node3D, paint: Color) -> void:
	var f := root.get_node_or_null("frame")
	if f == null:
		return
	var m := MeshFactory.mat(paint, 0.35, 0.45)
	for mi in f.find_children("*", "MeshInstance3D", true, false):
		var cur = mi.material_override
		if cur is StandardMaterial3D and (cur as StandardMaterial3D).albedo_color.v < 0.3:
			mi.material_override = m


## Scorches and slightly bends a damaged part (purely visual).
static func apply_condition(node: Node3D, c: float, seed_v: int) -> void:
	if c >= 0.85:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var dmg := 1.0 - c
	var ov := StandardMaterial3D.new()
	ov.albedo_color = Color(0.08, 0.05, 0.03, clampf(dmg * 0.85, 0.15, 0.7))
	ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ov.roughness = 1.0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = ov
	node.rotation_degrees += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * dmg * 14.0
	node.set_meta("damaged", true)
