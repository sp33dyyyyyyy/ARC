class_name GyroView
extends SubViewportContainer
## Live 3D wireframe of the quad used by the Gyro tab. Orientation is driven by
## the pilot dragging the board (plus a little simulated sensor wobble).

var yaw := 20.0
var pitch := 12.0
var roll := -8.0
var rates := Vector3.ZERO     # deg/s (roll, pitch, yaw), smoothed
var _model: Node3D
var _sv: SubViewport
var _prev := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.06)
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.position = Vector3(0, 15, 29)
	_sv.add_child(cam)
	cam.look_at(Vector3(0, 0, 0))
	rebuild()


func rebuild() -> void:
	if _model:
		_model.queue_free()
	_model = Node3D.new()
	_sv.add_child(_model)
	var fid: String = Game.placed.get("frame", "frame_5")
	var o: float = Parts.part(fid)["arm"]
	var sc := 9.0 / maxf(o, 1.0)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.62, 0.1)
	orange.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.9, 1.0)
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 4:
		var sg: Vector2 = Parts.MOTOR_SIGNS[i]
		var p := Vector3(sg.x, 0, sg.y) * o * sc
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(p)
		var segs := 20
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			im.surface_add_vertex(p + Vector3(cos(a0), 0, sin(a0)) * 3.2)
			im.surface_add_vertex(p + Vector3(cos(a1), 0, sin(a1)) * 3.2)
	var h := 2.4
	var corners := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	for k in 4:
		im.surface_add_vertex(corners[k])
		im.surface_add_vertex(corners[(k + 1) % 4])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = orange
	_model.add_child(mi)

	var im2 := ImmediateMesh.new()
	im2.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := Vector3(0, 0, -1)
	im2.surface_add_vertex(Vector3(0, 0, 0))
	im2.surface_add_vertex(n * 8.5)
	im2.surface_add_vertex(n * 8.5)
	im2.surface_add_vertex(n * 6.6 + Vector3(1.4, 0, 0))
	im2.surface_add_vertex(n * 8.5)
	im2.surface_add_vertex(n * 6.6 + Vector3(-1.4, 0, 0))
	im2.surface_end()
	var mi2 := MeshInstance3D.new()
	mi2.mesh = im2
	mi2.material_override = white
	_model.add_child(mi2)
	_apply()


func _apply() -> void:
	if _model:
		_model.basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(-yaw), deg_to_rad(-roll)))


func drag(dx: float, dy: float, rolling: bool) -> void:
	if rolling:
		roll = clampf(roll + dx * 0.4, -180.0, 180.0)
	else:
		yaw = fposmod(yaw + dx * 0.4, 360.0)
		pitch = clampf(pitch - dy * 0.4, -90.0, 90.0)


func calibrate() -> void:
	yaw = 0.0
	pitch = 0.0
	roll = 0.0


func heading() -> float:
	return fposmod(yaw, 360.0)


func _process(dt: float) -> void:
	_t += dt
	# simulated sensor wobble so the readouts are alive
	var wob_r := sin(_t * 1.7) * 0.25 + sin(_t * 5.3) * 0.08
	var wob_p := cos(_t * 1.3) * 0.25 + sin(_t * 4.1) * 0.08
	var cur := Vector3(roll + wob_r, pitch + wob_p, yaw)
	if dt > 0.0:
		var inst := (cur - _prev) / dt
		inst.z = wrapf(inst.z, -180.0 / dt, 180.0 / dt)
		rates = rates.lerp(inst, 0.2)
	_prev = cur
	if _model:
		_model.basis = Basis.from_euler(Vector3(deg_to_rad(pitch + wob_p), deg_to_rad(-yaw), deg_to_rad(-roll - wob_r)))
