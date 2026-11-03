class_name VehicleKit
extends RefCounted
## Low-poly models for the fictional Dravic Ironguard equipment and static objectives.
## All models face -Z with the origin on the ground. Units: metres.
## Returned roots carry metadata: "wheels" (Array of nodes to spin), "turret", "rotor", "tail_rotor", "dish".

static func _m(c: Color, metal: float = 0.2, rough: float = 0.75, emit: float = 0.0) -> StandardMaterial3D:
	return MeshFactory.mat(c, metal, rough, emit)


const OLIVE := Color(0.27, 0.31, 0.2)
const OLIVE_D := Color(0.2, 0.23, 0.15)
const GREY := Color(0.36, 0.38, 0.37)
const DARK := Color(0.08, 0.08, 0.085)


static func _b(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return MeshFactory.box(p, size, pos, mat, rot)


static func _c(p: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, seg: int = 12) -> MeshInstance3D:
	return MeshFactory.cyl(p, r, h, pos, mat, rot, seg)


## Ironguard insignia: a white chevron on a dark square.
static func _emblem(p: Node3D, pos: Vector3, rot_y: float, s: float = 0.6) -> void:
	var e := Node3D.new()
	e.position = pos
	e.rotation.y = rot_y
	p.add_child(e)
	_b(e, Vector3(s, s, 0.02), Vector3.ZERO, _m(Color(0.12, 0.12, 0.12)))
	var w := _m(Color(0.9, 0.9, 0.88), 0.0, 0.6)
	_b(e, Vector3(s * 0.55, s * 0.12, 0.03), Vector3(-s * 0.14, 0, 0), w, Vector3(0, 0, 35))
	_b(e, Vector3(s * 0.55, s * 0.12, 0.03), Vector3(s * 0.14, 0, 0), w, Vector3(0, 0, -35))


static func _lights(root: Node3D, xs: float, y: float, z: float) -> void:
	var lamp := _m(Color(1.0, 0.95, 0.8), 0.0, 0.3, 1.2)
	for sx in [-xs, xs]:
		_c(root, 0.13, 0.06, Vector3(sx, y, z), lamp, Vector3(90, 0, 0), 10)


static func _fenders(root: Node3D, xs: float, zs: Array, r: float, mat: Material) -> void:
	for sx in [-xs, xs]:
		for z in zs:
			_b(root, Vector3(0.5, 0.06, r * 2.3), Vector3(sx, r * 2.05, z), mat)
			_b(root, Vector3(0.5, r * 0.6, 0.06), Vector3(sx, r * 1.75, z - r * 1.15), mat, Vector3(-30, 0, 0))


static func _wheels(root: Node3D, xs: float, zs: Array, r: float, w: float) -> Array:
	var out: Array = []
	var tyre := _m(DARK, 0.1, 0.9)
	var hub := _m(GREY, 0.5, 0.5)
	for sx in [-xs, xs]:
		for z in zs:
			var wh := Node3D.new()
			wh.position = Vector3(sx, r, z)
			root.add_child(wh)
			_c(wh, r, w, Vector3.ZERO, tyre, Vector3(0, 0, 90), 12)
			_c(wh, r * 0.5, w + 0.02, Vector3.ZERO, hub, Vector3(0, 0, 90), 8)
			out.append(wh)
	return out


static func make(kind: String) -> Node3D:
	match kind:
		"truck": return truck(false)
		"radar_truck": return truck(true)
		"apc": return apc()
		"heavy_apc": return tracked(false)
		"tank": return tracked(true)
		"heli_scout": return heli(false)
		"heli_transport": return heli(true)
		"uav": return uav()
		"radar_site": return radar_site()
		"jammer": return jammer()
		"tower": return tower()
		"board": return board()
		"container": return container()
		"comms": return comms()
	return Node3D.new()


static func truck(radar: bool) -> Node3D:
	var root := Node3D.new()
	var body := _m(OLIVE, 0.2, 0.7)
	var glass := _m(Color(0.1, 0.14, 0.16), 0.6, 0.15)
	_b(root, Vector3(2.3, 0.35, 6.2), Vector3(0, 0.95, 0.2), _m(DARK, 0.3, 0.7))
	_b(root, Vector3(2.3, 1.5, 1.8), Vector3(0, 1.85, -2.3), body)
	_b(root, Vector3(2.2, 0.55, 0.05), Vector3(0, 2.25, -3.21), glass)
	_b(root, Vector3(2.32, 0.4, 0.4), Vector3(0, 1.1, -3.25), _m(DARK))
	if radar:
		_b(root, Vector3(2.4, 1.6, 3.4), Vector3(0, 2.0, 1.2), _m(GREY, 0.3, 0.6))
		var dish := Node3D.new()
		dish.position = Vector3(0, 3.2, 1.2)
		root.add_child(dish)
		_c(dish, 0.12, 0.8, Vector3(0, 0.4, 0), _m(GREY, 0.6, 0.4))
		_b(dish, Vector3(2.6, 1.1, 0.12), Vector3(0, 1.1, 0), _m(Color(0.75, 0.76, 0.74), 0.4, 0.5), Vector3(-15, 0, 0))
		root.set_meta("dish", dish)
	else:
		# canvas-covered cargo bed
		_b(root, Vector3(2.4, 0.5, 3.8), Vector3(0, 1.35, 1.3), body)
		var canvas := _m(Color(0.33, 0.35, 0.24), 0.0, 0.95)
		_b(root, Vector3(2.35, 1.3, 3.7), Vector3(0, 2.25, 1.3), canvas)
		_c(root, 1.17, 3.7, Vector3(0, 2.9, 1.3), canvas, Vector3(90, 0, 0), 10)
	_emblem(root, Vector3(1.17, 1.9, -2.3), PI * 0.5)
	_emblem(root, Vector3(-1.17, 1.9, -2.3), -PI * 0.5)
	# cab details: side windows, mirrors, grille, lights, bumper, exhaust stack, roof hatch
	for sx in [-1.16, 1.16]:
		_b(root, Vector3(0.02, 0.45, 0.8), Vector3(sx, 2.25, -2.5), glass)
		_b(root, Vector3(0.06, 0.35, 0.2), Vector3(sx * 1.13, 2.2, -3.0), _m(DARK))
		_b(root, Vector3(0.2, 0.04, 0.04), Vector3(sx * 1.05, 2.2, -3.0), _m(DARK))
	for k in 5:
		_b(root, Vector3(1.4, 0.04, 0.04), Vector3(0, 1.45 + k * 0.1, -3.22), _m(DARK))
	_lights(root, 0.85, 1.4, -3.23)
	_b(root, Vector3(2.45, 0.22, 0.25), Vector3(0, 0.85, -3.35), _m(DARK, 0.5, 0.5))
	_c(root, 0.08, 1.6, Vector3(1.2, 2.5, -1.45), _m(Color(0.2, 0.2, 0.2), 0.6, 0.5))
	_b(root, Vector3(0.8, 0.08, 0.6), Vector3(0, 2.63, -2.3), _m(OLIVE_D))
	_fenders(root, 1.05, [-2.4, 0.6, 2.2], 0.55, _m(OLIVE_D))
	root.set_meta("wheels", _wheels(root, 1.05, [-2.4, 0.6, 2.2], 0.55, 0.4))
	return root


static func apc() -> Node3D:
	var root := Node3D.new()
	var hull := _m(OLIVE, 0.25, 0.65)
	_b(root, Vector3(2.7, 1.3, 6.6), Vector3(0, 1.45, 0), hull)
	_b(root, Vector3(2.6, 0.9, 1.6), Vector3(0, 1.55, -3.6), hull, Vector3(-38, 0, 0))   # sloped nose
	_b(root, Vector3(2.0, 0.3, 4.6), Vector3(0, 2.25, 0.4), _m(OLIVE_D, 0.2, 0.7))
	var tur := Node3D.new()
	tur.position = Vector3(0, 2.4, -0.4)
	root.add_child(tur)
	_c(tur, 0.6, 0.45, Vector3(0, 0.22, 0), hull, Vector3.ZERO, 10)
	_c(tur, 0.07, 1.6, Vector3(0, 0.3, -0.9), _m(DARK, 0.6, 0.4), Vector3(90, 0, 0), 6)
	root.set_meta("turret", tur)
	for sx in [-1, 1]:
		_b(root, Vector3(0.05, 0.4, 0.5), Vector3(1.36 * sx, 1.7, 1.6), _m(DARK))
	_emblem(root, Vector3(1.36, 1.5, 0.6), PI * 0.5, 0.7)
	_emblem(root, Vector3(-1.36, 1.5, 0.6), -PI * 0.5, 0.7)
	# hatches, periscopes, smoke launchers, lights, tow hooks, stowage
	for hz in [0.9, 2.0]:
		_c(root, 0.38, 0.08, Vector3(0.45, 2.42, hz), _m(OLIVE_D), Vector3.ZERO, 12)
		_c(root, 0.38, 0.08, Vector3(-0.45, 2.42, hz), _m(OLIVE_D), Vector3.ZERO, 12)
	for k in 3:
		_b(root, Vector3(0.18, 0.12, 0.1), Vector3(-0.5 + k * 0.5, 2.15, -2.85), _m(Color(0.1, 0.14, 0.16), 0.6, 0.2))
	for sx in [-1, 1]:
		for k in 3:
			_c(root, 0.06, 0.28, Vector3(0.45 * sx, 2.65 + k * 0.08, -0.6), _m(DARK), Vector3(-30, 0, 15 * sx), 6)
	_lights(root, 0.9, 1.55, -3.95)
	for sx in [-0.7, 0.7]:
		_b(root, Vector3(0.12, 0.12, 0.2), Vector3(sx, 0.95, -4.0), _m(DARK))
	_b(root, Vector3(1.5, 0.35, 0.7), Vector3(0, 2.25, 3.0), _m(Color(0.3, 0.3, 0.22), 0.0, 0.95))
	_fenders(root, 1.25, [-2.3, -0.8, 0.8, 2.3], 0.6, _m(OLIVE_D))
	root.set_meta("wheels", _wheels(root, 1.25, [-2.3, -0.8, 0.8, 2.3], 0.6, 0.45))
	return root


static func tracked(tank: bool) -> Node3D:
	var root := Node3D.new()
	var hull := _m(OLIVE if tank else Color(0.3, 0.32, 0.24), 0.3, 0.6)
	var track := _m(DARK, 0.3, 0.9)
	var len := 7.2 if tank else 6.8
	for sx in [-1.45, 1.45]:
		_b(root, Vector3(0.7, 0.95, len), Vector3(sx, 0.55, 0), track)
		for k in 6:
			_c(root, 0.36, 0.72, Vector3(sx, 0.42, -len * 0.4 + k * len * 0.16), _m(Color(0.15, 0.15, 0.14), 0.4, 0.6), Vector3(0, 0, 90), 10)
	_b(root, Vector3(2.4, 0.9, len - 0.4), Vector3(0, 1.25, 0), hull)
	_b(root, Vector3(3.5, 0.12, len - 0.2), Vector3(0, 1.1, 0), _m(OLIVE_D))
	_b(root, Vector3(2.4, 0.6, 1.2), Vector3(0, 1.2, -len * 0.5), hull, Vector3(-30, 0, 0))
	var tur := Node3D.new()
	tur.position = Vector3(0, 1.7, 0.3 if tank else -0.6)
	root.add_child(tur)
	if tank:
		_b(tur, Vector3(2.3, 0.75, 2.8), Vector3(0, 0.37, 0.2), hull)
		_b(tur, Vector3(1.8, 0.5, 0.8), Vector3(0, 0.3, -1.3), hull, Vector3(-20, 0, 0))
		_c(tur, 0.12, 4.6, Vector3(0, 0.42, -3.6), _m(OLIVE_D, 0.4, 0.5), Vector3(90, 0, 0), 10)
		_c(tur, 0.17, 0.6, Vector3(0, 0.42, -5.6), _m(OLIVE_D, 0.4, 0.5), Vector3(90, 0, 0), 10)
		_c(tur, 0.35, 0.3, Vector3(0.6, 0.85, 0.6), hull, Vector3.ZERO, 8)
	else:
		_c(tur, 0.55, 0.5, Vector3(0, 0.25, 0), hull, Vector3.ZERO, 10)
		_c(tur, 0.06, 1.4, Vector3(0, 0.35, -0.8), _m(DARK, 0.6, 0.4), Vector3(90, 0, 0), 6)
		_b(root, Vector3(2.3, 0.7, 2.8), Vector3(0, 1.95, 1.6), hull)
	root.set_meta("turret", tur)
	_emblem(root, Vector3(1.21, 1.35, 1.0), PI * 0.5, 0.7)
	_emblem(root, Vector3(-1.21, 1.35, 1.0), -PI * 0.5, 0.7)
	# track links, sprockets / idlers, side skirts, engine deck, hatch, antennas
	var link := _m(Color(0.16, 0.16, 0.15), 0.5, 0.7)
	for sx in [-1.45, 1.45]:
		for k in 18:
			var z := -len * 0.48 + k * len * 0.056
			_b(root, Vector3(0.72, 0.06, 0.18), Vector3(sx, 1.04, z), link)
			_b(root, Vector3(0.72, 0.06, 0.18), Vector3(sx, 0.06, z), link)
		for z in [-len * 0.5 + 0.2, len * 0.5 - 0.2]:
			var sp := _c(root, 0.45, 0.74, Vector3(sx, 0.6, z), _m(Color(0.2, 0.2, 0.19), 0.6, 0.5), Vector3(0, 0, 90), 8)
			sp.name = "Sprocket"
		_b(root, Vector3(0.06, 0.55, len - 0.6), Vector3(sx * 1.24, 0.92, 0), _m(OLIVE_D))
	for k in 5:
		_b(root, Vector3(1.8, 0.05, 0.12), Vector3(0, 1.72, len * 0.3 + k * 0.2), _m(DARK))
	if tank:
		_c(tur, 0.42, 0.12, Vector3(-0.5, 0.82, 0.5), _m(OLIVE_D), Vector3.ZERO, 12)
		_b(tur, Vector3(0.9, 0.45, 0.4), Vector3(0, 0.38, -1.55), hull)
		_c(tur, 0.02, 2.2, Vector3(-0.85, 1.85, 1.2), _m(DARK), Vector3(-8, 0, 0), 4)
		_b(tur, Vector3(1.6, 0.4, 0.5), Vector3(0, 0.45, 1.6), _m(Color(0.3, 0.3, 0.22), 0.0, 0.95))
		for sx in [-1, 1]:
			for k in 4:
				_c(tur, 0.07, 0.3, Vector3(1.15 * sx, 0.6, -0.4 + k * 0.17), _m(DARK), Vector3(-40, 0, -40 * sx), 6)
	else:
		_c(root, 0.02, 2.0, Vector3(0.9, 2.4, 2.4), _m(DARK), Vector3(-8, 0, 0), 4)
		for k in 2:
			_c(root, 0.35, 0.08, Vector3(-0.5 + k, 2.33, 2.0), _m(OLIVE_D), Vector3.ZERO, 12)
	root.set_meta("wheels", [])
	return root


static func heli(transport: bool) -> Node3D:
	var root := Node3D.new()
	var skin := _m(Color(0.3, 0.33, 0.27) if transport else Color(0.33, 0.35, 0.33), 0.3, 0.55)
	var glass := _m(Color(0.1, 0.14, 0.18), 0.7, 0.1)
	var body_len := 9.0 if transport else 5.0
	var r := 1.25 if transport else 0.85
	var body := MeshFactory.cyl(root, r, body_len, Vector3(0, r + 0.6, 0), skin, Vector3(90, 0, 0), 12)
	body.name = "Body"
	MeshFactory.sphere(root, r, Vector3(0, r + 0.6, -body_len * 0.5), glass)
	_b(root, Vector3(r * 1.8, r * 0.8, body_len * 0.5), Vector3(0, r * 1.6 + 0.6, 0), skin)
	var tail_len := body_len * 0.9
	_c(root, r * 0.28, tail_len, Vector3(0, r * 1.3 + 0.6, body_len * 0.5 + tail_len * 0.5 - 0.4), skin, Vector3(90, 0, 0), 8)
	_b(root, Vector3(0.12, r * 1.6, r * 1.2), Vector3(0, r * 2.0 + 0.6, body_len * 0.5 + tail_len - 0.6), skin)
	_b(root, Vector3(r * 2.0, 0.1, 0.6), Vector3(0, r * 1.3 + 0.6, body_len * 0.5 + tail_len - 1.4), skin)
	# skids
	var steel := _m(Color(0.2, 0.2, 0.2), 0.6, 0.4)
	for sx in [-1, 1]:
		_c(root, 0.06, body_len * 0.75, Vector3(r * 0.9 * sx, 0.06, 0), steel, Vector3(90, 0, 0), 6)
		for sz in [-0.25, 0.25]:
			_b(root, Vector3(0.06, 0.8, 0.06), Vector3(r * 0.75 * sx, 0.4, body_len * sz), steel, Vector3(0, 0, -20 * sx))
	if transport:
		for sx in [-1, 1]:
			_b(root, Vector3(0.05, 0.5, 0.8), Vector3(r * sx * 1.0, r + 0.9, -1.0), glass)
	# main rotor
	var mast := Node3D.new()
	mast.position = Vector3(0, r * 2.0 + 0.95, -0.2)
	root.add_child(mast)
	_c(mast, 0.15, 0.4, Vector3.ZERO, steel)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 0.25, 0)
	mast.add_child(rotor)
	var blade_len := 7.5 if transport else 4.6
	var blade := _m(Color(0.12, 0.12, 0.12), 0.3, 0.6)
	var nb := 5 if transport else 4
	for k in nb:
		var h := Node3D.new()
		h.rotation.y = TAU * k / nb
		rotor.add_child(h)
		_b(h, Vector3(0.3, 0.05, blade_len), Vector3(0, 0, blade_len * 0.5), blade)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = blade_len
	cm.bottom_radius = blade_len
	cm.height = 0.02
	cm.radial_segments = 24
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.1, 0.1, 0.1, 0.18)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dm
	disc.name = "Blur"
	rotor.add_child(disc)
	root.set_meta("rotor", rotor)
	var tr := Node3D.new()
	tr.position = Vector3(0.18, r * 2.0 + 0.6, body_len * 0.5 + tail_len - 0.6)
	root.add_child(tr)
	for k in 3:
		var h := Node3D.new()
		h.rotation.x = TAU * k / 3.0
		tr.add_child(h)
		_b(h, Vector3(0.05, 0.9, 0.12), Vector3(0, 0.45, 0), blade)
	root.set_meta("tail_rotor", tr)
	_emblem(root, Vector3(r * 1.0, r + 0.7, 1.0), PI * 0.5, 0.8)
	_emblem(root, Vector3(-r * 1.0, r + 0.7, 1.0), -PI * 0.5, 0.8)
	# engine housings, intakes and exhausts on the roof
	for sx in [-0.35, 0.35]:
		_c(root, r * 0.32, body_len * 0.35, Vector3(sx * r, r * 2.05 + 0.6, 0.2), skin, Vector3(90, 0, 0), 10)
		_c(root, r * 0.22, 0.1, Vector3(sx * r, r * 2.05 + 0.6, 0.2 - body_len * 0.18), _m(DARK), Vector3(90, 0, 0), 10)
		_c(root, r * 0.2, 0.4, Vector3(sx * r * 1.6, r * 2.0 + 0.6, 0.2 + body_len * 0.2), _m(Color(0.12, 0.11, 0.1), 0.6, 0.5), Vector3(70, 0, 30 * signf(sx)), 8)
	# canopy frame bars
	for k in 3:
		var a := -0.6 + k * 0.6
		_b(root, Vector3(0.05, r * 1.1, 0.05), Vector3(sin(a) * r * 0.95, r + 0.75, -body_len * 0.5 - cos(a) * r * 0.55), _m(DARK), Vector3(-35, 0, rad_to_deg(a) * 0.5))
	# stub wings with fictional equipment pods (scout) / sponsons (transport)
	for sx in [-1, 1]:
		_b(root, Vector3(r * 1.6, 0.08, 0.8), Vector3(sx * r * 1.6, r + 0.4, 0.4), skin, Vector3(0, 0, -6 * sx))
		_c(root, 0.16 if not transport else 0.35, 1.1 if not transport else 2.2, Vector3(sx * r * 2.1, r + 0.22, 0.4), _m(Color(0.25, 0.27, 0.24), 0.3, 0.6), Vector3(90, 0, 0), 10)
	_b(root, Vector3(0.1, r * 0.9, r * 1.0), Vector3(0, r * 1.5 + 0.6, body_len * 0.5 + tail_len - 0.2), skin, Vector3(-20, 0, 0))
	var nav := _m(Color(1, 0.2, 0.15), 0.0, 0.4, 3.0)
	MeshFactory.sphere(root, 0.08, Vector3(0, r * 2.0 + 0.7, body_len * 0.5 + tail_len), nav)
	return root


static func uav() -> Node3D:
	var root := Node3D.new()
	var skin := _m(Color(0.55, 0.57, 0.56), 0.3, 0.5)
	_c(root, 0.25, 3.0, Vector3(0, 0, 0), skin, Vector3(90, 0, 0), 10)
	_b(root, Vector3(5.0, 0.08, 0.7), Vector3(0, 0.05, -0.1), skin)
	_b(root, Vector3(1.6, 0.06, 0.4), Vector3(0, 0.05, 1.4), skin)
	_b(root, Vector3(0.06, 0.6, 0.4), Vector3(0, 0.3, 1.4), skin)
	var prop := Node3D.new()
	prop.position = Vector3(0, 0, 1.55)
	root.add_child(prop)
	_b(prop, Vector3(0.9, 0.08, 0.04), Vector3.ZERO, _m(DARK))
	root.set_meta("rotor", prop)
	return root


static func radar_site() -> Node3D:
	var root := Node3D.new()
	var conc := _m(Color(0.5, 0.5, 0.48), 0.0, 0.9)
	_b(root, Vector3(4.0, 0.6, 4.0), Vector3(0, 0.3, 0), conc)
	_b(root, Vector3(2.2, 1.8, 2.2), Vector3(0, 1.5, 0), _m(GREY, 0.3, 0.6))
	var dish := Node3D.new()
	dish.position = Vector3(0, 2.6, 0)
	root.add_child(dish)
	_c(dish, 0.2, 0.8, Vector3(0, 0.4, 0), _m(GREY, 0.6, 0.4))
	var panel := _b(dish, Vector3(4.2, 1.6, 0.18), Vector3(0, 1.3, 0), _m(Color(0.78, 0.79, 0.76), 0.4, 0.5), Vector3(-18, 0, 0))
	panel.name = "Panel"
	_b(dish, Vector3(0.12, 0.12, 1.0), Vector3(0, 1.4, -0.6), _m(DARK))
	root.set_meta("dish", dish)
	_emblem(root, Vector3(0, 1.6, -1.11), 0.0, 0.8)
	return root


static func jammer() -> Node3D:
	var root := Node3D.new()
	var steel := _m(Color(0.42, 0.4, 0.36), 0.6, 0.5)
	_b(root, Vector3(1.6, 0.8, 1.6), Vector3(0, 0.4, 0), _m(OLIVE))
	for sx in [-0.4, 0.4]:
		for sz in [-0.4, 0.4]:
			_b(root, Vector3(0.08, 6.0, 0.08), Vector3(sx * (1.0 - 0.0), 3.6, sz), steel)
	for k in 6:
		_b(root, Vector3(0.85, 0.05, 0.05), Vector3(0, 1.2 + k, 0.4), steel, Vector3(0, 0, 35 if k % 2 == 0 else -35))
	var head := Node3D.new()
	head.position = Vector3(0, 6.6, 0)
	root.add_child(head)
	for k in 4:
		var a := k * PI * 0.5
		_b(head, Vector3(0.3, 1.0, 0.1), Vector3(cos(a) * 0.5, 0, sin(a) * 0.5), _m(Color(0.85, 0.85, 0.82)), Vector3(0, -rad_to_deg(a), 0))
	var lamp := MeshFactory.sphere(head, 0.15, Vector3(0, 0.7, 0), _m(Color(1, 0.2, 0.1), 0.0, 0.4, 3.0))
	lamp.name = "Lamp"
	root.set_meta("dish", head)
	return root


static func tower() -> Node3D:
	var root := Node3D.new()
	var wood := _m(Color(0.36, 0.27, 0.18), 0.0, 0.9)
	for sx in [-0.7, 0.7]:
		for sz in [-0.7, 0.7]:
			_b(root, Vector3(0.15, 3.6, 0.15), Vector3(sx, 1.8, sz), wood)
	_b(root, Vector3(2.0, 0.12, 2.0), Vector3(0, 3.6, 0), wood)
	for k in 4:
		var a := k * PI * 0.5
		_b(root, Vector3(2.0, 0.9, 0.08), Vector3(sin(a) * 0.96, 4.1, cos(a) * 0.96), wood, Vector3(0, rad_to_deg(a), 0))
	_b(root, Vector3(2.3, 0.1, 2.3), Vector3(0, 5.0, 0), _m(Color(0.25, 0.25, 0.22), 0.3, 0.7), Vector3(0, 0, 4))
	for k in 4:
		_b(root, Vector3(0.12, 0.5, 0.12), Vector3(-0.95 + (k % 2) * 1.9, 4.75, -0.95 + (k / 2) * 1.9), wood)
	return root


static func board() -> Node3D:
	var root := Node3D.new()
	var wood := _m(Color(0.5, 0.38, 0.24), 0.0, 0.9)
	for sx in [-1.2, 1.2]:
		_b(root, Vector3(0.15, 2.2, 0.15), Vector3(sx, 1.1, 0), wood)
	_b(root, Vector3(2.6, 1.8, 0.12), Vector3(0, 1.5, 0), _m(Color(0.88, 0.86, 0.8), 0.0, 0.8))
	var red := _m(Color(0.85, 0.12, 0.08), 0.0, 0.6)
	for k in 3:
		_c(root, 0.75 - k * 0.25, 0.14 + k * 0.01, Vector3(0, 1.5, -0.01), red if k % 2 == 0 else _m(Color(0.95, 0.95, 0.9)), Vector3(90, 0, 0), 20)
	_b(root, Vector3(3.0, 0.5, 1.2), Vector3(0, 0.25, 0.9), _m(Color(0.45, 0.38, 0.28), 0.0, 1.0))  # sandbag berm
	return root


static func container() -> Node3D:
	var root := Node3D.new()
	var cols := [Color(0.55, 0.2, 0.15), Color(0.2, 0.35, 0.5), Color(0.35, 0.4, 0.25), Color(0.6, 0.45, 0.15)]
	var c: Color = cols[randi() % cols.size()]
	var m := _m(c, 0.4, 0.6)
	_b(root, Vector3(2.4, 2.5, 6.0), Vector3(0, 1.25, 0), m)
	for k in 9:
		_b(root, Vector3(2.44, 2.3, 0.08), Vector3(0, 1.25, -2.6 + k * 0.65), _m(c.darkened(0.2), 0.4, 0.6))
	_b(root, Vector3(2.3, 2.3, 0.05), Vector3(0, 1.25, 3.01), _m(c.darkened(0.3), 0.4, 0.6))
	return root


static func comms() -> Node3D:
	var root := Node3D.new()
	_b(root, Vector3(1.8, 1.4, 1.4), Vector3(0, 0.7, 0), _m(OLIVE, 0.2, 0.7))
	_b(root, Vector3(1.2, 0.5, 0.05), Vector3(0, 0.9, -0.71), _m(Color(0.05, 0.25, 0.12), 0.0, 0.4, 0.8))
	_c(root, 0.04, 5.0, Vector3(0.6, 3.9, 0.3), _m(Color(0.3, 0.3, 0.3), 0.6, 0.4), Vector3.ZERO, 6)
	_c(root, 0.04, 3.0, Vector3(-0.6, 2.9, 0.3), _m(Color(0.3, 0.3, 0.3), 0.6, 0.4), Vector3.ZERO, 6)
	_c(root, 0.45, 0.08, Vector3(0, 1.45, 0.2), _m(Color(0.8, 0.8, 0.78), 0.3, 0.5), Vector3(-30, 0, 0), 14)
	_emblem(root, Vector3(0.91, 0.8, 0), PI * 0.5, 0.6)
	return root
