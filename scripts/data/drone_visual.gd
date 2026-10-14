class_name DroneVisual
extends RefCounted
## Assembles a complete drone model from a placement dictionary.


static func default_placement() -> Dictionary:
	var d := {"frame": "frame_5", "esc": "esc_4in1", "fc": "fc_f4", "vtx": "vtx_25", "cam": "cam_fpv", "battery": "bat_1500"}
	for i in 4:
		var dir: String = Parts.MOTOR_SPIN[i].to_lower()
		d["motor_%d" % (i + 1)] = "motor_2306_%s" % dir
		d["prop_%d" % (i + 1)] = "prop_5143_%s" % dir
	return d


## Returns a Node3D whose children are named after their slots and sit at the slot positions.
static func assemble(placed: Dictionary, broken: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	if not placed.has("frame"):
		return root
	var frame_id: String = placed["frame"]
	for s in Parts.slots_for(frame_id):
		if not placed.has(s["name"]):
			continue
		var node := MeshFactory.make_part(placed[s["name"]], frame_id, broken.get(s["name"], false))
		node.name = s["name"]
		node.position = s["pos"]
		for l in node.find_children("*", "Label3D", true, false):
			l.visible = false
		root.add_child(node)
	return root
