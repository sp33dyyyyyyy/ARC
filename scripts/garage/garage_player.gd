class_name GaragePlayer
extends CharacterBody3D
## First-person walker for the garage: WASD / left stick, mouse / right stick look,
## sprint, crouch, a reach ray for interactables, and carrying Pickables.

signal hover_changed(target: Node)

const WALK := 2.8
const SPRINT := 5.0
const CROUCH := 1.4
const EYE := 1.62
const EYE_CROUCH := 1.0
const REACH := 2.6

var cam: Camera3D
var ray: RayCast3D
var yaw := 0.0
var pitch := 0.0
var crouched := false
var enabled := true          # false while a menu / the computer is open
var hovered: Node = null
var held: Pickable = null
var _hold_rot := Vector3.ZERO
var _bob := 0.0
var _sprint_latch := false
var _step_t := 0.0
var _eye := EYE
var _shape: CapsuleShape3D


func _ready() -> void:
	var cs := CollisionShape3D.new()
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.28
	_shape.height = 1.75
	cs.shape = _shape
	cs.position.y = 0.875
	add_child(cs)
	collision_layer = 2
	collision_mask = 1
	cam = Camera3D.new()
	cam.fov = float(Settings.opt.get("garage_fov", 72.0))
	cam.near = 0.03
	cam.far = 400.0
	cam.position.y = EYE
	add_child(cam)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 4
	ray.collide_with_areas = false
	ray.add_exception(self)
	cam.add_child(ray)
	cam.current = true


func look_dir() -> Vector3:
	return -cam.global_transform.basis.z


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := 0.0022 * Settings.look_sens
		if held != null and Input.is_action_pressed("rotate_item"):
			_hold_rot.y += event.relative.x * s * 1.6
			_hold_rot.x += event.relative.y * s * 1.6
			return
		yaw -= event.relative.x * s
		pitch -= event.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-85), deg_to_rad(85))
	elif event.is_action_pressed("crouch"):
		if Settings.opt.get("crouch_toggle", true):
			crouched = not crouched
		else:
			crouched = true
	elif event.is_action_released("crouch") and not Settings.opt.get("crouch_toggle", true):
		crouched = false
	elif event.is_action_pressed("sprint") and Settings.opt.get("sprint_toggle", false):
		_sprint_latch = not _sprint_latch


func _physics_process(dt: float) -> void:
	var g := 9.81
	if not is_on_floor():
		velocity.y -= g * dt
	if enabled:
		# stick look
		var lx := Input.get_axis("look_left", "look_right")
		var ly := Input.get_axis("look_up", "look_down")
		var stick := Vector2(lx, ly)
		if stick.length() > 0.12:
			stick = stick * pow(stick.length(), 0.6)
			var rs := 2.6 * Settings.look_sens * dt
			if held != null and Input.is_action_pressed("rotate_item"):
				_hold_rot.y += stick.x * rs * 1.4
				_hold_rot.x += stick.y * rs * 1.4
			else:
				yaw -= stick.x * rs
				pitch -= stick.y * rs * (-1.0 if Settings.invert_y else 1.0)
				pitch = clampf(pitch, deg_to_rad(-85), deg_to_rad(85))
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var sprinting := _sprint_latch if Settings.opt.get("sprint_toggle", false) else Input.is_action_pressed("sprint")
		var spd := CROUCH if crouched else (SPRINT if sprinting else WALK)
		var dir := Basis(Vector3.UP, yaw) * Vector3(mv.x, 0, mv.y)
		var want := dir * spd
		velocity.x = move_toward(velocity.x, want.x, 18.0 * dt)
		velocity.z = move_toward(velocity.z, want.z, 18.0 * dt)
		if mv.length() > 0.1 and is_on_floor():
			_bob += dt * spd * 2.4
			_step_t -= dt * spd
			if _step_t <= 0.0:
				_step_t = 1.45
				Audio.play("step", randf_range(0.85, 1.15))
		else:
			_bob = lerpf(_bob, round(_bob / PI) * PI, minf(dt * 6.0, 1.0))
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	rotation.y = yaw
	_eye = lerpf(_eye, EYE_CROUCH if crouched else EYE, minf(dt * 10.0, 1.0))
	cam.position.y = _eye + (sin(_bob) * 0.025 if Settings.opt.get("head_bob", true) else 0.0)
	cam.rotation.x = pitch
	_update_hover()
	_update_held(dt)


func _update_hover() -> void:
	var h: Node = null
	if enabled and ray.is_colliding():
		h = ray.get_collider()
		if h == held:
			h = null
	if h != hovered:
		if hovered != null and is_instance_valid(hovered):
			Interactable.set_glow(_glow_of(hovered), false)
		hovered = h
		if hovered != null:
			Interactable.set_glow(_glow_of(hovered), true)
		hover_changed.emit(hovered)


func _glow_of(n: Node) -> Node:
	if n is Interactable:
		return (n as Interactable).glow_root()
	return n


func hover_point() -> Vector3:
	return ray.get_collision_point() if ray.is_colliding() else cam.global_position + look_dir() * REACH


# --- carrying -----------------------------------------------------------------------------------
func hold(p: Pickable) -> void:
	if held != null:
		drop()
	held = p
	p.set_held(true)
	Interactable.set_glow(p, false)
	_hold_rot = Vector3(0, p.global_rotation.y - yaw, 0)
	Audio.play("pickup")
	Pad.rumble(0.25, 0.0, 0.08)


func release() -> Pickable:
	var p := held
	held = null
	if p:
		p.set_held(false)
	return p


## Drops the held item in front of the player with a little toss.
func drop() -> void:
	var p := release()
	if p == null:
		return
	p.linear_velocity = look_dir() * 1.2 + velocity * 0.5
	Audio.play("drop")


## Places the held item on the surface under the crosshair (upright, keeping its yaw).
func place() -> bool:
	if held == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + look_dir() * (REACH + 0.6), 1 | 4)
	q.exclude = [get_rid(), held.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		return false
	var p := release()
	p.global_transform = Transform3D(Basis(Vector3.UP, yaw + _hold_rot.y), hit["position"] + Vector3(0, p.half_height + 0.01, 0))
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	Audio.play("drop", 1.2)
	Pad.rumble(0.15, 0.0, 0.06)
	return true


func _update_held(dt: float) -> void:
	if held == null or not is_instance_valid(held):
		held = null
		return
	var target := cam.global_position + look_dir() * 0.75 + cam.global_transform.basis.y * -0.22
	var b := Basis(Vector3.UP, yaw + _hold_rot.y) * Basis(Vector3.RIGHT, _hold_rot.x)
	var t := minf(dt * 14.0, 1.0)
	var cur := held.global_transform
	var q0 := cur.basis.orthonormalized().get_rotation_quaternion()
	var q1 := b.orthonormalized().get_rotation_quaternion()
	held.global_transform = Transform3D(Basis(q0.slerp(q1, t)), cur.origin.lerp(target, t))
