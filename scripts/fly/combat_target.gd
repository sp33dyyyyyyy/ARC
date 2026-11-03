class_name CombatTarget
extends Node3D
## A fictional hostile target: ground vehicle on a road, helicopter, patrol UAV or a
## static objective. Abstract health/armour, visible damage states (smoke, fire, wreck)
## and simple scripted AI. Nothing here models real weapon or vulnerability data.

signal destroyed(t: CombatTarget)

enum M { STATIC, ROAD, HELI, UAV }

var kind := "truck"
var title := ""
var hp := 100.0
var max_hp := 100.0
var armour := 0.0
var size := Vector3(2, 2, 4)
var score := 100
var objective := false
var dead := false
var escaped := false
var scanned := 0.0            # 0..1 recon progress
var motion: int = M.STATIC
var world: FlyWorld
var model: Node3D
var alert := false
var state := "idle"

# road
var path: PackedVector3Array = PackedVector3Array()
var path_len := 0.0
var _cum: PackedFloat32Array = PackedFloat32Array()
var s := 0.0
var speed := 8.0
var cruise := 8.0
var leader: CombatTarget = null
var follow_gap := 14.0

# air
var vel := Vector3.ZERO
var yaw := 0.0
var home := Vector3.ZERO
var waypoints: Array = []
var wp := 0
var alt := 45.0
var timer := 0.0
var rotor_speed := 0.0
var _evade_t := 0.0
var _spin := 0.0
var _loops := 0

var _rotor: Node3D = null
var _tail: Node3D = null
var _dish: Node3D = null
var _turret: Node3D = null
var _smoke: Node3D = null
var _fire: Node3D = null
var _wheels: Array = []
var _rng := RandomNumberGenerator.new()


static func create(p_kind: String, p_world: FlyWorld, pos: Vector3, p_yaw: float) -> CombatTarget:
	var t := CombatTarget.new()
	t.kind = p_kind
	t.world = p_world
	var d: Dictionary = Campaign.TARGETS.get(p_kind, Campaign.TARGETS["truck"])
	t.title = d["name"]
	t.max_hp = d["hp"]
	t.hp = d["hp"]
	t.armour = d["armour"]
	t.size = d["size"] * 2.0
	t.score = d["score"]
	t.model = VehicleKit.make(p_kind)
	t.add_child(t.model)
	t._wheels = t.model.get_meta("wheels") if t.model.has_meta("wheels") else []
	t._rotor = t.model.get_meta("rotor") if t.model.has_meta("rotor") else null
	t._tail = t.model.get_meta("tail_rotor") if t.model.has_meta("tail_rotor") else null
	t._dish = t.model.get_meta("dish") if t.model.has_meta("dish") else null
	t._turret = t.model.get_meta("turret") if t.model.has_meta("turret") else null
	t.position = pos
	t.yaw = p_yaw
	t.rotation.y = p_yaw
	t._rng.seed = int(pos.x * 13.0 + pos.z * 7.0)
	match p_kind:
		"heli_scout", "heli_transport":
			t.motion = M.HELI
			t.state = "landed"
			t.home = pos
			t.cruise = 20.0 if p_kind == "heli_scout" else 16.0
			t.rotor_speed = 0.6
		"uav":
			t.motion = M.UAV
			t.state = "patrol"
			t.cruise = 24.0
			t.rotor_speed = 1.0
	return t


func is_air() -> bool:
	return motion == M.HELI or motion == M.UAV


## Centre of the bounding box in world space.
func center() -> Vector3:
	return global_transform * Vector3(0, size.y * 0.5, 0)


## Point-vs-oriented-box test (with a margin). Returns true when p is inside.
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var l := global_transform.affine_inverse() * p
	var h := size * 0.5 + Vector3.ONE * margin
	return absf(l.x) <= h.x and l.y >= -margin and l.y <= size.y + margin and absf(l.z) <= h.z


## Distance from p to the box surface (0 inside).
func distance_to_box(p: Vector3) -> float:
	var l := global_transform.affine_inverse() * p
	var h := size * 0.5
	var q := Vector3(maxf(absf(l.x) - h.x, 0.0), maxf(maxf(-l.y, l.y - size.y), 0.0), maxf(absf(l.z) - h.z, 0.0))
	return q.length()


# --- setup helpers ---------------------------------------------------------------------
func set_road(points: PackedVector3Array, start_s: float, p_speed: float) -> void:
	motion = M.ROAD
	path = points
	_cum.resize(points.size())
	var acc := 0.0
	for i in points.size():
		if i > 0:
			acc += points[i].distance_to(points[i - 1])
		_cum[i] = acc
	path_len = acc
	s = start_s
	cruise = p_speed
	speed = p_speed
	state = "drive"
	_apply_road_pose(0.0)


func _sample(d: float) -> Vector3:
	d = clampf(d, 0.0, path_len)
	var i := _cum.bsearch(d)
	i = clampi(i, 1, path.size() - 1)
	var seg := _cum[i] - _cum[i - 1]
	var k := 0.0 if seg <= 0.001 else (d - _cum[i - 1]) / seg
	return path[i - 1].lerp(path[i], k)


func _apply_road_pose(dt: float) -> void:
	var p := _sample(s)
	var a := _sample(s + 3.0)
	var b := _sample(s - 3.0)
	p.y = world.height(p.x, p.z)
	a.y = world.height(a.x, a.z)
	b.y = world.height(b.x, b.z)
	var fwd := (a - b)
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var target_yaw := atan2(-fwd.x, -fwd.z)
	yaw = target_yaw if dt == 0.0 else lerp_angle(yaw, target_yaw, minf(dt * 4.0, 1.0))
	var pitch := asin(clampf(fwd.y, -0.5, 0.5))
	global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), p)


# --- damage --------------------------------------------------------------------------------
## Applies abstract damage (already distance-scaled). Returns the damage dealt.
func damage(amount: float) -> float:
	if dead:
		return 0.0
	var dealt := amount * (1.0 - armour)
	hp = maxf(hp - dealt, 0.0)
	alert = true
	if motion == M.ROAD and not dead:
		cruise *= 1.0 if speed > cruise * 1.2 else 1.35
	if hp <= max_hp * 0.55 and _smoke == null:
		_smoke = Fx.smoke(self, Vector3(0, size.y * 0.9, 0), clampf(size.length() / 6.0, 0.6, 1.6), 0.6)
	if hp <= max_hp * 0.25 and _fire == null:
		_fire = Fx.fire(self, Vector3(0, size.y * 0.7, 0.3), clampf(size.length() / 7.0, 0.5, 1.4))
	if hp <= 0.0:
		_destroy()
	return dealt


func _destroy() -> void:
	if dead:
		return
	if motion == M.HELI or motion == M.UAV:
		if global_position.y - world.top_at(global_position.x, global_position.z) > 1.5:
			state = "crashing"
			alert = true
			if _smoke == null:
				_smoke = Fx.smoke(self, Vector3(0, size.y * 0.8, 0), 1.2, 0.85)
			return
	_wreck()


func _wreck() -> void:
	dead = true
	state = "destroyed"
	speed = 0.0
	Fx.blast(get_parent(), center(), clampf(size.length() / 5.0, 0.7, 1.8))
	Audio.play("explosion", randf_range(0.85, 1.05))
	Fx.char_meshes(model)
	var tur := _turret
	if tur:
		tur.rotation.y += _rng.randf_range(0.5, 1.5)
		tur.rotation.z += _rng.randf_range(-0.25, 0.25)
		tur.position.y += 0.2
	var rotor := _rotor
	if rotor:
		var blur := rotor.get_node_or_null("Blur")
		if blur:
			blur.visible = false
	model.rotation = Vector3(_rng.randf_range(-0.06, 0.06), 0, _rng.randf_range(-0.12, 0.12))
	if is_air():
		global_position.y = world.top_at(global_position.x, global_position.z)
		model.rotation.z = _rng.randf_range(-0.6, 0.6)
	if _smoke == null:
		_smoke = Fx.smoke(self, Vector3(0, size.y * 0.8, 0), 1.3, 0.9)
	if _fire == null:
		_fire = Fx.fire(self, Vector3(0, size.y * 0.5, 0), clampf(size.length() / 7.0, 0.6, 1.4))
	destroyed.emit(self)


# --- AI --------------------------------------------------------------------------------------
func update(dt: float, drone_pos: Vector3, drone_armed: bool) -> void:
	# rotors and dishes spin while alive
	var rotor := _rotor
	if rotor and not dead:
		rotor.rotation.y += rotor_speed * 38.0 * dt if motion == M.HELI else 0.0
		if motion == M.UAV:
			rotor.rotation.z += 60.0 * dt
	var tr := _tail
	if tr and not dead:
		tr.rotation.x += rotor_speed * 60.0 * dt
	var dish := _dish
	if dish and not dead:
		dish.rotation.y += dt * (1.2 if kind != "jammer" else 0.0)
		var lamp := dish.get_node_or_null("Lamp")
		if lamp:
			lamp.visible = fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0
	if dead:
		return
	if not alert and drone_armed and drone_pos.distance_to(global_position) < (160.0 if is_air() else 90.0):
		alert = true
	match motion:
		M.ROAD: _update_road(dt)
		M.HELI: _update_heli(dt, drone_pos)
		M.UAV: _update_uav(dt)
	var tur := _turret
	if tur and motion == M.ROAD:
		tur.rotation.y = sin(Time.get_ticks_msec() * 0.0004 + position.x) * 0.6


func _update_road(dt: float) -> void:
	if state != "drive":
		return
	var want := cruise
	if leader != null and is_instance_valid(leader):
		if leader.dead:
			# go around the wreck: slow down and keep a bigger gap
			want = cruise * 0.6
		var gap := leader.s - s
		if gap < follow_gap:
			want = minf(want, maxf(leader.speed * (gap / follow_gap), 0.0))
		elif gap > follow_gap * 1.5:
			want = cruise * 1.25
		if leader.dead and gap < follow_gap * 0.8:
			want = 0.0
	speed = move_toward(speed, want, 3.0 * dt)
	s += speed * dt
	for w in _wheels:
		(w as Node3D).rotation.x -= speed * dt / 0.55
	_apply_road_pose(dt)
	if s >= path_len - 2.0:
		escaped = true
		state = "escaped"
		visible = false


func _update_heli(dt: float, drone_pos: Vector3) -> void:
	var gy := world.top_at(global_position.x, global_position.z)
	match state:
		"landed":
			rotor_speed = move_toward(rotor_speed, 0.75, dt * 0.3)
			timer += dt
			if timer > (14.0 if _loops == 0 else 22.0) or alert:
				state = "takeoff"
				timer = 0.0
		"takeoff":
			rotor_speed = move_toward(rotor_speed, 1.0, dt * 0.5)
			if rotor_speed > 0.95:
				vel = vel.lerp(Vector3(0, 3.5, 0), minf(dt * 2.0, 1.0))
				if global_position.y - gy > 14.0:
					state = "patrol"
		"patrol", "evade", "return":
			var target: Vector3 = home + Vector3(0, 14.0, 0) if state == "return" else waypoints[wp]
			var extra := 22.0 if state == "evade" else 0.0
			target.y = maxf(target.y + extra, world.top_at(target.x, target.z) + 25.0 + extra)
			var to := target - global_position
			var spd := cruise * (1.45 if state == "evade" else 1.0)
			var dist := to.length()
			var desired := to.normalized() * minf(spd, dist * 0.35 + 2.0)
			vel = vel.move_toward(desired, 5.0 * dt)
			if state == "evade":
				_evade_t -= dt
				if _evade_t <= 0.0:
					state = "patrol"
			if alert and state == "patrol" and _evade_t <= -12.0:
				state = "evade"
				_evade_t = 14.0
			elif state == "patrol":
				_evade_t -= dt
			if state == "return" and Vector2(to.x, to.z).length() < 6.0:
				state = "landing"
			elif state != "return" and dist < 22.0:
				wp += 1
				if wp >= waypoints.size():
					wp = 0
					_loops += 1
					if not alert:
						state = "hover"
						timer = 0.0
		"hover":
			vel = vel.move_toward(Vector3.ZERO, 4.0 * dt)
			timer += dt
			if timer > 5.0:
				state = "return"
		"landing":
			var to2 := home - global_position
			vel = vel.move_toward(Vector3(to2.x * 0.5, clampf(to2.y * 0.6, -3.0, -0.6), to2.z * 0.5), 3.0 * dt)
			if global_position.y - home.y < 0.15:
				global_position.y = home.y
				vel = Vector3.ZERO
				state = "landed"
				timer = 0.0
		"crashing":
			_spin = minf(_spin + dt * 3.0, 9.0)
			vel.y -= 9.81 * dt * 0.8
			vel.x *= 1.0 - dt * 0.3
			vel.z *= 1.0 - dt * 0.3
			yaw += _spin * dt
			global_position += vel * dt
			rotation = Vector3(0.25, yaw, 0.35 * sin(Time.get_ticks_msec() * 0.003))
			rotor_speed = maxf(rotor_speed - dt * 0.3, 0.2)
			if global_position.y <= world.top_at(global_position.x, global_position.z) + 0.2:
				_wreck()
			return
	global_position += vel * dt
	var floor_y := world.top_at(global_position.x, global_position.z)
	if global_position.y < floor_y and state != "landing":
		global_position.y = floor_y
	# attitude from motion
	var hv := Vector2(vel.x, vel.z)
	if hv.length() > 1.5:
		var target_yaw := atan2(-vel.x, -vel.z)
		var dyaw := wrapf(target_yaw - yaw, -PI, PI)
		var rate := clampf(dyaw, -0.9, 0.9)
		yaw += rate * dt
		var fwd_speed := hv.length()
		rotation = Vector3(-clampf(fwd_speed / cruise, 0.0, 1.4) * deg_to_rad(10.0), yaw, -rate * clampf(fwd_speed / cruise, 0.0, 1.0) * deg_to_rad(22.0))
	else:
		rotation = Vector3(rotation.x * 0.95, yaw, rotation.z * 0.95)


func _update_uav(dt: float) -> void:
	if state == "crashing":
		vel.y -= 9.81 * dt
		global_position += vel * dt
		rotation.z += dt * 5.0
		if global_position.y <= world.top_at(global_position.x, global_position.z) + 0.2:
			_wreck()
		return
	timer += dt
	var r := 150.0
	var ang := timer * cruise / r
	var target := home + Vector3(cos(ang) * r, 0, sin(ang) * r)
	vel = (target - global_position) / maxf(dt, 0.001)
	vel = vel.limit_length(cruise * 1.5)
	global_position = target
	yaw = atan2(-(-sin(ang)), -(cos(ang)))
	rotation = Vector3(0, yaw, deg_to_rad(-18.0))


## For the vehicle sound mix: {level, chop} heard from `ear`.
func engine_sound(ear: Vector3) -> Vector2:
	if dead or escaped:
		return Vector2.ZERO
	var d := ear.distance_to(global_position)
	match motion:
		M.ROAD:
			return Vector2(clampf(30.0 / (d + 10.0), 0.0, 1.0) * clampf(speed / 6.0, 0.3, 1.0), 0.0)
		M.HELI:
			return Vector2(clampf(80.0 / (d + 20.0), 0.0, 1.0) * clampf(rotor_speed, 0.0, 1.0), 1.0)
		M.UAV:
			return Vector2(clampf(25.0 / (d + 10.0), 0.0, 0.6), 0.0)
	return Vector2.ZERO
