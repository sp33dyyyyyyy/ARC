extends Node
## Shared game state: the drone on the workbench (its parts, condition, loose screws,
## wiring and flight-controller configuration), the flight being launched and screen navigation.

signal screen_requested(screen: String, args: Dictionary)

var placed: Dictionary = {}          # slot name -> part id
var broken: Dictionary = {}          # prop slot name -> true
var cond: Dictionary = {}            # slot name -> condition 0..1 (missing = new)
var loose: Dictionary = {}           # slot name -> screws still to tighten
var wires: Array = []                # connection ids (see Parts.WIRES)
var cfg: Dictionary = {}             # flight-controller configuration
var paint: Color = Color(0, 0, 0, 0)
var bench_name: String = ""
var bench_charge: float = 1.0
var mission: String = "free_flight"
var last_result: Dictionary = {}
var workshop_stage: String = "build"
var screen: String = "menu"
## What the next FlyStage flies: {"source": "bench"|"roster", "drone_id": String, "mission": String}
var flight: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg = default_cfg()
	load_drone()


func default_cfg() -> Dictionary:
	return FlightMath.default_cfg()


func goto(screen_name: String, args: Dictionary = {}) -> void:
	screen_requested.emit(screen_name, args)


# --- build helpers ----------------------------------------------------------
func reset_build() -> void:
	placed.clear()
	broken.clear()
	cond.clear()
	loose.clear()
	wires.clear()
	cfg = default_cfg()
	paint = Color(0, 0, 0, 0)
	bench_name = ""
	bench_charge = 1.0
	save_drone()


func stats() -> Dictionary:
	return Parts.compute_build(placed, broken, cond)


func wiring_complete() -> bool:
	return Parts.missing_wires(wires).is_empty()


func loose_text() -> String:
	var names: Array = []
	for s in loose:
		if int(loose[s]) > 0:
			names.append(s.replace("_", " "))
	return ", ".join(names)


func ready_to_fly() -> Dictionary:
	## {"ok": bool, "reason": String}
	var s := stats()
	if not s["complete"]:
		return {"ok": false, "reason": "Build is incomplete: %s" % s["missing_text"]}
	if s["broken_props"] > 0:
		return {"ok": false, "reason": "%d prop(s) are broken - replace them in BUILD." % s["broken_props"]}
	if not loose.is_empty():
		return {"ok": false, "reason": "Loose screws on: %s - tighten them in BUILD." % loose_text()}
	if not wiring_complete():
		return {"ok": false, "reason": "Wiring is incomplete: %s" % ", ".join(Parts.missing_wires(wires))}
	return {"ok": true, "reason": ""}


## The drone data a flight uses, as a roster-style dictionary.
func flight_drone() -> Dictionary:
	if flight.get("source", "bench") == "roster":
		return Career.get_drone(flight.get("drone_id", ""))
	return {"id": "", "name": bench_name if bench_name != "" else "Bench drone", "placed": placed, "broken": broken, "cond": cond, "wires": wires,
		"cfg": cfg, "paint": [paint.r, paint.g, paint.b, paint.a], "charge": bench_charge, "certified": true}


# --- persistence ------------------------------------------------------------
func save_drone() -> void:
	SaveData.data["drone"] = {
		"placed": placed.duplicate(),
		"broken": broken.duplicate(),
		"cond": cond.duplicate(),
		"loose": loose.duplicate(),
		"wires": wires.duplicate(),
		"cfg": cfg.duplicate(true),
		"paint": [paint.r, paint.g, paint.b, paint.a],
		"name": bench_name,
		"charge": bench_charge,
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
	if d.get("cond") is Dictionary:
		for slot in d["cond"]:
			if placed.has(slot) and (d["cond"][slot] is float or d["cond"][slot] is int):
				cond[str(slot)] = clampf(float(d["cond"][slot]), 0.0, 1.0)
	if d.get("loose") is Dictionary:
		for slot in d["loose"]:
			if placed.has(slot) and (d["loose"][slot] is float or d["loose"][slot] is int) and int(d["loose"][slot]) > 0:
				loose[str(slot)] = int(d["loose"][slot])
	if d.get("wires") is Array:
		for w in d["wires"]:
			if w is String and Parts.WIRES.has(w):
				wires.append(w)
	if d.get("cfg") is Dictionary:
		_merge_cfg(cfg, d["cfg"])
	if d.get("paint") is Array and d["paint"].size() >= 4:
		paint = Color(d["paint"][0], d["paint"][1], d["paint"][2], d["paint"][3])
	if d.get("name") is String:
		bench_name = d["name"]
	if d.get("charge") is float or d.get("charge") is int:
		bench_charge = clampf(float(d["charge"]), 0.0, 1.0)
	# A saved build is only trusted if it is consistent with the current frame layout.
	if not Parts.placement_is_valid(placed):
		placed.clear()
		broken.clear()
		cond.clear()
		loose.clear()
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
