class_name Missions
extends RefCounted
## Course layouts for the gate race and the battery challenge.

const GATE_XZ := [
	Vector2(10, -100), Vector2(90, -200), Vector2(200, -300), Vector2(330, -310),
	Vector2(430, -200), Vector2(430, -60), Vector2(340, 60), Vector2(200, 150),
	Vector2(60, 230), Vector2(-90, 260), Vector2(-200, 140), Vector2(-100, -20),
]
const ROUTE_XZ := [
	Vector2(80, -120), Vector2(180, -260), Vector2(300, -380), Vector2(450, -330),
	Vector2(520, -180), Vector2(500, 0), Vector2(420, 150), Vector2(300, 260),
	Vector2(150, 330), Vector2(-20, 380), Vector2(-190, 330), Vector2(-320, 200),
	Vector2(-360, 40), Vector2(-300, -130), Vector2(-160, -230), Vector2(-40, -110),
	Vector2(0, 0),
]
const GATE_AGL := 10.0
const ROUTE_AGL := 28.0


static func exclusions() -> Array:
	return GATE_XZ.duplicate()


## {"gates": [{"pos", "normal"}], "radius", "par", "limit"}
static func gate_race(world: FlyWorld) -> Dictionary:
	var pts: Array = []
	for xz in GATE_XZ:
		var y := maxf(world.height(xz.x, xz.y), FlyWorld.WATER_LEVEL) + GATE_AGL
		pts.append(Vector3(xz.x, y, xz.y))
	var gates: Array = []
	var length := 0.0
	var prev := world.start_position()
	for i in pts.size():
		var nxt: Vector3 = pts[i + 1] if i + 1 < pts.size() else world.start_position() + Vector3(0, GATE_AGL, 0)
		var dir: Vector3 = (nxt - prev)
		dir.y *= 0.3
		gates.append({"pos": pts[i], "normal": dir.normalized()})
		length += prev.distance_to(pts[i])
		prev = pts[i]
	return {"gates": gates, "radius": 3.1, "par": length / 21.0, "limit": length / 8.0, "length": length}


## {"points": [Vector3], "radius", "length"}
static func battery_route(world: FlyWorld) -> Dictionary:
	var pts: Array = []
	var length := 0.0
	var prev := world.start_position()
	for xz in ROUTE_XZ:
		var y := maxf(world.height(xz.x, xz.y), FlyWorld.WATER_LEVEL) + ROUTE_AGL
		var p := Vector3(xz.x, y, xz.y)
		pts.append(p)
		length += prev.distance_to(p)
		prev = p
	# the last point is "home": come back down near the pad
	pts[pts.size() - 1] = world.start_position() + Vector3(0, 6.0, 0)
	return {"points": pts, "radius": 12.0, "length": length}
