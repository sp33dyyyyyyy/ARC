extends Node
## Progress persistence: best times, unlocked parts and the current drone.
## Stored as JSON in user://save.json. Missing/corrupt files fall back to defaults.

signal unlocked(part_ids: Array)

const SAVE_PATH := "user://save.json"
const DEFAULT_UNLOCKED := [
	"frame_5", "motor_2306_cw", "motor_2306_ccw", "prop_5143_cw", "prop_5143_ccw",
	"esc_4in1", "fc_f4", "vtx_25", "cam_fpv", "bat_1500", "bat_1100",
]

var data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_data()


func _defaults() -> Dictionary:
	return {
		"version": 1,
		"best_times": {},     # mission id -> seconds
		"best_mah": {},       # mission id -> mAh used on the best run
		"top_speed_kmh": 0.0,
		"unlocked": DEFAULT_UNLOCKED.duplicate(),
		"drone": {},          # placed / broken / wires / cfg (see Game)
	}


func load_data() -> void:
	data = _defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("save.json is corrupt - using defaults")
		return
	var d: Dictionary = parsed
	if d.get("best_times") is Dictionary:
		for k in d["best_times"]:
			if d["best_times"][k] is float or d["best_times"][k] is int:
				data["best_times"][str(k)] = float(d["best_times"][k])
	if d.get("best_mah") is Dictionary:
		for k in d["best_mah"]:
			if d["best_mah"][k] is float or d["best_mah"][k] is int:
				data["best_mah"][str(k)] = float(d["best_mah"][k])
	if d.get("top_speed_kmh") is float or d.get("top_speed_kmh") is int:
		data["top_speed_kmh"] = float(d["top_speed_kmh"])
	if d.get("unlocked") is Array:
		for id in d["unlocked"]:
			if id is String and not data["unlocked"].has(id):
				data["unlocked"].append(id)
	if d.get("drone") is Dictionary:
		data["drone"] = d["drone"]


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save.json")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func is_unlocked(part_id: String) -> bool:
	return data["unlocked"].has(part_id)


func unlock(ids: Array) -> Array:
	var fresh: Array = []
	for id in ids:
		if not data["unlocked"].has(id):
			data["unlocked"].append(id)
			fresh.append(id)
	if not fresh.is_empty():
		save()
		unlocked.emit(fresh)
	return fresh


func unlock_all() -> void:
	unlock(Parts.db().keys())


func best_time(mission: String) -> float:
	return float(data["best_times"].get(mission, 0.0))


## Records a finished run. Returns {"new_best": bool, "unlocked": Array}.
func record_run(mission: String, time_s: float, mah_used: float) -> Dictionary:
	var prev := best_time(mission)
	var new_best := prev <= 0.0 or time_s < prev
	if new_best:
		data["best_times"][mission] = time_s
		data["best_mah"][mission] = mah_used
	var fresh := unlock(Parts.UNLOCKS.get(mission, []))
	save()
	return {"new_best": new_best, "unlocked": fresh}


func note_speed(kmh: float) -> void:
	if kmh > float(data["top_speed_kmh"]):
		data["top_speed_kmh"] = kmh
