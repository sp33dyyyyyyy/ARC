class_name Pickable
extends RigidBody3D
## A physical item the player can pick up (F), carry, rotate (hold R) and place or drop:
## parcels, battery packs, drones, tools, tool cases. `kind` + `data` say what it is.

var kind := ""
var data: Dictionary = {}
var title := ""
var describe_fn: Callable        # () -> String  shown by the secondary action (inspect)
var use_prompt_fn: Callable      # () -> String  "[E]" text while hovered or held ("" = none)
var use_fn: Callable             # (player) -> void
var half_height := 0.1
var held := false
var visual: Node3D


static func make(parent: Node3D, p_kind: String, p_title: String, size: Vector3, model: Node3D, mass_kg: float = 1.0) -> Pickable:
	var p := Pickable.new()
	p.kind = p_kind
	p.title = p_title
	p.mass = mass_kg
	p.half_height = size.y * 0.5
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	p.add_child(cs)
	if model:
		p.visual = model
		p.add_child(model)
	p.continuous_cd = true
	p.can_sleep = true
	p.collision_layer = 1 | 4
	p.collision_mask = 1 | 4
	parent.add_child(p)
	return p


func use_prompt() -> String:
	return use_prompt_fn.call() if use_prompt_fn.is_valid() else ""


func describe() -> String:
	return describe_fn.call() if describe_fn.is_valid() else title


func use(player: Node) -> void:
	if use_fn.is_valid():
		use_fn.call(player)


func set_held(on: bool) -> void:
	held = on
	freeze = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 0 if on else (1 | 4)
	collision_mask = 0 if on else (1 | 4)
	if not on:
		sleeping = false
