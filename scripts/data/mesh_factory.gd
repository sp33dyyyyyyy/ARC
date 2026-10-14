class_name MeshFactory
extends RefCounted
## Procedural low-poly meshes for every part, plus workbench materials.
## All part meshes are authored with forward = -Z, origin at the bottom-centre
## (props: at the hub plane). Units are centimetres.

static var _mats: Dictionary = {}

const GOLD := Color(0.9, 0.7, 0.15)
const CARBON := Color(0.055, 0.055, 0.065)


# --- materials ----------------------------------------------------------------
static func mat(color: Color, metallic: float = 0.0, rough: float = 0.6, emit: float = 0.0, alpha: float = 1.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [color.to_html(true), metallic, rough, emit, alpha, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


# --- primitives -------------------------------------------------------------------
static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO, segments: int = 16, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label3d(parent: Node3D, text: String, size_cm: float, pos: Vector3, color: Color = Color.WHITE, group: String = "", billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = size_cm / 48.0
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	if group != "":
		l.add_to_group(group)
	parent.add_child(l)
	return l


## Curved arrow showing a spin direction when viewed from above.
static func spin_arrow(cw: bool, radius: float, color: Color, thick: float = 0.1, emit: float = 0.0) -> Node3D:
	var root := Node3D.new()
	var m := mat(color, 0.0, 0.5, emit)
	var sweep := deg_to_rad(250.0)
	var dir := -1.0 if cw else 1.0
	var a0 := deg_to_rad(30.0) if not cw else deg_to_rad(30.0) + sweep
	var steps := 12
	var dphi := sweep / steps
	for i in steps:
		var phi := a0 + dir * dphi * (i + 0.5)
		var p := Vector3(radius * cos(phi), 0, -radius * sin(phi))
		var t := dir * Vector3(-sin(phi), 0, -cos(phi))
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(thick, thick * 0.8, radius * dphi * 1.15)
		b.mesh = bm
		b.material_override = m
		b.transform = Transform3D(Basis.looking_at(t, Vector3.UP), p)
		root.add_child(b)
	var phi_e := a0 + dir * sweep
	var pe := Vector3(radius * cos(phi_e), 0, -radius * sin(phi_e))
	var te := dir * Vector3(-sin(phi_e), 0, -cos(phi_e))
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = thick * 2.4
	hm.height = thick * 5.0
	hm.radial_segments = 8
	hm.rings = 1
	head.mesh = hm
	head.material_override = m
	head.transform = Transform3D(Basis(Quaternion(Vector3.UP, te)), pe + te * thick * 2.0)
	root.add_child(head)
	return root


## Flat arrow lying in the XZ plane pointing towards -Z.
static func flat_arrow(length: float, width: float, color: Color, emit: float = 0.0, thick: float = 0.06) -> Node3D:
	var root := Node3D.new()
	var m := mat(color, 0.0, 0.5, emit)
	var shaft_len := length * 0.55
	box(root, Vector3(width * 0.35, thick, shaft_len), Vector3(0, 0, shaft_len * 0.5 - length * 0.5 + length * 0.45), m)
	var head := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(width, length * 0.45, thick)
	head.mesh = pm
	head.material_override = m
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0, 0, -length * 0.5 + length * 0.225)
	root.add_child(head)
	return root


## A cable: a thin tube following `points`.
static func tube(points: PackedVector3Array, radius: float, material: Material, sides: int = 6) -> MeshInstance3D:
	var n := points.size()
	var mi := MeshInstance3D.new()
	if n < 2:
		return mi
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in n:
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		var ref := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var u := t.cross(ref).normalized()
		var v := t.cross(u).normalized()
		var ring: Array = []
		for s in sides:
			var ang := TAU * s / sides
			ring.append(points[i] + (u * cos(ang) + v * sin(ang)) * radius)
		rings.append(ring)
	for i in n - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a: Vector3 = rings[i][s]
			var b: Vector3 = rings[i][s2]
			var c: Vector3 = rings[i + 1][s]
			var d: Vector3 = rings[i + 1][s2]
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	mi.mesh = st.commit()
	var mm: Material = material
	if material is StandardMaterial3D:
		mm = material.duplicate()
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mm
	return mi


static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, steps: int = 16) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3)
	return out


# --- parts ----------------------------------------------------------------------------
static func make_part(id: String, frame_id: String = "frame_5", broken: bool = false) -> Node3D:
	var p := Parts.part(id)
	var root: Node3D
	match p["cat"]:
		"frame": root = make_frame(id)
		"motor": root = make_motor(id)
		"prop": root = make_prop(id, frame_id, broken)
		"esc": root = make_esc()
		"fc": root = make_fc()
		"vtx": root = make_vtx()
		"cam": root = make_cam()
		"battery": root = make_battery(id)
		_: root = Node3D.new()
	root.set_meta("part_id", id)
	return root


## Rough bounding radius (cm) and the centre of the part (for the parts tray).
static func bounds(id: String) -> Dictionary:
	match Parts.part(id)["cat"]:
		"frame": return {"r": 13.0 * (Parts.part(id)["arm"] / 7.95), "c": Vector3(0, 2.0, 0)}
		"motor": return {"r": 2.2, "c": Vector3(0, 1.25, 0)}
		"prop": return {"r": 6.5, "c": Vector3(0, 0.3, 0)}
		"esc": return {"r": 2.7, "c": Vector3(0, 0.3, 0)}
		"fc": return {"r": 2.7, "c": Vector3(0, 0.3, 0)}
		"vtx": return {"r": 3.9, "c": Vector3(0, 0.4, 1.4)}
		"cam": return {"r": 2.0, "c": Vector3(0, 1.0, 0)}
		"battery": return {"r": 5.2, "c": Vector3(0, 1.4, 0.6)}
	return {"r": 3.0, "c": Vector3.ZERO}


static func _pad(parent: Node3D, pad_id: String, labels: bool = true) -> void:
	var pd: Dictionary = Parts.PADS[pad_id]
	var col := GOLD
	match pd["kind"]:
		"pwr+": col = Color(0.95, 0.35, 0.2)
		"pwr-": col = Color(0.55, 0.55, 0.6)
	box(parent, Vector3(0.42, 0.07, 0.42), pd["pos"], mat(col, 0.8, 0.3))
	if labels:
		label3d(parent, pd["label"], 0.42, pd["pos"] + Vector3(0, 0.62, 0), Color(1, 1, 0.85), "pad_label")


static func make_frame(id: String) -> Node3D:
	var f: Dictionary = Parts.part(id)
	var o: float = f["arm"]
	var root := Node3D.new()
	var carbon := mat(CARBON, 0.45, 0.4)
	var sc: float = clampf(o / 7.95, 0.82, 1.35)
	var plate := Vector3(5.0 * sc, 0.35, 9.0 * sc)
	box(root, plate, Vector3(0, 0.175, 0), carbon)
	for i in 4:
		var sg: Vector2 = Parts.MOTOR_SIGNS[i]
		var tip := Vector3(o * sg.x, 0, o * sg.y)
		var dir := tip.normalized()
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(1.0 * sc, 0.4, tip.length())
		arm.mesh = am
		arm.material_override = carbon
		arm.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), tip * 0.5 + Vector3(0, 0.2, 0))
		root.add_child(arm)
		cyl(root, 1.6 * sc, 0.4, tip + Vector3(0, 0.2, 0), carbon, Vector3.ZERO, 20)
	# standoffs
	var gold := mat(Color(0.95, 0.72, 0.1), 0.9, 0.25)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			cyl(root, 0.2, 5.1, Vector3(1.525 * sx, 0.35 + 2.55, 1.525 * sz), gold, Vector3.ZERO, 10)
	# camera cage plates (nose)
	var cz := -o * 0.7
	for sx in [-1, 1]:
		box(root, Vector3(0.3, 2.6, 2.2), Vector3(1.35 * sx, 0.35 + 1.3, cz), carbon)
	# top plate (separate node so the WIRE stage can lift it off)
	var top := Node3D.new()
	top.name = "TopPlate"
	top.position = Vector3(0, 5.4, 0)
	box(top, Vector3(4.4 * sc, 0.35, 8.0 * sc), Vector3(0, 0.175, 0), carbon)
	for sz in [-1.8, 1.8]:
		box(top, Vector3(3.7 * sc, 0.4, 0.5), Vector3(0, 0.2, sz), mat(Color(0.12, 0.12, 0.14), 0.0, 0.9))
	var nose := flat_arrow(2.2, 1.6, Color(1, 1, 1), 0.3)
	nose.position = Vector3(0, 0.37, -3.0 * sc)
	top.add_child(nose)
	root.add_child(top)
	var nose2 := flat_arrow(2.2, 1.6, Color(1, 1, 1), 0.3)
	nose2.position = Vector3(0, 0.37, -3.6 * sc)
	root.add_child(nose2)
	return root


static func make_motor(id: String) -> Node3D:
	var m: Dictionary = Parts.part(id)
	var s: float = m["size"]
	var root := Node3D.new()
	var steel := mat(Color(0.7, 0.7, 0.75), 0.9, 0.3)
	var dark := mat(Color(0.12, 0.12, 0.14), 0.6, 0.4)
	var bell: Color = m["color"]
	cyl(root, 1.35 * s, 0.5, Vector3(0, 0.25, 0), dark, Vector3.ZERO, 20)
	cyl(root, 1.0 * s, 0.6, Vector3(0, 0.8, 0), mat(Color(0.8, 0.45, 0.2), 0.8, 0.35), Vector3.ZERO, 16)
	cyl(root, 1.5 * s, 1.0, Vector3(0, 1.6, 0), mat(bell, 0.85, 0.28), Vector3.ZERO, 24)
	cyl(root, 1.5 * s, 0.1, Vector3(0, 2.15, 0), dark, Vector3.ZERO, 24)
	cyl(root, 0.3, 0.3, Vector3(0, 2.35, 0), mat(GOLD, 0.9, 0.2), Vector3.ZERO, 10)
	var arrow := spin_arrow(m["spin"] == "CW", 1.1 * s, Color(1, 1, 1), 0.09, 0.5)
	arrow.position = Vector3(0, 2.22, 0)
	arrow.add_to_group("spin_arrow")
	root.add_child(arrow)
	return root


## Prop: origin at the hub plane. `frame_id` scales it to the frame's prop size.
static func make_prop(id: String, frame_id: String = "frame_5", broken: bool = false) -> Node3D:
	var p: Dictionary = Parts.part(id)
	var f: Dictionary = Parts.part(frame_id)
	var root := Node3D.new()
	var spin_cw: bool = p["spin"] == "CW"
	var scale_f: float = f["prop_in"] / 5.0
	var radius: float = p["diam"] * 2.54 * 0.5 * scale_f
	var col: Color = p["color"]
	var blade_mat := mat(col, 0.0, 0.35, 0.25)
	cyl(root, 0.6, 0.5, Vector3(0, 0.25, 0), mat(Color(0.08, 0.08, 0.09), 0.5, 0.4), Vector3.ZERO, 12)
	var n: int = p["blades"]
	for b in n:
		var ang := TAU * b / n
		var length := radius - 0.5
		var w := 1.2 * scale_f + 0.2
		if broken and b == 0:
			length *= 0.4
		if broken and b == 1 and n == 3:
			continue
		var holder := Node3D.new()
		holder.rotation = Vector3(0, ang, 0)
		root.add_child(holder)
		var pitch := 22.0 * (-1.0 if spin_cw else 1.0)
		box(holder, Vector3(length, 0.08, w), Vector3(0.5 + length * 0.5, 0.42, 0), blade_mat, Vector3(pitch, 0, 0))
		if not (broken and b == 0):
			box(holder, Vector3(0.8, 0.08, w * 0.7), Vector3(0.5 + length - 0.2, 0.42, 0), blade_mat, Vector3(pitch, 0, 0))
	var arrow := spin_arrow(spin_cw, 0.95, Color(1, 1, 1), 0.07, 0.6)
	arrow.position = Vector3(0, 0.62, 0)
	arrow.add_to_group("spin_arrow")
	root.add_child(arrow)
	root.set_meta("radius", radius)
	return root


static func _pcb(parent: Node3D, w: float, d: float, color: Color) -> void:
	box(parent, Vector3(w, 0.25, d), Vector3(0, 0.125, 0), mat(color, 0.2, 0.5))
	var ring := mat(GOLD, 0.9, 0.3)
	if w > 3.0:
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				cyl(parent, 0.36, 0.27, Vector3(1.525 * sx, 0.135, 1.525 * sz), ring, Vector3.ZERO, 10)


static func make_esc() -> Node3D:
	var root := Node3D.new()
	_pcb(root, 3.6, 3.6, Color(0.04, 0.04, 0.05))
	var chip := mat(Color(0.015, 0.015, 0.02), 0.3, 0.35)
	for i in 4:
		var x := -1.05 + 0.7 * i
		box(root, Vector3(0.62, 0.18, 0.62), Vector3(x, 0.34, -0.5), chip)
		label3d(root, "ESC%d" % (i + 1), 0.28, Vector3(x, 0.75, -0.5), Color(0.7, 0.9, 1.0), "chip_label")
	for pid in Parts.PADS:
		if Parts.PADS[pid]["cat"] == "esc":
			_pad(root, pid)
	# bulk capacitor lying near the C BAT pad
	cyl(root, 0.42, 1.0, Vector3(0.9, 0.55, 1.0), mat(Color(0.1, 0.1, 0.12), 0.4, 0.4), Vector3(90, 0, 0), 12)
	var arrow := flat_arrow(1.1, 0.9, Color(1, 1, 1), 0.4)
	arrow.position = Vector3(0, 0.27, 0.65)
	root.add_child(arrow)
	return root


static func make_fc() -> Node3D:
	var root := Node3D.new()
	_pcb(root, 3.6, 3.6, Color(0.05, 0.1, 0.28))
	box(root, Vector3(1.0, 0.15, 1.0), Vector3(0.6, 0.33, 0.5), mat(Color(0.015, 0.015, 0.02), 0.3, 0.35))
	box(root, Vector3(0.55, 0.14, 0.55), Vector3(-0.55, 0.32, 0.1), mat(Color(0.02, 0.02, 0.03), 0.3, 0.3))
	sphere(root, 0.07, Vector3(-0.75, 0.42, -0.1), mat(Color.WHITE, 0.0, 0.5, 1.0))
	label3d(root, "GYRO", 0.3, Vector3(-0.55, 0.8, 0.1), Color(1.0, 0.8, 0.4), "chip_label")
	box(root, Vector3(0.9, 0.35, 0.7), Vector3(0, 0.42, 1.45), mat(Color(0.75, 0.75, 0.8), 0.9, 0.3))
	for pid in Parts.PADS:
		if Parts.PADS[pid]["cat"] == "fc":
			_pad(root, pid)
	var arrow := flat_arrow(1.1, 0.9, Color(1, 1, 1), 0.4)
	arrow.position = Vector3(0.3, 0.27, -0.35)
	root.add_child(arrow)
	return root


static func make_vtx() -> Node3D:
	var root := Node3D.new()
	_pcb(root, 2.6, 2.6, Color(0.14, 0.03, 0.2))
	box(root, Vector3(1.4, 0.45, 1.4), Vector3(0.15, 0.48, -0.1), mat(Color(0.8, 0.8, 0.85), 0.95, 0.25))
	cyl(root, 0.22, 0.6, Vector3(0, 0.45, 1.4), mat(GOLD, 0.9, 0.3), Vector3(90, 0, 0), 8)
	var dir := Vector3(0, sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)))
	var pivot := Vector3(0, 0.45, 1.7)
	cyl(root, 0.09, 5.0, pivot + dir * 2.5, mat(Color(0.03, 0.03, 0.03), 0.2, 0.5), Vector3(70, 0, 0), 8)
	cyl(root, 0.17, 0.8, pivot + dir * 5.0, mat(Color(0.9, 0.9, 0.9), 0.0, 0.6), Vector3(70, 0, 0), 8)
	for pid in Parts.PADS:
		if Parts.PADS[pid]["cat"] == "vtx":
			_pad(root, pid)
	var arrow := flat_arrow(0.9, 0.7, Color(1, 1, 1), 0.4)
	arrow.position = Vector3(-0.6, 0.27, -0.6)
	root.add_child(arrow)
	return root


static func make_cam() -> Node3D:
	var root := Node3D.new()
	var tilt := Node3D.new()
	tilt.position = Vector3(0, 1.0, 0)
	tilt.rotation_degrees = Vector3(20, 0, 0)
	root.add_child(tilt)
	var plastic := mat(Color(0.05, 0.05, 0.06), 0.2, 0.5)
	box(tilt, Vector3(2.0, 2.0, 1.4), Vector3.ZERO, plastic)
	cyl(tilt, 0.7, 0.8, Vector3(0, 0, -1.0), mat(Color(0.12, 0.12, 0.14), 0.6, 0.3), Vector3(90, 0, 0), 16)
	cyl(tilt, 0.55, 0.05, Vector3(0, 0, -1.43), mat(Color(0.1, 0.25, 0.55), 0.0, 0.1, 0.6), Vector3(90, 0, 0), 16)
	for sx in [-1, 1]:
		box(root, Vector3(0.2, 1.7, 1.2), Vector3(1.1 * sx, 1.0, 0), mat(Color(1.0, 0.4, 0.05), 0.8, 0.3))
	for pid in Parts.PADS:
		if Parts.PADS[pid]["cat"] == "cam":
			_pad(root, pid)
	var arrow := flat_arrow(0.9, 0.8, Color(1, 1, 1), 0.4)
	arrow.position = Vector3(0, 2.15, 0)
	root.add_child(arrow)
	return root


static func make_battery(id: String) -> Node3D:
	var b: Dictionary = Parts.part(id)
	var root := Node3D.new()
	var len_scale: float = clampf(float(b["mah"]) / 1500.0, 0.8, 1.35)
	var body := Vector3(3.6, 2.8, 7.5 * len_scale)
	box(root, body, Vector3(0, 1.4, 0), mat(Color(0.04, 0.1, 0.42), 0.1, 0.35))
	box(root, Vector3(3.0, 0.03, 5.2 * len_scale), Vector3(0, 2.81, 0), mat(Color(0.92, 0.92, 0.95), 0.0, 0.6))
	var lab := label3d(root, "4S %dmAh" % int(b["mah"]), 0.55, Vector3(0, 2.86, 0), Color(0.05, 0.05, 0.1), "", false)
	lab.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(0, 2.86, 0.3))
	lab.outline_size = 0
	var strap := mat(Color(0.1, 0.1, 0.12), 0.0, 0.9)
	for sz in [-1.8, 1.8]:
		box(root, Vector3(3.7, 2.9, 0.5), Vector3(0, 1.4, sz * len_scale), strap)
	var half := body.z * 0.5
	for sx in [-1, 1]:
		var col := Color(0.9, 0.1, 0.1) if sx < 0 else Color(0.06, 0.06, 0.06)
		cyl(root, 0.18, 5.0 - half, Vector3(0.6 * sx, 1.4, (half + 5.0) * 0.5), mat(col, 0.0, 0.5), Vector3(90, 0, 0), 8)
		box(root, Vector3(0.6, 0.6, 0.5), Vector3(0.6 * sx, 1.4, 4.8), mat(Color(0.95, 0.8, 0.1), 0.2, 0.4))
	for pid in ["bat.RED", "bat.BLACK"]:
		_pad(root, pid)
	var arrow := flat_arrow(1.2, 1.0, Color(1, 1, 1), 0.3)
	arrow.position = Vector3(0, 2.86, -2.6 * len_scale)
	root.add_child(arrow)
	return root


# --- workbench ---------------------------------------------------------------------------
static func mat_grid_material(size: Vector2) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec2 size = vec2(60.0, 40.0);
uniform vec3 base_color : source_color = vec3(0.03, 0.2, 0.11);
void fragment() {
	vec2 p = UV * size;
	vec2 fw = fwidth(p);
	vec2 g1 = abs(fract(p - 0.5) - 0.5) / fw;
	float l1 = (1.0 - min(min(g1.x, g1.y), 1.0)) * (1.0 - smoothstep(0.08, 0.25, fw.x));
	vec2 q = p / 5.0;
	vec2 g5 = abs(fract(q - 0.5) - 0.5) / (fw / 5.0);
	float l5 = 1.0 - min(min(g5.x, g5.y), 1.0);
	vec2 e = min(p, size - p) / fw;
	float edge = 1.0 - min(min(e.x, e.y) / 3.0, 1.0);
	vec3 c = base_color + vec3(0.035, 0.06, 0.04) * l1 + vec3(0.18, 0.3, 0.22) * l5;
	c = mix(c, vec3(0.9, 0.95, 0.9), clamp(edge, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("size", size)
	return m


static func wood_texture(w: int = 256, h: int = 256, planks: int = 4, base: Color = Color(0.52, 0.32, 0.16)) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.02
	var pw := float(w) / planks
	for y in h:
		for x in w:
			var plank := int(x / pw)
			var lx := fmod(float(x), pw)
			var n := noise.get_noise_2d(float(x) * 0.6 + plank * 91.0, float(y) * 0.05) * 6.0
			var grain := sin((lx * 0.25 + n * 3.0) + plank * 2.0) * 0.5 + 0.5
			var shade := 0.78 + 0.28 * grain + noise.get_noise_2d(float(x) * 3.0, float(y) * 0.4) * 0.18
			var c := base * shade
			if lx < 1.5 or lx > pw - 1.5:
				c = c * 0.45
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	return ImageTexture.create_from_image(img)
