class_name Fx
extends RefCounted
## Cheap CPU particle effects (smoke, fire, sparks, dust, debris) and the stylised,
## non-graphic impact flash used for abstract hits. Works on the Compatibility renderer.

static var _mats: Dictionary = {}


static func _puff_mat(key: String, color: Color, additive: bool) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _soft_tex()
	_mats[key] = m
	return m


static func _soft_tex() -> ImageTexture:
	if _mats.has("_tex"):
		return _mats["_tex"]
	var d := 32
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5 - d * 0.5, y + 0.5 - d * 0.5).length() / (d * 0.5)
			var a := clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var t := ImageTexture.create_from_image(img)
	_mats["_tex"] = t
	return t


static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / maxf(cols.size() - 1, 1))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	return g


static func _emitter(amount: int, life: float, mesh_size: float, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2(mesh_size, mesh_size)
	q.material = mat
	p.mesh = q
	p.local_coords = false
	return p


## Continuous smoke column (damaged vehicle / wreck).
static func smoke(parent: Node3D, offset: Vector3, size: float = 1.0, dark: float = 0.5) -> CPUParticles3D:
	var p := _emitter(int(18 * size) + 6, 3.6, 1.6 * size, _puff_mat("smoke", Color.WHITE, false))
	p.position = offset
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = 1.2 * size
	p.initial_velocity_max = 2.4 * size
	p.gravity = Vector3(0.6, 0.9, 0.2)
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(1, 2.4))
	p.scale_amount_curve = c
	var g := Color(0.16, 0.16, 0.17).lerp(Color(0.45, 0.45, 0.46), 1.0 - dark)
	p.color_ramp = _ramp([Color(g, 0.0), Color(g, 0.55), Color(g.lightened(0.2), 0.0)])
	parent.add_child(p)
	return p


static func fire(parent: Node3D, offset: Vector3, size: float = 1.0) -> CPUParticles3D:
	var p := _emitter(int(22 * size) + 6, 0.7, 0.9 * size, _puff_mat("fire", Color.WHITE, true))
	p.position = offset
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 1.0 * size
	p.initial_velocity_max = 2.6 * size
	p.gravity = Vector3(0, 2.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * size
	p.color_ramp = _ramp([Color(1.0, 0.85, 0.4, 0.0), Color(1.0, 0.55, 0.12, 0.9), Color(0.8, 0.18, 0.05, 0.0)])
	parent.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 1.6 * size
	l.omni_range = 9.0 * size
	l.position = offset + Vector3(0, 0.8, 0)
	parent.add_child(l)
	return p


static func sparks(parent: Node3D, pos: Vector3, n: int = 24) -> void:
	var p := _emitter(n, 0.6, 0.12, _puff_mat("spark", Color.WHITE, true))
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -9.8, 0)
	p.color_ramp = _ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.6, 0.15, 1), Color(1, 0.3, 0.05, 0)])
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_autofree(p, 1.5)


static func dust(parent: Node3D, pos: Vector3, size: float = 1.0) -> void:
	var p := _emitter(int(16 * size) + 4, 1.8, 2.0 * size, _puff_mat("smoke", Color.WHITE, false))
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 5.0 * size
	p.gravity = Vector3(0, -1.0, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.color_ramp = _ramp([Color(0.55, 0.48, 0.38, 0.7), Color(0.6, 0.55, 0.45, 0.0)])
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_autofree(p, 2.5)


## The stylised hit effect: bright flash, expanding shock ring, sparks, dust and debris chunks.
static func blast(parent: Node3D, pos: Vector3, size: float = 1.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 8.0 * size
	l.omni_range = 26.0 * size
	parent.add_child(l)
	l.global_position = pos + Vector3(0, 1.0, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1.0, 0.7, 0.3, 0.9)
	ball.material_override = bm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.4 * size
	var t2 := ball.create_tween().set_parallel(true)
	t2.tween_property(ball, "scale", Vector3.ONE * 4.5 * size, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t2.tween_property(bm, "albedo_color:a", 0.0, 0.45)
	t2.chain().tween_callback(ball.queue_free)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := bm.duplicate()
	rm.albedo_color = Color(1.0, 0.9, 0.7, 0.6)
	ring.material_override = rm
	parent.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.3, 0)
	var t3 := ring.create_tween().set_parallel(true)
	t3.tween_property(ring, "scale", Vector3(9, 1, 9) * size, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t3.tween_property(rm, "albedo_color:a", 0.0, 0.6)
	t3.chain().tween_callback(ring.queue_free)
	sparks(parent, pos, int(30 * size))
	dust(parent, pos, 1.4 * size)
	var sm2 := smoke(parent, Vector3.ZERO, 1.2 * size, 0.7)
	sm2.global_position = pos
	sm2.one_shot = true
	sm2.explosiveness = 0.6
	sm2.emitting = true
	_autofree(sm2, 5.0)
	# debris chunks
	var dm := MeshFactory.mat(Color(0.12, 0.12, 0.12), 0.3, 0.8)
	for k in int(8 * size):
		var c := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(randf_range(0.1, 0.4), randf_range(0.05, 0.2), randf_range(0.1, 0.4)) * size
		c.mesh = b
		c.material_override = dm
		parent.add_child(c)
		c.global_position = pos + Vector3(0, 0.5, 0)
		var v := Vector3(randf_range(-1, 1), randf_range(0.8, 2.0), randf_range(-1, 1)).normalized() * randf_range(6.0, 14.0) * sqrt(size)
		var dur := randf_range(0.8, 1.5)
		var end := pos + Vector3(v.x, 0, v.z) * dur * 0.7
		var t4 := c.create_tween().set_parallel(true)
		t4.tween_method(func(k2: float):
			if is_instance_valid(c):
				var p0 := pos + Vector3(0, 0.5, 0)
				c.global_position = p0.lerp(end, k2) + Vector3(0, v.y * dur * k2 - 4.9 * pow(dur * k2, 2.0), 0)
				c.rotation += Vector3(0.2, 0.3, 0.1), 0.0, 1.0, dur)
		t4.chain().tween_interval(2.0)
		t4.chain().tween_callback(c.queue_free)


static func _autofree(n: Node, t: float) -> void:
	# a child timer dies with its node, so nothing can fire after a scene change
	var tm := Timer.new()
	tm.wait_time = t
	tm.one_shot = true
	tm.autostart = true
	n.add_child(tm)
	tm.timeout.connect(n.queue_free)


## Darkens every mesh under `root` (wreck look).
static func char_meshes(root: Node) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.065, 0.06)
	m.roughness = 1.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m
