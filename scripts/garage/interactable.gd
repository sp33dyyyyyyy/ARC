class_name Interactable
extends AnimatableBody3D
## Reusable interaction target for the walkable garage. Any object the player can use
## is one of these (or a Pickable). Behaviour is supplied as callables so equipment
## doesn't need its own script:
##   prompt_fn() -> String          text after "[E]" ("" = not usable right now)
##   use_fn(player)                 primary action (E / Cross)
##   alt_prompt_fn() -> String      text after "[RMB]" ("" = none)
##   alt_fn(player)                 secondary action (RMB / L2)
##   accepts_fn(held) -> String     prompt when the player holds `held` ("" = doesn't accept it)
##   give_fn(player, held)          called when the held item is used on this object
##   pick_fn(player) -> bool        F on this object picks something up (e.g. a drone off the rack)
##   pick_prompt_fn() -> String

var title := ""
var prompt_fn: Callable
var use_fn: Callable
var alt_prompt_fn: Callable
var alt_fn: Callable
var accepts_fn: Callable
var give_fn: Callable
var pick_fn: Callable
var pick_prompt_fn: Callable
## Node whose meshes glow when hovered (defaults to self).
var highlight_root: Node3D


static func make(parent: Node3D, size: Vector3, pos: Vector3, p_title: String, p_prompt: Variant, p_use: Callable = Callable()) -> Interactable:
	var it := Interactable.new()
	it.sync_to_physics = false
	it.title = p_title
	if p_prompt is Callable:
		it.prompt_fn = p_prompt
	else:
		var txt := str(p_prompt)
		it.prompt_fn = func() -> String: return txt
	it.use_fn = p_use
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	it.add_child(cs)
	it.position = pos
	parent.add_child(it)
	return it


func prompt() -> String:
	return prompt_fn.call() if prompt_fn.is_valid() else ""


func alt_prompt() -> String:
	return alt_prompt_fn.call() if alt_prompt_fn.is_valid() else ""


func pick_prompt() -> String:
	return pick_prompt_fn.call() if pick_prompt_fn.is_valid() else ""


func accepts(held: Node) -> String:
	return accepts_fn.call(held) if accepts_fn.is_valid() else ""


func use(player: Node) -> void:
	if use_fn.is_valid():
		use_fn.call(player)


func alt(player: Node) -> void:
	if alt_fn.is_valid():
		alt_fn.call(player)


func give(player: Node, held: Node) -> void:
	if give_fn.is_valid():
		give_fn.call(player, held)


func pick(player: Node) -> bool:
	return pick_fn.call(player) if pick_fn.is_valid() else false


func glow_root() -> Node3D:
	return highlight_root if highlight_root != null and is_instance_valid(highlight_root) else self


# --- shared hover glow -----------------------------------------------------------------
static var _glow_mat: ShaderMaterial


static func glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.25, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * 5.0);
	ALBEDO = tint.rgb * (rim * 0.9 + 0.1) * pulse;
}
"""
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = sh
	return _glow_mat


static func set_glow(root: Node, on: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	var m: Material = glow_material() if on else null
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_overlay = m
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not mi.has_meta("no_glow"):
			(mi as MeshInstance3D).material_overlay = m
