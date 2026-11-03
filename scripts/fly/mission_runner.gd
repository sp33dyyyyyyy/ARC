class_name MissionRunner
extends Node3D
## Runs a career combat / recon mission inside FlyStage: spawns the fictional targets,
## scripts their behaviour, resolves abstract payload hits and impact strikes, tracks
## scanning progress and objectives, and decides when the mission is complete or failed.

signal notice(text: String, color: Color)
signal objective_destroyed(t: CombatTarget)

var mission: Dictionary = {}
var world: FlyWorld
var targets: Array = []           # CombatTarget
var phase := "active"             # active / rtb / failed
var kills := 0
var score := 0
var jam_level := 0.0
var _proj: Array = []
var _type := "strike"


func setup(m: Dictionary, w: FlyWorld) -> void:
	mission = m
	world = w
	_type = m.get("type", "strike")
	var rng := RandomNumberGenerator.new()
	rng.seed = String(m.get("id", "x")).hash()
	for spec in m.get("targets", []):
		var kind: String = spec.get("kind", "truck")
		if kind == "convoy":
			_spawn_convoy(spec)
			continue
		var n := int(spec.get("n", 1))
		var base := world.anchor(spec.get("at", "course"))
		for i in n:
			var off := Vector3.ZERO
			if n > 1 or spec.get("at", "") in ["checkpoint", "yard"]:
				var a := rng.randf() * TAU
				off = Vector3(cos(a), 0, sin(a)) * rng.randf_range(8.0, 22.0)
				if kind == "board":
					off = Vector3(-25 + i * 25, 0, -24 + rng.randf_range(-3, 3))
			var p := base + off
			p.y = world.top_at(p.x, p.z)
			if kind == "jammer":
				p = base
			var t := CombatTarget.create(kind, world, p, rng.randf() * TAU if kind != "board" else 0.0)
			t.objective = spec.get("objective", true)
			add_child(t)
			targets.append(t)
			if kind.begins_with("heli"):
				t.waypoints = _heli_route(spec.get("patrol", "loop"), rng)
			elif kind == "uav":
				t.home = world.anchor("sky") + Vector3(0, 80.0 + i * 12.0, 0)
				t.timer = i * 9.0
				t.global_position = t.home + Vector3(150, 0, 0)
			t.destroyed.connect(_on_destroyed)
	for t in targets:
		world.exclusions.append(Vector2(t.global_position.x, t.global_position.z))


func _heli_route(kind: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var n := 5 if kind == "loop" else 6
	var r := 230.0 if kind == "loop" else 380.0
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * i / n
		var p := Vector3(cos(a) * r, 0, sin(a) * r * 0.8)
		p.y = world.top_at(p.x, p.z) + (45.0 if kind == "loop" else 70.0)
		out.append(p)
	return out


func _spawn_convoy(spec: Dictionary) -> void:
	var pts := world.road_points()
	if pts.size() < 2:
		return
	var s0: float = maxf(world.road_s_near(world.anchor("convoy").x, world.anchor("convoy").z) - 330.0, 40.0)
	var units: Array = spec.get("units", ["truck"])
	var leader: CombatTarget = null
	for i in units.size():
		var t := CombatTarget.create(units[i], world, Vector3.ZERO, 0.0)
		add_child(t)
		var sp := 7.0 if units.has("tank") else 8.0
		t.set_road(pts, s0 - i * 16.0, sp)
		t.leader = leader
		t.follow_gap = 16.0
		t.objective = i == int(spec.get("objective_index", 0))
		t.destroyed.connect(_on_destroyed)
		targets.append(t)
		leader = t


func _on_destroyed(t: CombatTarget) -> void:
	kills += 1
	score += t.score
	Career.data["stats"]["targets"] = int(Career.data["stats"]["targets"]) + 1
	Pad.rumble(0.5, 0.7, 0.4)
	notice.emit("DESTROYED: %s%s" % [t.title, "  (objective)" if t.objective else "  (+%d bonus)" % int(t.score * 0.5)], Hud.GREEN if t.objective else Hud.AMBER)
	if t.objective:
		objective_destroyed.emit(t)
	_check_done()


func objectives_done() -> bool:
	var any := false
	for t in targets:
		if not t.objective:
			continue
		any = true
		if _type == "recon":
			if t.scanned < 1.0:
				return false
		elif not t.dead:
			return false
	return any


func _check_done() -> void:
	if phase == "active" and objectives_done():
		phase = "rtb"
		notice.emit("OBJECTIVES COMPLETE - return to the launch point and land to recover the drone", Hud.GREEN)
		Audio.play("success")


func bonus_credits() -> int:
	var b := 0
	for t in targets:
		if t.dead and not t.objective:
			b += int(t.score * 0.5)
	return b


# --- per physics step ---------------------------------------------------------------------
func tick(dt: float, sim: DroneSim, cam: Camera3D, scan_mult: float) -> void:
	for t in targets:
		(t as CombatTarget).update(dt, sim.pos, sim.armed)
	# convoy escaped?
	if phase == "active":
		for t in targets:
			if t.objective and t.escaped and not t.dead:
				phase = "failed"
				notice.emit("MISSION FAILED - the objective left the area", Hud.RED)
	# recon scanning
	if _type == "recon" and cam != null:
		var fwd := -cam.global_transform.basis.z
		for t in targets:
			if t.dead or t.scanned >= 1.0:
				continue
			var to: Vector3 = t.center() - cam.global_position
			var d := to.length()
			if d > 190.0 * scan_mult or d < 1.0:
				continue
			var ang := rad_to_deg(fwd.angle_to(to / d))
			if ang > 10.0 * sqrt(scan_mult) + 120.0 / maxf(d, 10.0):
				continue
			if not _los(cam.global_position, t.center()):
				continue
			t.scanned = minf(t.scanned + dt / 2.2 * scan_mult, 1.0)
			if Engine.get_physics_frames() % 40 == 0:
				Audio.play("scan", 1.0 + t.scanned)
			if t.scanned >= 1.0:
				Audio.play("gate", 1.3)
				notice.emit("SCANNED: %s" % t.title, Hud.GREEN)
				Pad.rumble(0.2, 0.0, 0.15)
				_check_done()
	# projectiles
	for i in range(_proj.size() - 1, -1, -1):
		var p: Dictionary = _proj[i]
		p["vel"] = (p["vel"] as Vector3) + Vector3(0, -9.81, 0) * dt - (p["vel"] as Vector3) * 0.02 * dt
		var np: Vector3 = (p["pos"] as Vector3) + (p["vel"] as Vector3) * dt
		p["pos"] = np
		p["t"] = float(p["t"]) + dt
		(p["node"] as Node3D).global_position = np
		var hit: CombatTarget = null
		for t in targets:
			if not t.dead and t.contains(np, 0.4):
				hit = t
				break
		if hit != null or np.y <= world.top_at(np.x, np.z) or float(p["t"]) > 14.0 or (world.is_water(np.x, np.z) and np.y < FlyWorld.WATER_LEVEL):
			detonate(np, p["power"], p["radius"], hit)
			(p["node"] as Node3D).queue_free()
			_proj.remove_at(i)
	# jammer + vehicle audio
	jam_level = 0.0
	var eng := Vector2.ZERO
	for t in targets:
		if t.kind == "jammer" and not t.dead:
			jam_level = maxf(jam_level, clampf(1.0 - sim.pos.distance_to(t.global_position) / 260.0, 0.0, 1.0))
		var e: Vector2 = t.engine_sound(sim.pos)
		if e.x > eng.x:
			eng = e
	Audio.engine_level = eng.x
	Audio.engine_chop = eng.y
	Audio.engine_pitch = 0.5


func _los(a: Vector3, b: Vector3) -> bool:
	for k in [0.25, 0.5, 0.75]:
		var p := a.lerp(b, k)
		if world.top_at(p.x, p.z) > p.y + 0.5:
			return false
	return true


## Releases one abstract training pod from the drone.
func release(sim: DroneSim, power: float, radius: float) -> void:
	var n := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.05
	cm.height = 0.25
	n.mesh = cm
	n.material_override = MeshFactory.mat(Color(0.3, 0.34, 0.22), 0.2, 0.6)
	add_child(n)
	var p0 := sim.pos + sim.basis * Vector3(0, -0.06, 0)
	n.global_position = p0
	_proj.append({"node": n, "pos": p0, "vel": sim.vel + Vector3(0, -1.0, 0), "power": power, "radius": radius, "t": 0.0})
	Audio.play("release")
	Pad.rumble(0.3, 0.0, 0.12)


## Predicted impact point of a pod released now (for the drop reticle).
func predict_impact(sim: DroneSim) -> Vector3:
	var p := sim.pos
	var v := sim.vel + Vector3(0, -1.0, 0)
	var dt := 0.05
	for i in 240:
		v += Vector3(0, -9.81, 0) * dt - v * 0.02 * dt
		p += v * dt
		if p.y <= world.top_at(p.x, p.z):
			return p
		for t in targets:
			if not t.dead and t.contains(p, 0.4):
				return p
	return p


## Abstract area damage. Returns the total damage dealt.
func detonate(point: Vector3, power: float, radius: float, direct: CombatTarget) -> float:
	var total := 0.0
	Fx.blast(self, point, clampf(0.6 + power / 160.0, 0.6, 1.8))
	Audio.play("explosion", randf_range(0.95, 1.15))
	for t in targets:
		if t.dead or t.escaped:
			continue
		var d: float = 0.0 if t == direct else t.distance_to_box(point)
		if d >= radius:
			continue
		var k := pow(1.0 - d / radius, 0.7)
		var dealt: float = t.damage(power * k)
		total += dealt
		if dealt > 0.0 and not t.dead:
			notice.emit("HIT %s  -%d  (%d %%)" % [t.title, int(dealt), int(t.hp / t.max_hp * 100.0)], Hud.AMBER)
	if total <= 0.0:
		notice.emit("Miss", Hud.WHITE)
	return total


## Target the drone flew into this step (or null).
func impact_target(sim: DroneSim) -> CombatTarget:
	for t in targets:
		if not t.dead and not t.escaped and t.contains(sim.pos, 0.15):
			return t
	return null


func objective_lines() -> Array:
	var out: Array = []
	for t in targets:
		if not t.objective:
			continue
		if _type == "recon":
			out.append("%s %s  %s" % ["✓" if t.scanned >= 1.0 else "▢", "Scan " + t.title, "" if t.scanned >= 1.0 else "%d %%" % int(t.scanned * 100.0)])
		else:
			out.append("%s Destroy %s%s" % ["✓" if t.dead else "▢", t.title, "" if t.dead else "  %d %%" % int(t.hp / t.max_hp * 100.0)])
	if phase == "rtb":
		out.append("▢ Return to launch and land")
	return out


## Nearest objective (or launch point in RTB) for the HUD arrow.
func guide_point(from: Vector3) -> Vector3:
	if phase == "rtb":
		return world.start_position()
	var best := Vector3.INF
	var bd := 1e9
	for t in targets:
		if t.objective and not t.dead and not (_type == "recon" and t.scanned >= 1.0):
			var d := from.distance_to(t.global_position)
			if d < bd:
				bd = d
				best = t.center()
	return best
