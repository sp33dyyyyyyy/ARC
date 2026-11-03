class_name FlyWorld
extends Node3D
## The outdoor flying worlds, all generated from primitives and procedural noise:
##   testing    - hills, a lake and the garage property (the original field)
##   rural      - farmland, a valley road, a farm, a village, a checkpoint and a training range
##   industrial - an abandoned works: warehouses, a factory hall, chimneys, a rail yard, a helipad
## Time of day, weather (clear / overcast / fog / rain) and wind come from `conditions`.

const HALF := 600.0                    # testing-map half-size (m), kept for callers
const CHUNK := 150.0
const WATER_LEVEL := 0.0
const LAKE_C := Vector2(260, -180)
const LAKE_R := 150.0
const START_H := 14.0

signal progress(fraction: float, label: String)

var map := "testing"
var conditions: Dictionary = {"time": "dusk", "weather": "clear", "wind": 1.0}
var half := 600.0
var quality: Dictionary
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _nf := FastNoiseLite.new()
var _nfield := FastNoiseLite.new()
var _tree_grid: Dictionary = {}        # Vector2i cell -> Array of [x, z, base_y, scale]
var _box_grid: Dictionary = {}         # Vector2i cell (40 m) -> Array of boxes [cx, cy, cz, hx, hy, hz, yaw]
var buildings: Array = []              # {pos, size, yaw, kind, color}
var tree_count := 0
var exclusions: Array = []             # Vector2 points kept free of trees (gates, targets etc.)
var sun: DirectionalLight3D
var env: Environment
var rain := false
var _step := 4.0
var _grid_n := 0
var _grid: PackedFloat32Array
var _launch := Vector2.ZERO
var _road: Array = []


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
	_nfield.seed = 31
	_nfield.noise_type = FastNoiseLite.TYPE_CELLULAR
	_nfield.frequency = 0.012
	_nfield.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE


## Must be called before build() / height() for a non-default map.
func set_map(p_map: String) -> void:
	map = p_map
	var info := map_info(map)
	half = info["half"]
	_launch = info["launch"]
	_road = info["road"]
	match map:
		"rural":
			_n1.frequency = 0.0016
		"industrial":
			_n1.frequency = 0.0025


## Static description of a map for briefings and mission setup.
static func map_info(p_map: String) -> Dictionary:
	match p_map:
		"rural":
			return {"half": 675.0, "launch": Vector2(-380, 300), "road": RURAL_ROAD,
				"anchors": {"range": Vector2(-210, 170), "checkpoint": Vector2(30, 40), "convoy": Vector2(60, -40), "farm": Vector2(-60, 230), "course": Vector2(-300, 250)}}
		"industrial":
			return {"half": 600.0, "launch": Vector2(-360, 320), "road": IND_ROAD,
				"anchors": {"radar": Vector2(130, -40), "radar_jam": Vector2(60, -110), "yard": Vector2(-40, 60), "helipad": Vector2(150, 130), "sky": Vector2(20, 20), "course": Vector2(-250, 250)}}
	return {"half": 600.0, "launch": Vector2(0, 0), "road": [], "anchors": {"course": Vector2(0, -80)}}


const RURAL_ROAD := [Vector2(-675, -250), Vector2(-420, -180), Vector2(-200, -60), Vector2(0, 20), Vector2(160, -10), Vector2(330, -120), Vector2(520, -160), Vector2(675, -230)]
const IND_ROAD := [Vector2(-600, 200), Vector2(-300, 200), Vector2(-100, 140), Vector2(100, 140), Vector2(300, 60), Vector2(600, 60)]


# --- terrain functions -----------------------------------------------------------------------
func height(x: float, z: float) -> float:
	match map:
		"rural":
			var h := 14.0 + _n1.get_noise_2d(x, z) * 26.0 + _n2.get_noise_2d(x, z) * 2.5
			var ks := 1.0 - smoothstep(20.0, 70.0, Vector2(x, z).distance_to(_launch))
			return maxf(lerpf(h, 14.0 + _n1.get_noise_2d(_launch.x, _launch.y) * 26.0, ks), 1.0)
		"industrial":
			var dc := Vector2(x, z).length()
			var hills := _n1.get_noise_2d(x, z) * 30.0 * smoothstep(330.0, 560.0, dc)
			return 6.0 + hills + _n2.get_noise_2d(x, z) * 0.25
	var h := 24.0 + _n1.get_noise_2d(x, z) * 46.0 + _n2.get_noise_2d(x, z) * 5.0
	var d := Vector2(x, z).distance_to(LAKE_C)
	var k := 1.0 - smoothstep(LAKE_R * 0.55, LAKE_R, d)
	h = lerpf(h, -10.0, k)
	var ds := Vector2(x, z).length()
	var ks := 1.0 - smoothstep(16.0, 75.0, ds)
	h = lerpf(h, START_H, ks)
	return h


func is_water(x: float, z: float) -> bool:
	return map == "testing" and height(x, z) < WATER_LEVEL


func start_position() -> Vector3:
	if map == "testing":
		return Vector3(0, START_H + 0.1, 0)
	return Vector3(_launch.x, height(_launch.x, _launch.y) + 0.1, _launch.y)


func anchor(name: String) -> Vector3:
	var a: Vector2 = map_info(map)["anchors"].get(name, _launch)
	return Vector3(a.x, top_at(a.x, a.y), a.y)


## Ground or roof height under (x, z).
func top_at(x: float, z: float) -> float:
	var h := height(x, z)
	for b in boxes_near(x, z):
		var l := Vector2(x - b[0], z - b[2]).rotated(-b[6])
		if absf(l.x) <= b[3] and absf(l.y) <= b[5]:
			h = maxf(h, b[1] + b[4])
	return h


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


## Building / obstacle boxes near (x, z): [cx, cy, cz, hx, hy, hz, yaw]
func boxes_near(x: float, z: float) -> Array:
	var c := Vector2i(floori(x / 40.0), floori(z / 40.0))
	var out: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var l = _box_grid.get(Vector2i(c.x + dx, c.y + dz))
			if l:
				out.append_array(l)
	return out


func _add_box(center: Vector3, half_ext: Vector3, yaw: float) -> void:
	var b := [center.x, center.y, center.z, half_ext.x, half_ext.y, half_ext.z, yaw]
	var r := Vector2(half_ext.x, half_ext.z).length()
	var c0 := Vector2i(floori((center.x - r) / 40.0), floori((center.z - r) / 40.0))
	var c1 := Vector2i(floori((center.x + r) / 40.0), floori((center.z + r) / 40.0))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var key := Vector2i(cx, cz)
			if not _box_grid.has(key):
				_box_grid[key] = []
			_box_grid[key].append(b)


## Distance from (x, z) to the map's road polyline.
func road_distance(x: float, z: float) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for i in range(1, _road.size()):
		var a: Vector2 = _road[i - 1]
		var b: Vector2 = _road[i]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Densely sampled road with terrain heights (for vehicles).
func road_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if _road.size() < 2:
		return out
	for i in range(1, _road.size()):
		var a: Vector2 = _road[i - 1]
		var b: Vector2 = _road[i]
		var n := int(ceil(a.distance_to(b) / 6.0))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			out.append(Vector3(p.x, height(p.x, p.y), p.y))
	var e: Vector2 = _road[_road.size() - 1]
	out.append(Vector3(e.x, height(e.x, e.y), e.y))
	return out


## Arc-length position on the road closest to (x, z).
func road_s_near(x: float, z: float) -> float:
	var pts := road_points()
	var best := 1e9
	var acc := 0.0
	var best_s := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		var d := Vector2(pts[i].x - x, pts[i].z - z).length()
		if d < best:
			best = d
			best_s = acc
	return best_s


# --- building -------------------------------------------------------------------------------------
## Builds the world over several frames (emits `progress`) so the window stays responsive.
func build(q: Dictionary) -> void:
	quality = q
	_step = q["terrain_step"]
	progress.emit(0.0, "Sky and light")
	_build_environment()
	await get_tree().process_frame
	_plan_buildings()
	await _build_terrain()
	if map == "testing":
		progress.emit(0.8, "Lake")
		_build_water()
	await get_tree().process_frame
	progress.emit(0.82, "Buildings")
	_build_buildings()
	await get_tree().process_frame
	progress.emit(0.85, "Trees")
	await _build_trees()
	progress.emit(0.98, "Launch pad")
	_build_pad()
	await get_tree().process_frame
	progress.emit(1.0, "Done")


func _build_environment() -> void:
	var t: String = conditions.get("time", "dusk")
	var w: String = conditions.get("weather", "clear")
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	var top := Color(0.2, 0.18, 0.42)
	var hor := Color(1.0, 0.56, 0.42)
	var sun_rot := Vector3(-9, -38, 0)
	var sun_col := Color(1.0, 0.8, 0.66)
	var sun_e := 1.35
	match t:
		"noon":
			top = Color(0.22, 0.42, 0.75)
			hor = Color(0.68, 0.78, 0.88)
			sun_rot = Vector3(-55, -30, 0)
			sun_col = Color(1.0, 0.97, 0.9)
			sun_e = 1.25
		"dawn":
			top = Color(0.28, 0.34, 0.6)
			hor = Color(1.0, 0.72, 0.62)
			sun_rot = Vector3(-7, 120, 0)
			sun_col = Color(1.0, 0.78, 0.7)
			sun_e = 1.15
	var fog := 0.0016 if quality["view"] > 500.0 else 0.0026
	match w:
		"overcast":
			top = top.lerp(Color(0.45, 0.47, 0.5), 0.75)
			hor = hor.lerp(Color(0.62, 0.63, 0.65), 0.75)
			sun_e *= 0.45
			fog *= 1.6
		"fog":
			top = top.lerp(Color(0.62, 0.64, 0.66), 0.8)
			hor = hor.lerp(Color(0.72, 0.73, 0.74), 0.85)
			sun_e *= 0.5
			fog = 0.0105
		"rain":
			top = top.lerp(Color(0.3, 0.32, 0.36), 0.85)
			hor = hor.lerp(Color(0.45, 0.47, 0.5), 0.85)
			sun_e *= 0.35
			fog = 0.0055
			rain = true
	psm.sky_top_color = top
	psm.sky_horizon_color = hor
	psm.sky_curve = 0.18
	psm.ground_horizon_color = hor.darkened(0.05)
	psm.ground_bottom_color = Color(0.35, 0.22, 0.28).lerp(Color(0.3, 0.3, 0.3), 0.5 if w != "clear" else 0.0)
	psm.ground_curve = 0.05
	psm.sun_angle_max = 40.0
	psm.sun_curve = 0.2
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75 if w == "clear" else 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = hor
	env.fog_density = fog
	env.fog_sky_affect = 0.55 if w == "clear" else 0.85
	env.fog_aerial_perspective = 0.25
	env.fog_sun_scatter = 0.35 if w == "clear" else 0.05
	env.glow_enabled = quality["glow"]
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = sun_rot
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.shadow_enabled = quality["shadows"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality["shadow_size"] >= 2048 else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = quality.get("shadow_dist", 140.0)
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.5
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)


func _build_terrain() -> void:
	_grid_n = int(round(half * 2.0 / _step))
	var n1 := _grid_n + 1
	_grid.resize(n1 * n1)
	for iz in n1:
		var z := -half + iz * _step
		for ix in n1:
			_grid[iz * n1 + ix] = height(-half + ix * _step, z)
		if iz % 30 == 29:
			progress.emit(0.05 + 0.25 * iz / n1, "Shaping terrain")
			await get_tree().process_frame
	var per_chunk := int(round(CHUNK / _step))
	var chunks := int(round(half * 2.0 / CHUNK))
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
					var wx := -half + gx * _step
					var wz := -half + gz * _step
					var i := lz * vn + lx
					verts[i] = Vector3(wx - (-half + cx * CHUNK), h, wz - (-half + cz * CHUNK))
					norms[i] = nrm
					cols[i] = _terrain_color(wx, wz, h, nrm, detail.get_noise_2d(wx, wz))
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
			mi.position = Vector3(-half + cx * CHUNK, 0, -half + cz * CHUNK)
			mi.custom_aabb = AABB(Vector3(0, -30, 0), Vector3(CHUNK, 140, CHUNK))
			add_child(mi)
		progress.emit(0.3 + 0.5 * float(cz + 1) / chunks, "Building terrain")
		await get_tree().process_frame


func _terrain_color(x: float, z: float, h: float, n: Vector3, noise: float) -> Color:
	var rock := Color(0.42, 0.37, 0.34)
	match map:
		"rural":
			var field := _nfield.get_noise_2d(x * 0.9, z * 1.3) * 0.5 + 0.5
			var crops := [Color(0.62, 0.55, 0.25), Color(0.24, 0.4, 0.13), Color(0.36, 0.27, 0.17), Color(0.45, 0.5, 0.2), Color(0.3, 0.45, 0.16)]
			var c: Color = crops[clampi(int(field * 4.99), 0, 4)]
			c = c.lerp(c.darkened(0.15), noise * 0.5 + 0.5)
			var rd := road_distance(x, z)
			if rd < 9.0:
				c = c.lerp(Color(0.42, 0.36, 0.28), clampf((9.0 - rd) / 2.5, 0.0, 1.0))
			if rd < 4.5:
				c = Color(0.2, 0.2, 0.21).lerp(Color(0.24, 0.24, 0.25), noise * 0.5 + 0.5)
			c = c.lerp(rock, clampf((1.0 - n.y - 0.25) * 3.0, 0.0, 1.0))
			return c
		"industrial":
			var dc := Vector2(x, z).length()
			var conc := Color(0.38, 0.37, 0.35).lerp(Color(0.3, 0.29, 0.28), noise * 0.5 + 0.5)
			var grass := Color(0.22, 0.32, 0.14).lerp(Color(0.32, 0.36, 0.18), noise * 0.5 + 0.5)
			var c := conc.lerp(grass, smoothstep(300.0, 380.0, dc))
			if fmod(absf(x) + 3.0, 80.0) < 6.0 or fmod(absf(z) + 3.0, 80.0) < 6.0:
				c = c.lerp(Color(0.22, 0.22, 0.23), 1.0 - smoothstep(300.0, 340.0, dc))
			if road_distance(x, z) < 6.0:
				c = Color(0.19, 0.19, 0.2)
			return c
	var grass2 := Color(0.1, 0.34, 0.09).lerp(Color(0.26, 0.46, 0.12), noise * 0.5 + 0.5)
	var sand := Color(0.78, 0.68, 0.5)
	var col := grass2
	var steep := 1.0 - n.y
	col = col.lerp(rock, clampf((steep - 0.22) * 4.0, 0.0, 1.0))
	col = col.lerp(rock.lightened(0.15), clampf((h - 52.0) / 20.0, 0.0, 1.0))
	col = col.lerp(sand, clampf((3.0 - h) / 3.0, 0.0, 1.0))
	if h < -1.0:
		col = col.lerp(Color(0.22, 0.28, 0.3), clampf((-h - 1.0) / 6.0, 0.0, 1.0))
	if Vector2(x, z).distance_to(Vector2(-22, -2)) < 8.0:
		col = Color(0.45, 0.44, 0.42)     # the driveway in front of the garage
	return col


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.2, half * 2.2)
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


# --- buildings ---------------------------------------------------------------------------------------
func _bld(x: float, z: float, size: Vector3, yaw: float, kind: String, color: Color) -> void:
	var y := height(x, z) - 0.3
	buildings.append({"pos": Vector3(x, y, z), "size": size, "yaw": yaw, "kind": kind, "color": color})
	_add_box(Vector3(x, y + size.y * 0.5, z), size * 0.5, yaw)
	exclusions.append(Vector2(x, z))


func _plan_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map.hash()
	var anchors: Dictionary = map_info(map)["anchors"]
	match map:
		"testing":
			_bld(-22, -10, Vector3(8, 3.4, 9), 0.0, "garage", Color(0.7, 0.68, 0.62))
			_bld(-33, -10, Vector3(9, 5.8, 9), 0.0, "house", Color(0.76, 0.7, 0.6))
		"rural":
			var f: Vector2 = anchors["farm"]
			_bld(f.x, f.y, Vector3(11, 7, 17), 0.3, "barn", Color(0.55, 0.16, 0.12))
			_bld(f.x + 22, f.y - 6, Vector3(7, 5, 9), 0.3, "house", Color(0.86, 0.84, 0.78))
			_bld(f.x - 14, f.y + 10, Vector3(5, 12, 5), 0.0, "silo", Color(0.7, 0.72, 0.72))
			_bld(f.x - 20, f.y + 4, Vector3(5, 10, 5), 0.0, "silo", Color(0.7, 0.72, 0.72))
			_bld(f.x + 6, f.y + 20, Vector3(8, 3.5, 6), 0.3, "shed", Color(0.4, 0.42, 0.42))
			# a village along the road
			var a4: Vector2 = RURAL_ROAD[4]
			var a5: Vector2 = RURAL_ROAD[5]
			var dirv := (a5 - a4).normalized()
			for i in 7:
				var rp := a4.lerp(a5, (float(i) + 0.5) / 7.0)
				var side := 1.0 if i % 2 == 0 else -1.0
				var hp := rp + Vector2(-dirv.y, dirv.x) * side * rng.randf_range(20.0, 30.0)
				_bld(hp.x, hp.y, Vector3(rng.randf_range(6, 8), rng.randf_range(4.5, 6), rng.randf_range(7, 10)), atan2(-dirv.x, -dirv.y), "house", Color.from_hsv(rng.randf_range(0.05, 0.12), 0.2, 0.85))
			# checkpoint: booth + sandbag walls by the road
			var c: Vector2 = anchors["checkpoint"]
			_bld(c.x + 9, c.y + 8, Vector3(3, 2.6, 3), 0.1, "booth", Color(0.32, 0.36, 0.25))
			for k in 4:
				_bld(c.x - 12 + k * 7, c.y + 16, Vector3(5, 1.1, 1.0), 0.15, "sandbag", Color(0.48, 0.42, 0.3))
			# training range berms
			var r: Vector2 = anchors["range"]
			for k in 3:
				_bld(r.x - 25 + k * 25, r.y - 30, Vector3(18, 2.5, 3), 0.0, "berm", Color(0.42, 0.33, 0.22))
		"industrial":
			var jam: Vector2 = anchors["radar_jam"]
			_bld(jam.x, jam.y, Vector3(34, 16, 26), 0.0, "factory", Color(0.48, 0.42, 0.36))
			_bld(jam.x + 28, jam.y - 12, Vector3(4, 38, 4), 0.0, "chimney", Color(0.5, 0.32, 0.25))
			_bld(jam.x + 36, jam.y - 2, Vector3(3.6, 30, 3.6), 0.0, "chimney", Color(0.5, 0.32, 0.25))
			var spots := [Vector2(-130, -40), Vector2(-70, -150), Vector2(210, -10), Vector2(220, -130), Vector2(-180, 110), Vector2(40, 235), Vector2(-90, 235), Vector2(230, 230), Vector2(-240, -150), Vector2(110, -210)]
			for sp in spots:
				var rot := 0.0 if rng.randf() < 0.5 else PI * 0.5
				_bld(sp.x, sp.y, Vector3(rng.randf_range(22, 30), rng.randf_range(9, 13), rng.randf_range(36, 50)), rot, "warehouse", Color.from_hsv(rng.randf_range(0.0, 0.1), rng.randf_range(0.05, 0.25), rng.randf_range(0.42, 0.6)))
			# container stacks around the yard edges
			var y: Vector2 = anchors["yard"]
			for k in 8:
				var a := k * TAU / 8.0
				var cp := y + Vector2(cos(a) * 48.0, sin(a) * 38.0)
				var stack := 1 + rng.randi() % 2
				_bld(cp.x, cp.y, Vector3(2.5, 2.6 * stack, 6.1), a, "container_stack", Color.from_hsv(rng.randf(), 0.5, 0.5))
			for p in [Vector2(-300, -300), Vector2(300, -300), Vector2(300, 300)]:
				_bld(p.x, p.y, Vector3(3, 18, 3), 0.0, "water_tower", Color(0.4, 0.4, 0.38))


func _build_buildings() -> void:
	var mats := {}
	var roof_dark := MeshFactory.mat(Color(0.25, 0.2, 0.18), 0.1, 0.8)
	var window := MeshFactory.mat(Color(0.12, 0.15, 0.18), 0.4, 0.2)
	for b in buildings:
		var col: Color = b["color"]
		var key := str(col)
		if not mats.has(key):
			mats[key] = MeshFactory.mat(col, 0.1, 0.85)
		var m: StandardMaterial3D = mats[key]
		var root := Node3D.new()
		root.position = b["pos"]
		root.rotation.y = b["yaw"]
		add_child(root)
		var s: Vector3 = b["size"]
		var kind: String = b["kind"]
		match kind:
			"silo", "chimney", "water_tower":
				if kind == "water_tower":
					for k in 4:
						var a := k * PI * 0.5 + PI * 0.25
						MeshFactory.box(root, Vector3(0.3, s.y, 0.3), Vector3(cos(a) * 1.4, s.y * 0.5, sin(a) * 1.4), m)
					MeshFactory.cyl(root, 4.0, 5.0, Vector3(0, s.y + 2.5, 0), m, Vector3.ZERO, 12)
				else:
					MeshFactory.cyl(root, s.x * 0.5, s.y, Vector3(0, s.y * 0.5, 0), m, Vector3.ZERO, 12)
					if kind == "silo":
						MeshFactory.sphere(root, s.x * 0.5, Vector3(0, s.y, 0), m)
			_:
				MeshFactory.box(root, s, Vector3(0, s.y * 0.5, 0), m)
				if kind in ["house", "barn", "garage", "shed", "booth"]:
					# gable roof: a triangular prism
					var prism := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = s.x * 0.62
					cm.bottom_radius = s.x * 0.62
					cm.height = s.z * 1.04
					cm.radial_segments = 3
					cm.rings = 1
					prism.mesh = cm
					prism.material_override = roof_dark if kind != "barn" else MeshFactory.mat(Color(0.3, 0.3, 0.32), 0.3, 0.6)
					prism.rotation_degrees = Vector3(90, 0, 0)
					prism.position = Vector3(0, s.y + s.x * 0.15, 0)
					prism.scale = Vector3(1, 1, 0.5)
					root.add_child(prism)
					if kind == "house":
						for wx in [-0.25, 0.25]:
							MeshFactory.box(root, Vector3(s.x * 0.18, s.y * 0.25, 0.05), Vector3(s.x * wx, s.y * 0.55, -s.z * 0.5 - 0.02), window)
					if kind in ["garage", "barn"]:
						MeshFactory.box(root, Vector3(s.x * 0.6, s.y * 0.7, 0.05), Vector3(0, s.y * 0.35, s.z * 0.5 + 0.02), MeshFactory.mat(Color(0.7, 0.7, 0.72), 0.4, 0.5))
				elif kind in ["warehouse", "factory"]:
					var strip := MeshFactory.mat(col.darkened(0.18), 0.3, 0.7)
					for k in 6:
						MeshFactory.box(root, Vector3(s.x + 0.04, 0.35, s.z + 0.04), Vector3(0, s.y * (0.15 + k * 0.14), 0), strip)
					MeshFactory.box(root, Vector3(s.x * 0.4, s.y * 0.55, 0.1), Vector3(0, s.y * 0.275, s.z * 0.5 + 0.05), MeshFactory.mat(Color(0.25, 0.27, 0.28), 0.5, 0.5))
					for k in 3:
						MeshFactory.box(root, Vector3(s.x * 0.8, 0.3, 2.0), Vector3(0, s.y + 0.15, -s.z * 0.3 + k * s.z * 0.3), window)
	if map == "industrial":
		var anchors: Dictionary = map_info(map)["anchors"]
		var y: Vector2 = anchors["yard"]
		var rail := MeshFactory.mat(Color(0.3, 0.28, 0.26), 0.7, 0.5)
		for k in 3:
			for side in [-0.75, 0.75]:
				MeshFactory.box(self, Vector3(160, 0.15, 0.12), Vector3(y.x, height(y.x, y.y) + 0.08, y.y - 20 + k * 6 + side), rail)
		var hp: Vector2 = anchors["helipad"]
		var hy := height(hp.x, hp.y)
		MeshFactory.cyl(self, 9.0, 0.2, Vector3(hp.x, hy + 0.1, hp.y), MeshFactory.mat(Color(0.25, 0.26, 0.27), 0.1, 0.8), Vector3.ZERO, 24)
		var hm := MeshFactory.mat(Color(0.95, 0.85, 0.2), 0.0, 0.6)
		MeshFactory.box(self, Vector3(1.2, 0.05, 7), Vector3(hp.x - 2.5, hy + 0.22, hp.y), hm)
		MeshFactory.box(self, Vector3(1.2, 0.05, 7), Vector3(hp.x + 2.5, hy + 0.22, hp.y), hm)
		MeshFactory.box(self, Vector3(4, 0.05, 1.2), Vector3(hp.x, hy + 0.22, hp.y), hm)


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024 + absi(map.hash()) % 1000 if map != "testing" else 2024
	var want: int = quality["trees"]
	if map == "industrial":
		want = int(want * 0.6)
	var pts: Array = []
	var tries := 0
	var launch := Vector2(start_position().x, start_position().z)
	while pts.size() < want and tries < want * 40:
		tries += 1
		if tries % 150 == 0:
			await get_tree().process_frame
		var x := rng.randf_range(-half + 20.0, half - 20.0)
		var z := rng.randf_range(-half + 20.0, half - 20.0)
		if Vector2(x, z).distance_to(launch) < 55.0:
			continue
		var h := height(x, z)
		if h < 2.0 or h > 62.0:
			continue
		var slope := absf(height(x + 2.0, z) - h) + absf(height(x, z + 2.0) - h)
		if slope > 2.6:
			continue
		match map:
			"testing":
				if _nf.get_noise_2d(x, z) < -0.12:
					continue
			"rural":
				# hedgerows on field borders + a few copses
				var e := _nfield.get_noise_2d(x * 0.9, z * 1.3)
				var e2 := _nfield.get_noise_2d(x * 0.9 + 4.0, z * 1.3 + 4.0)
				var border := absf(e - e2) > 0.01
				if not border and _nf.get_noise_2d(x, z) < 0.3:
					continue
				if road_distance(x, z) < 12.0:
					continue
			"industrial":
				if Vector2(x, z).length() < 330.0 and _nf.get_noise_2d(x, z) < 0.4:
					continue
				if road_distance(x, z) < 10.0:
					continue
		var blocked := false
		for ex in exclusions:
			if Vector2(x, z).distance_to(ex) < 22.0:
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
				var leaf := Color(0.05, 0.25, 0.08).lerp(Color(0.14, 0.4, 0.1), g)
				if map == "rural" and g > 0.85:
					leaf = Color(0.45, 0.4, 0.12)
				mm.set_instance_color(i, leaf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = trunk_mat if kind == 0 else fol_mat
		mmi.custom_aabb = AABB(Vector3(-half, -20, -half), Vector3(half * 2, 140, half * 2))
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
		MeshFactory.cyl(self, 0.06, 1.8, c + Vector3(cos(ang) * 6.5, 0.9, sin(ang) * 6.5), MeshFactory.mat(Color(0.9, 0.9, 0.95)), Vector3.ZERO, 6)
		MeshFactory.box(self, Vector3(0.7, 0.4, 0.04), c + Vector3(cos(ang) * 6.5 + 0.35, 1.6, sin(ang) * 6.5), MeshFactory.mat(Color(1, 0.35, 0.1), 0.0, 0.6, 0.4))
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if map != "testing":
		# field launch point: crates and a camo net
		var crate := MeshFactory.mat(Color(0.3, 0.33, 0.2), 0.1, 0.8)
		MeshFactory.box(self, Vector3(1.2, 0.7, 0.8), c + Vector3(5.5, 0.35, 2.0), crate)
		MeshFactory.box(self, Vector3(0.9, 0.6, 0.7), c + Vector3(6.2, 0.95, 2.2), crate)
		MeshFactory.box(self, Vector3(3.0, 0.08, 2.0), c + Vector3(-6, 1.8, 3.0), MeshFactory.mat(Color(0.25, 0.28, 0.18), 0.0, 0.9))
		for sx in [-7.4, -4.6]:
			for sz in [2.1, 3.9]:
				MeshFactory.cyl(self, 0.04, 1.8, c + Vector3(sx, 0.9, sz), MeshFactory.mat(Color(0.2, 0.2, 0.2)), Vector3.ZERO, 6)
