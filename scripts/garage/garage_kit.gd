class_name GarageKit
extends RefCounted
## Procedural mid/low-poly furniture, vehicles and materials for the garage (units: metres).
## Everything is primitives + small generated textures so it stays cheap on modest PCs.

static var _cache: Dictionary = {}


# --- textures & materials ----------------------------------------------------------
static func _noise_tex(key: String, size: int, base: Color, var_amt: float, freq: float, stains: float = 0.0) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = key.hash()
	n.frequency = freq
	n.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = key.hash() + 7
	n2.frequency = freq * 0.18
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := n.get_noise_2d(x, y) * var_amt
			var s := clampf(n2.get_noise_2d(x, y) * 2.0 - 0.3, 0.0, 1.0) * stains
			img.set_pixel(x, y, Color(base.r + v - s * 0.12, base.g + v - s * 0.11, base.b + v - s * 0.1))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func tex_mat(key: String, base: Color, var_amt: float, freq: float, uv: Vector2, rough: float = 0.85, metal: float = 0.0, stains: float = 0.0) -> StandardMaterial3D:
	var ck := "mat_%s_%s" % [key, uv]
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(key, 128, base, var_amt, freq, stains)
	m.uv1_scale = Vector3(uv.x, uv.y, 1)
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[ck] = m
	return m


static func concrete(uv: Vector2 = Vector2(4, 4)) -> StandardMaterial3D:
	return tex_mat("concrete", Color(0.47, 0.46, 0.44), 0.06, 0.09, uv, 0.92, 0.0, 1.0)


static func block_wall(uv: Vector2 = Vector2(3, 1)) -> StandardMaterial3D:
	return tex_mat("wall", Color(0.66, 0.64, 0.6), 0.035, 0.05, uv, 0.95)


static func asphalt(uv: Vector2 = Vector2(8, 2)) -> StandardMaterial3D:
	return tex_mat("asphalt", Color(0.17, 0.17, 0.18), 0.05, 0.3, uv, 0.95)


static func grass(uv: Vector2 = Vector2(12, 12)) -> StandardMaterial3D:
	return tex_mat("grass", Color(0.24, 0.36, 0.15), 0.07, 0.05, uv, 1.0)


static func cardboard() -> StandardMaterial3D:
	return tex_mat("cardboard", Color(0.62, 0.47, 0.3), 0.04, 0.4, Vector2(1, 1), 0.95)


static func wood() -> StandardMaterial3D:
	if _cache.has("wood"):
		return _cache["wood"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = MeshFactory.wood_texture(128, 128, 5, Color(0.55, 0.38, 0.22))
	m.roughness = 0.8
	_cache["wood"] = m
	return m


static func m(color: Color, metal: float = 0.0, rough: float = 0.7, emit: float = 0.0) -> StandardMaterial3D:
	return MeshFactory.mat(color, metal, rough, emit)


# --- geometry helpers ----------------------------------------------------------------
static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return MeshFactory.box(parent, size, pos, material, rot_deg)


static func cyl(parent: Node3D, r: float, h: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO, seg: int = 14) -> MeshInstance3D:
	return MeshFactory.cyl(parent, r, h, pos, material, rot_deg, seg)


## Static collider (no mesh).
static func solid(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation_degrees = rot_deg
	parent.add_child(sb)
	return sb


## Visible + solid box.
static func block(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	solid(parent, size, pos)
	return box(parent, size, pos, material)


static func label(parent: Node3D, text: String, size_px: int, pos: Vector3, color: Color = Color.WHITE, rot_y: float = 0.0, billboard: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = 0.0025
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	l.rotation.y = rot_y
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	parent.add_child(l)
	return l


# --- furniture -------------------------------------------------------------------------
## Workbench: top at y = 0.92, 3.0 x 0.85 m. Returns {root, drawers: [Node3D], cupboard_doors: [Node3D]}.
static func workbench(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var steel := m(Color(0.22, 0.3, 0.38), 0.6, 0.45)
	var dark := m(Color(0.12, 0.13, 0.14), 0.5, 0.5)
	box(root, Vector3(3.0, 0.06, 0.85), Vector3(0, 0.89, 0), wood())
	box(root, Vector3(2.2, 0.005, 0.6), Vector3(-0.2, 0.923, 0.02), m(Color(0.1, 0.35, 0.18), 0.0, 0.9))   # assembly mat
	# carcass: cupboard (left) + drawer stack (right)
	box(root, Vector3(2.9, 0.82, 0.04), Vector3(0, 0.45, -0.4), steel)
	for x in [-1.45, -0.05, 1.45]:
		box(root, Vector3(0.04, 0.82, 0.8), Vector3(x, 0.45, 0), steel)
	box(root, Vector3(2.9, 0.04, 0.8), Vector3(0, 0.06, 0), steel)
	box(root, Vector3(1.38, 0.03, 0.78), Vector3(-0.75, 0.45, 0), steel)  # cupboard shelf
	# colliders: top, back, dividers and bottom only, so the cupboard and drawers stay reachable
	solid(root, Vector3(3.0, 0.08, 0.85), Vector3(0, 0.88, 0))
	solid(root, Vector3(3.0, 0.84, 0.06), Vector3(0, 0.44, -0.4))
	for x in [-1.45, -0.05, 1.45]:
		solid(root, Vector3(0.05, 0.84, 0.8), Vector3(x, 0.44, 0))
	solid(root, Vector3(3.0, 0.06, 0.8), Vector3(0, 0.05, 0))
	solid(root, Vector3(1.38, 0.03, 0.78), Vector3(-0.75, 0.45, 0))
	var doors: Array = []
	for i in 2:
		var hinge := Node3D.new()
		hinge.position = Vector3(-1.43 + i * 1.36, 0.45, 0.41)
		root.add_child(hinge)
		var sgn := 1.0 if i == 0 else -1.0
		box(hinge, Vector3(0.68, 0.76, 0.025), Vector3(0.34 * sgn, 0, 0), steel)
		box(hinge, Vector3(0.03, 0.18, 0.03), Vector3(0.6 * sgn, 0.05, 0.03), dark)
		doors.append(hinge)
	var drawers: Array = []
	for i in 3:
		var d := Node3D.new()
		d.position = Vector3(0.7, 0.72 - i * 0.25, 0.0)
		root.add_child(d)
		box(d, Vector3(1.4, 0.22, 0.03), Vector3(0, 0, 0.41), steel)
		box(d, Vector3(0.3, 0.03, 0.03), Vector3(0, 0.04, 0.44), dark)
		box(d, Vector3(1.32, 0.02, 0.76), Vector3(0, -0.09, 0.02), dark)
		for sx in [-0.65, 0.65]:
			box(d, Vector3(0.02, 0.16, 0.76), Vector3(sx, -0.02, 0.02), dark)
		box(d, Vector3(1.32, 0.16, 0.02), Vector3(0, -0.02, -0.36), dark)
		drawers.append(d)
	# vice, lamp, bits on the top
	box(root, Vector3(0.16, 0.12, 0.2), Vector3(1.25, 1.0, 0.15), m(Color(0.15, 0.25, 0.55), 0.6, 0.4))
	return {"root": root, "drawers": drawers, "doors": doors}


## Pegboard with tool silhouettes; 2.6 x 1.1 m, origin at its centre.
static func pegboard(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	box(root, Vector3(2.6, 1.1, 0.02), Vector3.ZERO, m(Color(0.62, 0.5, 0.36), 0.0, 0.9))
	var tool := m(Color(0.15, 0.15, 0.16), 0.7, 0.35)
	var red := m(Color(0.75, 0.1, 0.08), 0.1, 0.5)
	for i in 6:
		var x := -1.1 + i * 0.22
		box(root, Vector3(0.025, 0.28 + i * 0.03, 0.02), Vector3(x, 0.15, 0.03), tool)
		box(root, Vector3(0.06, 0.1, 0.03), Vector3(x, 0.32 + i * 0.015, 0.03), red)
	for i in 4:
		cyl(root, 0.06 + i * 0.01, 0.03, Vector3(0.3 + i * 0.2, 0.25, 0.04), tool, Vector3(90, 0, 0), 10)
	box(root, Vector3(0.5, 0.04, 0.15), Vector3(0.9, -0.15, 0.08), m(Color(0.2, 0.2, 0.22), 0.4, 0.5))
	for i in 5:
		box(root, Vector3(0.06, 0.08, 0.1), Vector3(0.72 + i * 0.09, -0.09, 0.08), m(Color.from_hsv(i * 0.18, 0.6, 0.8), 0.0, 0.5))
	return root


static func desk_with_pc(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var steel := m(Color(0.25, 0.26, 0.28), 0.6, 0.4)
	box(root, Vector3(1.4, 0.05, 0.7), Vector3(0, 0.75, 0), wood())
	for sx in [-0.65, 0.65]:
		for sz in [-0.3, 0.3]:
			box(root, Vector3(0.05, 0.73, 0.05), Vector3(sx, 0.365, sz), steel)
	solid(root, Vector3(1.4, 0.78, 0.7), Vector3(0, 0.39, 0))
	# monitor
	var mon := Node3D.new()
	mon.position = Vector3(0, 0.78, -0.18)
	root.add_child(mon)
	box(mon, Vector3(0.2, 0.02, 0.16), Vector3(0, 0.01, 0), steel)
	box(mon, Vector3(0.04, 0.22, 0.04), Vector3(0, 0.12, 0), steel)
	box(mon, Vector3(0.66, 0.4, 0.04), Vector3(0, 0.42, 0), m(Color(0.07, 0.07, 0.08), 0.3, 0.4))
	var screen := MeshFactory.box(mon, Vector3(0.6, 0.35, 0.005), Vector3(0, 0.42, 0.022), m(Color(0.1, 0.35, 0.45), 0.0, 0.3, 1.6))
	screen.set_meta("no_glow", true)
	# keyboard + mouse + tower
	box(root, Vector3(0.45, 0.02, 0.15), Vector3(-0.05, 0.785, 0.12), m(Color(0.1, 0.1, 0.11), 0.2, 0.6))
	box(root, Vector3(0.06, 0.02, 0.09), Vector3(0.3, 0.785, 0.13), m(Color(0.1, 0.1, 0.11), 0.2, 0.6))
	box(root, Vector3(0.2, 0.42, 0.42), Vector3(0.5, 0.21, 0.05), m(Color(0.13, 0.13, 0.15), 0.4, 0.4))
	box(root, Vector3(0.005, 0.03, 0.03), Vector3(0.6, 0.38, 0.27), m(Color(0.3, 1.0, 0.4), 0.0, 0.3, 3.0))
	# chair
	var ch := Node3D.new()
	ch.position = Vector3(0, 0, 0.65)
	root.add_child(ch)
	var fab := m(Color(0.12, 0.13, 0.17), 0.0, 0.9)
	box(ch, Vector3(0.48, 0.08, 0.46), Vector3(0, 0.48, 0), fab)
	box(ch, Vector3(0.46, 0.5, 0.07), Vector3(0, 0.8, 0.22), fab)
	cyl(ch, 0.03, 0.42, Vector3(0, 0.24, 0), steel)
	for k in 5:
		var a := TAU * k / 5.0
		box(ch, Vector3(0.04, 0.03, 0.3), Vector3(sin(a) * 0.15, 0.04, cos(a) * 0.15), steel, Vector3(0, rad_to_deg(a), 0))
	solid(ch, Vector3(0.5, 0.9, 0.5), Vector3(0, 0.45, 0))
	return {"root": root, "screen": screen, "monitor": mon}


## Metal shelving: width x 0.5 deep x 2.0 high, 4 shelves.
static func shelving(parent: Node3D, width: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var galv := m(Color(0.6, 0.62, 0.64), 0.7, 0.45)
	for sx in [-width * 0.5 + 0.02, width * 0.5 - 0.02]:
		for sz in [-0.23, 0.23]:
			box(root, Vector3(0.035, 2.0, 0.035), Vector3(sx, 1.0, sz), galv)
	for i in 4:
		var y := 0.12 + i * 0.58
		box(root, Vector3(width, 0.025, 0.5), Vector3(0, y, 0), galv)
		solid(root, Vector3(width, 0.03, 0.5), Vector3(0, y, 0))
	solid(root, Vector3(0.05, 2.0, 0.5), Vector3(-width * 0.5, 1.0, 0))
	solid(root, Vector3(0.05, 2.0, 0.5), Vector3(width * 0.5, 1.0, 0))
	return root


## Small labelled parts bin (cardboard-coloured plastic).
static func bin(parent: Node3D, color: Color) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var mm := m(color, 0.0, 0.6)
	box(root, Vector3(0.34, 0.02, 0.38), Vector3(0, 0.01, 0), mm)
	box(root, Vector3(0.34, 0.2, 0.02), Vector3(0, 0.1, -0.18), mm)
	box(root, Vector3(0.34, 0.12, 0.02), Vector3(0, 0.06, 0.18), mm)
	for sx in [-0.16, 0.16]:
		box(root, Vector3(0.02, 0.2, 0.38), Vector3(sx, 0.1, 0), mm)
	return root


static func cardboard_box(size: Vector3, tape: bool = true) -> Node3D:
	var root := Node3D.new()
	var cb := cardboard()
	var body := MeshFactory.box(root, size, Vector3.ZERO, cb)
	body.name = "Body"
	if tape:
		box(root, Vector3(size.x + 0.002, 0.004, 0.06), Vector3(0, size.y * 0.5, 0), m(Color(0.78, 0.68, 0.45), 0.0, 0.4))
	# flaps (rotate open when unpacked)
	for i in 2:
		var hinge := Node3D.new()
		hinge.name = "Flap%d" % i
		var sgn := -1.0 if i == 0 else 1.0
		hinge.position = Vector3(0, size.y * 0.5, sgn * size.z * 0.5)
		root.add_child(hinge)
		box(hinge, Vector3(size.x, 0.006, size.z * 0.5), Vector3(0, 0.004, -sgn * size.z * 0.25), cb)
	return root


static func drone_rack(parent: Node3D, slots: int) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var dark := m(Color(0.16, 0.17, 0.18), 0.6, 0.4)
	var rows := 3
	var cols := int(ceil(float(slots) / rows))
	var w := maxf(cols * 0.62, 1.3)
	box(root, Vector3(w, 1.9, 0.04), Vector3(0, 1.15, -0.22), m(Color(0.3, 0.32, 0.33), 0.2, 0.7))
	var pos: Array = []
	for r in rows:
		var y := 0.55 + r * 0.6
		box(root, Vector3(w, 0.03, 0.42), Vector3(0, y, 0), dark)
		solid(root, Vector3(w, 0.04, 0.42), Vector3(0, y, 0))
		for c in cols:
			if pos.size() < slots:
				pos.append(Vector3(-w * 0.5 + 0.31 + c * 0.62, y + 0.02, 0))
	for sx in [-w * 0.5, w * 0.5]:
		box(root, Vector3(0.04, 1.95, 0.44), Vector3(sx, 1.15, 0), dark)
	return {"root": root, "slots": pos, "width": w}


static func charger(parent: Node3D, docks: int) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	box(root, Vector3(0.9, 0.85, 0.5), Vector3(0, 0.425, 0), m(Color(0.2, 0.22, 0.24), 0.4, 0.5))
	solid(root, Vector3(0.9, 0.85, 0.5), Vector3(0, 0.425, 0))
	box(root, Vector3(0.8, 0.12, 0.3), Vector3(0, 0.91, -0.05), m(Color(0.08, 0.08, 0.09), 0.3, 0.4))
	var _l := label(root, "CHARGING STATION", 34, Vector3(0, 0.925, 0.1), Color(1, 0.75, 0.3), 0.0)
	_l.rotation_degrees.x = -90
	var pos: Array = []
	var leds: Array = []
	for i in docks:
		var x := -0.3 + (0.6 / maxf(docks - 1, 1)) * i if docks > 1 else 0.0
		var p := Vector3(x, 0.98, -0.05)
		box(root, Vector3(0.12, 0.02, 0.16), p, m(Color(0.02, 0.02, 0.02), 0.2, 0.6))
		var led := MeshFactory.box(root, Vector3(0.02, 0.015, 0.015), p + Vector3(0, 0.0, 0.11), m(Color(0.3, 0.3, 0.3), 0.0, 0.5, 0.0))
		led.set_meta("no_glow", true)
		leds.append(led)
		pos.append(p)
	return {"root": root, "docks": pos, "leds": leds}


static func test_station(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var steel := m(Color(0.3, 0.32, 0.36), 0.6, 0.4)
	box(root, Vector3(1.2, 0.05, 0.7), Vector3(0, 0.8, 0), m(Color(0.75, 0.76, 0.78), 0.2, 0.6))
	for sx in [-0.55, 0.55]:
		for sz in [-0.3, 0.3]:
			box(root, Vector3(0.05, 0.78, 0.05), Vector3(sx, 0.39, sz), steel)
	solid(root, Vector3(1.2, 0.82, 0.7), Vector3(0, 0.41, 0))
	cyl(root, 0.25, 0.03, Vector3(-0.15, 0.84, 0.05), m(Color(0.08, 0.3, 0.12), 0.1, 0.7))   # test pad
	var _l := label(root, "DIAG", 30, Vector3(-0.15, 0.857, 0.05), Color(0.6, 1, 0.7))
	_l.rotation_degrees.x = -90
	var box_ := MeshFactory.box(root, Vector3(0.36, 0.22, 0.26), Vector3(0.38, 0.935, -0.12), m(Color(0.85, 0.55, 0.1), 0.3, 0.5))
	var scr := MeshFactory.box(root, Vector3(0.24, 0.12, 0.005), Vector3(0.38, 0.95, 0.012), m(Color(0.05, 0.25, 0.1), 0.0, 0.3, 1.4))
	scr.set_meta("no_glow", true)
	var cable := MeshFactory.tube(MeshFactory.bezier(Vector3(0.25, 0.86, -0.05), Vector3(0.1, 0.9, 0.1), Vector3(-0.05, 0.9, 0.1), Vector3(-0.12, 0.86, 0.05), 10), 0.008, m(Color(0.05, 0.05, 0.05), 0.0, 0.6))
	root.add_child(cable)
	return {"root": root, "pad": Vector3(-0.15, 0.86, 0.05), "screen": scr, "box": box_}


static func printer(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var frame := m(Color(0.1, 0.1, 0.11), 0.5, 0.4)
	box(root, Vector3(0.7, 0.75, 0.6), Vector3(0, 0.375, 0), m(Color(0.32, 0.33, 0.35), 0.3, 0.6))
	solid(root, Vector3(0.7, 0.75, 0.6), Vector3(0, 0.375, 0))
	for sx in [-0.22, 0.22]:
		for sz in [-0.2, 0.2]:
			box(root, Vector3(0.025, 0.5, 0.025), Vector3(sx, 1.0, sz), frame)
	box(root, Vector3(0.46, 0.025, 0.42), Vector3(0, 1.25, 0), frame)
	box(root, Vector3(0.4, 0.01, 0.36), Vector3(0, 0.78, 0), m(Color(0.15, 0.15, 0.17), 0.6, 0.3))
	var head := Node3D.new()
	head.position = Vector3(0, 1.0, 0)
	root.add_child(head)
	box(head, Vector3(0.44, 0.02, 0.02), Vector3.ZERO, frame)
	var nozzle := MeshFactory.box(head, Vector3(0.06, 0.06, 0.05), Vector3(0, -0.03, 0), m(Color(0.9, 0.4, 0.05), 0.2, 0.5))
	nozzle.name = "Nozzle"
	var part := MeshFactory.cyl(root, 0.06, 0.04, Vector3(0, 0.805, 0), m(Color(1.0, 0.45, 0.05), 0.0, 0.6), Vector3.ZERO, 12)
	part.name = "PrintPart"
	part.visible = false
	cyl(root, 0.1, 0.06, Vector3(0.3, 1.32, 0), m(Color(0.95, 0.5, 0.1), 0.0, 0.5), Vector3(0, 0, 90), 16)   # spool
	return {"root": root, "head": head, "part": part}


static func deploy_case(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var shell := m(Color(0.22, 0.26, 0.17), 0.1, 0.65)
	box(root, Vector3(0.75, 0.2, 0.5), Vector3(0, 0.1, 0), shell)
	box(root, Vector3(0.71, 0.02, 0.46), Vector3(0, 0.19, 0), m(Color(0.05, 0.05, 0.05), 0.0, 1.0))  # foam
	solid(root, Vector3(0.75, 0.22, 0.5), Vector3(0, 0.11, 0))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.2, -0.25)
	root.add_child(lid)
	box(lid, Vector3(0.75, 0.08, 0.5), Vector3(0, 0.04, 0.25), shell)
	for sx in [-0.25, 0.25]:
		box(root, Vector3(0.06, 0.05, 0.03), Vector3(sx, 0.17, 0.26), m(Color(0.7, 0.7, 0.7), 0.8, 0.3))
	box(root, Vector3(0.2, 0.03, 0.04), Vector3(0, 0.12, 0.27), m(Color(0.05, 0.05, 0.05), 0.2, 0.5))
	var _l := label(lid, "DEPLOYMENT CASE", 30, Vector3(0, 0.081, 0.25), Color(0.9, 0.85, 0.6))
	_l.rotation_degrees.x = -90
	return {"root": root, "lid": lid}


static func assembly_station(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var yel := m(Color(0.95, 0.68, 0.08), 0.3, 0.5)
	var dark := m(Color(0.15, 0.15, 0.16), 0.5, 0.4)
	box(root, Vector3(1.8, 0.85, 0.8), Vector3(0, 0.425, 0), dark)
	solid(root, Vector3(1.8, 0.85, 0.8), Vector3(0, 0.425, 0))
	box(root, Vector3(1.7, 0.03, 0.4), Vector3(0, 0.87, 0), m(Color(0.05, 0.05, 0.05), 0.1, 0.9))  # belt
	var arms: Array = []
	for sx in [-0.5, 0.5]:
		var base := Node3D.new()
		base.position = Vector3(sx, 0.87, -0.3)
		root.add_child(base)
		cyl(base, 0.08, 0.1, Vector3(0, 0.05, 0), yel)
		var a1 := Node3D.new()
		a1.position = Vector3(0, 0.1, 0)
		base.add_child(a1)
		box(a1, Vector3(0.06, 0.45, 0.06), Vector3(0, 0.22, 0), yel)
		var a2 := Node3D.new()
		a2.position = Vector3(0, 0.45, 0)
		a2.rotation_degrees.x = 70
		a1.add_child(a2)
		box(a2, Vector3(0.05, 0.4, 0.05), Vector3(0, 0.2, 0), yel)
		arms.append(a1)
	label(root, "AUTO-ASSEMBLY", 40, Vector3(0, 0.6, 0.41), Color(1, 0.8, 0.3))
	return {"root": root, "arms": arms}


## Ceiling fluorescent fitting with its light.
static func tube_light(parent: Node3D, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	box(root, Vector3(1.3, 0.05, 0.18), Vector3.ZERO, m(Color(0.85, 0.85, 0.85), 0.3, 0.5))
	var tube_m := m(Color(1.0, 0.97, 0.9), 0.0, 0.3, 3.0)
	var tubes: Array = []
	for sz in [-0.04, 0.04]:
		var t := cyl(root, 0.015, 1.2, Vector3(0, -0.04, sz), tube_m, Vector3(0, 0, 90), 8)
		t.set_meta("no_glow", true)
		tubes.append(t)
	var light := OmniLight3D.new()
	light.position = Vector3(0, -0.15, 0)
	light.light_color = Color(1.0, 0.92, 0.8)
	light.light_energy = 1.5
	light.omni_range = 6.5
	light.omni_attenuation = 1.2
	root.add_child(light)
	return {"root": root, "light": light, "tube_mat": tube_m}


## Delivery van, ~5 x 2 x 2.3 m, facing -Z. Origin on the ground.
static func van() -> Node3D:
	var root := Node3D.new()
	var white := m(Color(0.86, 0.87, 0.85), 0.3, 0.45)
	var dark := m(Color(0.08, 0.08, 0.09), 0.2, 0.6)
	var glass := m(Color(0.12, 0.18, 0.22), 0.6, 0.15)
	box(root, Vector3(1.95, 1.7, 3.6), Vector3(0, 1.35, 0.6), white)
	box(root, Vector3(1.95, 1.1, 1.4), Vector3(0, 1.05, -1.85), white)
	box(root, Vector3(1.9, 0.6, 0.05), Vector3(0, 1.5, -2.5), glass, Vector3(-25, 0, 0))
	for sx in [-0.98, 0.98]:
		box(root, Vector3(0.02, 0.5, 0.9), Vector3(sx, 1.55, -1.75), glass)
	box(root, Vector3(1.96, 0.25, 4.9), Vector3(0, 0.5, -0.05), dark)
	box(root, Vector3(1.97, 0.35, 0.1), Vector3(0, 0.55, -2.55), dark)
	for sx in [-0.75, 0.75]:
		box(root, Vector3(0.25, 0.1, 0.04), Vector3(sx, 0.85, -2.56), m(Color(1, 1, 0.85), 0.0, 0.3, 2.0))
		box(root, Vector3(0.2, 0.12, 0.04), Vector3(sx, 0.95, 2.42), m(Color(0.9, 0.1, 0.05), 0.0, 0.3, 1.0))
	box(root, Vector3(1.97, 0.35, 0.02), Vector3(0, 1.6, 0.6), m(Color(0.95, 0.55, 0.1), 0.1, 0.5))
	for sx in [-1, 1]:
		var vl := label(root, "SWIFTPARCEL", 120, Vector3(sx * 0.99, 1.62, 0.6), Color(0.1, 0.12, 0.2), sx * PI * 0.5)
		vl.outline_size = 0
	var wheels: Array = []
	for sx in [-0.88, 0.88]:
		for sz in [-1.6, 1.5]:
			var w := cyl(root, 0.36, 0.25, Vector3(sx, 0.36, sz), dark, Vector3(0, 0, 90), 14)
			wheels.append(w)
	root.set_meta("wheels", wheels)
	var rear := Node3D.new()
	rear.name = "RearDoor"
	rear.position = Vector3(0.95, 0.55, 2.42)
	root.add_child(rear)
	box(rear, Vector3(0.95, 1.6, 0.04), Vector3(-0.475, 0.8, 0), white)
	return root


## Sectional garage door: four panels; origin bottom-centre. width x height.
static func garage_door(width: float, height: float) -> Node3D:
	var root := Node3D.new()
	var panel_m := m(Color(0.78, 0.79, 0.8), 0.45, 0.5)
	var groove := m(Color(0.55, 0.56, 0.57), 0.4, 0.6)
	var ph := height / 4.0
	for i in 4:
		var p := MeshFactory.box(root, Vector3(width, ph - 0.01, 0.05), Vector3(0, ph * (i + 0.5), 0), panel_m)
		for k in 4:
			box(p, Vector3(width / 4.0 - 0.08, ph * 0.6, 0.008), Vector3(-width * 0.375 + k * width / 4.0, 0, 0.028), groove)
	box(root, Vector3(0.3, 0.04, 0.04), Vector3(0, 0.25, 0.05), m(Color(0.2, 0.2, 0.2), 0.7, 0.3))
	return root


static func test_gate(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var o := m(Color(1.0, 0.45, 0.08), 0.0, 0.5, 0.4)
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.12, 1.9, 0.12), Vector3(sx, 0.95, 0), o)
	box(root, Vector3(2.12, 0.12, 0.12), Vector3(0, 1.9, 0), o)
	solid(root, Vector3(0.14, 1.9, 0.14), Vector3(-1, 0.95, 0))
	solid(root, Vector3(0.14, 1.9, 0.14), Vector3(1, 0.95, 0))
