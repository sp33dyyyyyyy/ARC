class_name FlyWorld
extends Node3D
## The outdoor flying field: rolling hills, a lake, trees, a low pink-orange sun
## and distance fog. Everything is generated from primitives / procedural noise.

const HALF := 600.0                    # world half-size (m)
const CHUNK := 150.0
const WATER_LEVEL := 0.0
const LAKE_C := Vector2(260, -180)
const LAKE_R := 150.0
const START_H := 14.0

var quality: Dictionary
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _nf := FastNoiseLite.new()
var _tree_grid: Dictionary = {}        # Vector2i cell -> Array of [x, z, base_y, scale]
var tree_count := 0
var exclusions: Array = []             # Vector2 points kept free of trees (gates etc.)
var sun: DirectionalLight3D
var env: Environment
var _step := 4.0
var _grid_n := 0
var _grid: PackedFloat32Array


func _init() -> void:
	_n1.seed = 1337
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n1.frequency = 0.0021
	_n1.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n1.fractal_octaves = 4
	_n2.seed = 99
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.frequency = 0.011
	_nf.seed = 7
	_nf.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nf.frequency = 0.006


# --- terrain functions -----------------------------------------------------------------------
func height(x: float, z: float) -> float:
	var h := 24.0 + _n1.get_noise_2d(x, z) * 46.0 + _n2.get_noise_2d(x, z) * 5.0
	var d := Vector2(x, z).distance_to(LAKE_C)
	var k := 1.0 - smoothstep(LAKE_R * 0.55, LAKE_R, d)
	h = lerpf(h, -10.0, k)
	var ds := Vector2(x, z).length()
	var ks := 1.0 - smoothstep(16.0, 75.0, ds)
	h = lerpf(h, START_H, ks)
	return h


func is_water(x: float, z: float) -> bool:
	return height(x, z) < WATER_LEVEL


func start_position() -> Vector3:
	return Vector3(0, START_H + 0.1, 0)


## Trees whose cell neighbourhood contains (x, z): array of [x, z, base_y, scale]
func trees_near(x: float, z: float) -> Array:
	var c := Vector2i(floori(x / 24.0), floori(z / 24.0))
	var out: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var l = _tree_grid.get(Vector2i(c.x + dx, c.y + dz))
			if l:
				out.append_array(l)
	return out


# --- building -------------------------------------------------------------------------------------
func build(q: Dictionary) -> void:
	quality = q
	_step = q["terrain_step"]
	_build_environment()
	_build_terrain()
	_build_water()
	_build_trees()
	_build_pad()


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.2, 0.18, 0.42)
	psm.sky_horizon_color = Color(1.0, 0.56, 0.42)
	psm.sky_curve = 0.18
	psm.ground_horizon_color = Color(0.95, 0.5, 0.4)
	psm.ground_bottom_color = Color(0.35, 0.22, 0.28)
	psm.ground_curve = 0.05
	psm.sun_angle_max = 40.0
	psm.sun_curve = 0.2
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(1.0, 0.64, 0.52)
	env.fog_density = 0.0016 if quality["view"] > 500.0 else 0.0026
	env.fog_sky_affect = 0.55
	env.fog_aerial_perspective = 0.25
	env.fog_sun_scatter = 0.35
	env.glow_enabled = quality["glow"]
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-9, -38, 0)
	sun.light_color = Color(1.0, 0.8, 0.66)
	sun.light_energy = 1.35
	sun.shadow_enabled = quality["shadows"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.5
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)


func _build_terrain() -> void:
	_grid_n = int(round(HALF * 2.0 / _step))
	var n1 := _grid_n + 1
	_grid.resize(n1 * n1)
	for iz in n1:
		var z := -HALF + iz * _step
		for ix in n1:
			_grid[iz * n1 + ix] = height(-HALF + ix * _step, z)
	var per_chunk := int(round(CHUNK / _step))
	var chunks := int(round(HALF * 2.0 / CHUNK))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic_specular = 0.2
	var detail := FastNoiseLite.new()
	detail.frequency = 0.05
	detail.seed = 5
	for cz in chunks:
		for cx in chunks:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			var vn := per_chunk + 1
			verts.resize(vn * vn)
			norms.resize(vn * vn)
			cols.resize(vn * vn)
			for lz in vn:
				for lx in vn:
					var gx := cx * per_chunk + lx
					var gz := cz * per_chunk + lz
					var h := _grid[gz * n1 + gx]
					var hl := _grid[gz * n1 + maxi(gx - 1, 0)]
					var hr := _grid[gz * n1 + mini(gx + 1, _grid_n)]
					var hu := _grid[maxi(gz - 1, 0) * n1 + gx]
					var hd := _grid[mini(gz + 1, _grid_n) * n1 + gx]
					var nrm := Vector3(hl - hr, 2.0 * _step, hu - hd).normalized()
					var wx := -HALF + gx * _step
					var wz := -HALF + gz * _step
					var i := lz * vn + lx
					verts[i] = Vector3(wx - (-HALF + cx * CHUNK) + 0.0, h, wz - (-HALF + cz * CHUNK) + 0.0)
					norms[i] = nrm
					cols[i] = _terrain_color(h, nrm, detail.get_noise_2d(wx, wz))
			for lz in per_chunk:
				for lx in per_chunk:
					var a := lz * vn + lx
					var b := a + 1
					var c := a + vn
					var d := c + 1
					idx.append_array([a, b, c, b, d, c])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = am
			mi.material_override = mat
			mi.position = Vector3(-HALF + cx * CHUNK, 0, -HALF + cz * CHUNK)
			mi.custom_aabb = AABB(Vector3(0, -30, 0), Vector3(CHUNK, 140, CHUNK))
			add_child(mi)


func _terrain_color(h: float, n: Vector3, noise: float) -> Color:
	var grass := Color(0.1, 0.34, 0.09).lerp(Color(0.26, 0.46, 0.12), noise * 0.5 + 0.5)
	var rock := Color(0.42, 0.37, 0.34)
	var sand := Color(0.78, 0.68, 0.5)
	var c := grass
	var steep := 1.0 - n.y
	c = c.lerp(rock, clampf((steep - 0.22) * 4.0, 0.0, 1.0))
	c = c.lerp(rock.lightened(0.15), clampf((h - 52.0) / 20.0, 0.0, 1.0))
	c = c.lerp(sand, clampf((3.0 - h) / 3.0, 0.0, 1.0))
	if h < -1.0:
		c = c.lerp(Color(0.22, 0.28, 0.3), clampf((-h - 1.0) / 6.0, 0.0, 1.0))
	return c


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.2, HALF * 2.2)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.28, 0.36, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.15
	m.metallic_specular = 0.9
	mi.material_override = m
	mi.position.y = WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var want: int = quality["trees"]
	var pts: Array = []
	var tries := 0
	while pts.size() < want and tries < want * 40:
		tries += 1
		var x := rng.randf_range(-HALF + 20.0, HALF - 20.0)
		var z := rng.randf_range(-HALF + 20.0, HALF - 20.0)
		if Vector2(x, z).length() < 55.0:
			continue
		var h := height(x, z)
		if h < 2.0 or h > 62.0:
			continue
		var slope := absf(height(x + 2.0, z) - h) + absf(height(x, z + 2.0) - h)
		if slope > 2.6:
			continue
		if _nf.get_noise_2d(x, z) < -0.12:
			continue
		var blocked := false
		for ex in exclusions:
			if Vector2(x, z).distance_to(ex) < 14.0:
				blocked = true
				break
		if blocked:
			continue
		var s := rng.randf_range(0.8, 1.45)
		pts.append([x, z, h, s])
	tree_count = pts.size()
	for p in pts:
		var key := Vector2i(floori(p[0] / 24.0), floori(p[1] / 24.0))
		if not _tree_grid.has(key):
			_tree_grid[key] = []
		_tree_grid[key].append(p)

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 2.6
	trunk.radial_segments = 5
	trunk.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.25, 0.16, 0.1)
	trunk_mat.roughness = 1.0
	# foliage: three stacked cones merged into one mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := [[2.3, 3.6, 2.0], [1.8, 3.2, 3.9], [1.2, 2.8, 5.6]]
	for t in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = t[0]
		cone.height = t[1]
		cone.radial_segments = 7
		cone.rings = 1
		st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, t[2] + t[1] * 0.5, 0)))
	var foliage := st.commit()
	var fol_mat := StandardMaterial3D.new()
	fol_mat.vertex_color_use_as_albedo = true
	fol_mat.albedo_color = Color.WHITE
	fol_mat.roughness = 0.9

	for kind in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = (kind == 1)
		mm.mesh = trunk if kind == 0 else foliage
		mm.instance_count = pts.size()
		for i in pts.size():
			var p: Array = pts[i]
			var s: float = p[3]
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			var origin := Vector3(p[0], p[2] - 0.2, p[1])
			if kind == 0:
				origin.y += 1.3 * s
			mm.set_instance_transform(i, Transform3D(b, origin))
			if kind == 1:
				var g := rng.randf_range(0.0, 1.0)
				mm.set_instance_color(i, Color(0.05, 0.25, 0.08).lerp(Color(0.14, 0.4, 0.1), g))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = trunk_mat if kind == 0 else fol_mat
		mmi.custom_aabb = AABB(Vector3(-HALF, -20, -HALF), Vector3(HALF * 2, 140, HALF * 2))
		add_child(mmi)


func _build_pad() -> void:
	var c := start_position() - Vector3(0, 0.1, 0)
	var pad := MeshFactory.cyl(self, 4.0, 0.12, c + Vector3(0, 0.06, 0), MeshFactory.mat(Color(0.22, 0.22, 0.25), 0.1, 0.8), Vector3.ZERO, 32)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.05
	tm.outer_radius = 3.4
	tm.rings = 40
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = MeshFactory.mat(Color(1, 0.62, 0.1), 0.0, 0.6, 0.5)
	ring.position = c + Vector3(0, 0.14, 0)
	ring.scale = Vector3(1, 0.2, 1)
	add_child(ring)
	for a in 4:
		var ang := TAU * a / 4.0 + PI * 0.25
		var pole := MeshFactory.cyl(self, 0.06, 1.8, c + Vector3(cos(ang) * 6.5, 0.9, sin(ang) * 6.5), MeshFactory.mat(Color(0.9, 0.9, 0.95)), Vector3.ZERO, 6)
		MeshFactory.box(self, Vector3(0.7, 0.4, 0.04), c + Vector3(cos(ang) * 6.5 + 0.35, 1.6, sin(ang) * 6.5), MeshFactory.mat(Color(1, 0.35, 0.1), 0.0, 0.6, 0.4))
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
