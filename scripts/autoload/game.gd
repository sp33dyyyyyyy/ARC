extends Node
## Shared game state: the drone being built, its wiring and flight-controller
## configuration, the selected mission, and screen navigation.

signal screen_requested(screen: String, args: Dictionary)

var placed: Dictionary = {}          # slot name -> part id
var broken: Dictionary = {}          # prop slot name -> true
var wires: Array = []                # connection ids (see Parts.WIRES)
var cfg: Dictionary = {}             # flight-controller configuration
var mission: String = "free_flight"
var last_result: Dictionary = {}
var workshop_stage: String = "build"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg = default_cfg()
	load_drone()


func default_cfg() -> Dictionary:
	return FlightMath.default_cfg()


func goto(screen: String, args: Dictionary = {}) -> void:
	screen_requested.emit(screen, args)


# --- build helpers ----------------------------------------------------------
func reset_build() -> void:
	placed.clear()
	broken.clear()
	wires.clear()
	save_drone()


func stats() -> Dictionary:
	return Parts.compute_build(placed, broken)


func wiring_complete() -> bool:
	return Parts.missing_wires(wires).is_empty()


func ready_to_fly() -> Dictionary:
	## {"ok": bool, "reason": String}
	var s := stats()
	if not s["complete"]:
		return {"ok": false, "reason": "Build is incomplete: %s" % s["missing_text"]}
	if s["broken_props"] > 0:
		return {"ok": false, "reason": "%d prop(s) are broken - replace them in BUILD." % s["broken_props"]}
	if not wiring_complete():
		return {"ok": false, "reason": "Wiring is incomplete: %s" % ", ".join(Parts.missing_wires(wires))}
	return {"ok": true, "reason": ""}


# --- persistence ------------------------------------------------------------
func save_drone() -> void:
	SaveData.data["drone"] = {
		"placed": placed.duplicate(),
		"broken": broken.duplicate(),
		"wires": wires.duplicate(),
		"cfg": cfg.duplicate(true),
	}
	SaveData.save()


func load_drone() -> void:
	var d = SaveData.data.get("drone", {})
	if not (d is Dictionary) or d.is_empty():
		return
	var db := Parts.db()
	if d.get("placed") is Dictionary:
		for slot in d["placed"]:
			var pid = d["placed"][slot]
			if pid is String and db.has(pid):
				placed[str(slot)] = pid
	if d.get("broken") is Dictionary:
		for slot in d["broken"]:
			if placed.has(slot):
				broken[str(slot)] = true
	if d.get("wires") is Array:
		for w in d["wires"]:
			if w is String and Parts.WIRES.has(w):
				wires.append(w)
	if d.get("cfg") is Dictionary:
		_merge_cfg(cfg, d["cfg"])
	# A saved build is only trusted if it is consistent with the current frame layout.
	if not Parts.placement_is_valid(placed):
		placed.clear()
		broken.clear()
		wires.clear()


func _merge_cfg(dst: Dictionary, src: Dictionary) -> void:
	for k in dst:
		if not src.has(k):
			continue
		if dst[k] is Dictionary and src[k] is Dictionary:
			_merge_cfg(dst[k], src[k])
		elif (dst[k] is float or dst[k] is int) and (src[k] is float or src[k] is int):
			dst[k] = type_convert(src[k], typeof(dst[k]))
		elif typeof(dst[k]) == typeof(src[k]):
			dst[k] = src[k]
