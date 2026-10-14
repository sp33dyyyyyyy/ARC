class_name Parts
extends RefCounted
## Static catalogue: parts, slot layouts, solder pads, wire harness and the
## derived airframe statistics used by the flight model.
##
## Units: the workshop uses 1 unit = 1 cm. Forward is -Z, up is +Y, right is +X.

const CATEGORIES := ["frame", "motor", "prop", "esc", "fc", "vtx", "cam", "battery"]
const CAT_NAMES := {
	"frame": "Frame", "motor": "Motors", "prop": "Props", "esc": "ESC",
	"fc": "Flight ctrl", "vtx": "VTX", "cam": "Camera", "battery": "Battery",
}
const CAT_QUOTA := {"frame": 1, "motor": 4, "prop": 4, "esc": 1, "fc": 1, "vtx": 1, "cam": 1, "battery": 1}

## Parts unlocked by finishing a mission (saved in save.json).
const UNLOCKS := {
	"gate_race": ["frame_3", "motor_2207_cw", "motor_2207_ccw", "prop_5040_cw", "prop_5040_ccw", "bat_2200"],
	"battery_challenge": ["frame_7", "motor_2806_cw", "motor_2806_ccw"],
}
const MISSION_NAMES := {"free_flight": "Free Flight", "gate_race": "Gate Race", "battery_challenge": "Battery Challenge"}

## Betaflight motor order, props-in: M1 rear-right CCW, M2 front-right CW, M3 rear-left CW, M4 front-left CCW.
const MOTOR_SPIN := ["CCW", "CW", "CW", "CCW"]
const MOTOR_SIGNS := [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]  # (x, z) sign per motor

# Stack heights (cm, frame-local). Parts' origins sit at their bottom face.
const Y_MOTOR := 0.4
const Y_PROP := 2.9
const Y_ESC := 1.0
const Y_FC := 2.5
const Y_VTX := 4.0
const Y_BATTERY := 5.75

# --- wire harness ------------------------------------------------------------
## id -> connection. a/b are pad ids "<part>.<pad>"; the route hint shapes the cable.
const WIRES := {
	"m1": {"a": "fc.M1", "b": "esc.S1", "color": Color(1.0, 0.85, 0.1), "label": "Motor 1 signal  (FC M1 → ESC1)", "required": true, "dir": Vector3(0, 0, -1), "bulge": 1.6},
	"m2": {"a": "fc.M2", "b": "esc.S2", "color": Color(0.2, 0.85, 0.3), "label": "Motor 2 signal  (FC M2 → ESC2)", "required": true, "dir": Vector3(0, 0, -1), "bulge": 2.1},
	"m3": {"a": "fc.M3", "b": "esc.S3", "color": Color(0.25, 0.5, 1.0), "label": "Motor 3 signal  (FC M3 → ESC3)", "required": true, "dir": Vector3(0, 0, -1), "bulge": 2.6},
	"m4": {"a": "fc.M4", "b": "esc.S4", "color": Color(0.95, 0.95, 0.95), "label": "Motor 4 signal  (FC M4 → ESC4)", "required": true, "dir": Vector3(0, 0, -1), "bulge": 3.1},
	"bat_pos": {"a": "bat.RED", "b": "esc.BATP", "color": Color(0.95, 0.12, 0.1), "label": "Battery + (red) → ESC BAT+", "required": true, "dir": Vector3(0, 0, 1), "bulge": 4.0},
	"bat_neg": {"a": "bat.BLACK", "b": "esc.BATN", "color": Color(0.08, 0.08, 0.08), "label": "Battery − (black) → ESC BAT−", "required": true, "dir": Vector3(0, 0, 1), "bulge": 5.0},
	"vtx": {"a": "vtx.UART", "b": "fc.UART", "color": Color(0.25, 0.5, 1.0), "label": "VTX → FC UART pad", "required": true, "dir": Vector3(0, 0, 1), "bulge": 1.8},
	"cam": {"a": "cam.OUT", "b": "fc.CAM", "color": Color(1.0, 0.85, 0.1), "label": "Camera → FC CAM pad", "required": true, "dir": Vector3(-1, 0, 0), "bulge": 3.0},
	"cur": {"a": "esc.CUR", "b": "fc.CURR", "color": Color(0.95, 0.95, 0.95), "label": "ESC CUR → FC CURR  (optional: total amps on HUD)", "required": false, "dir": Vector3(1, 0, 0), "bulge": 2.2},
}

## Pad id -> {part category, local position, label, kind}. kind: sig / pwr+ / pwr- / cap / cur
const PADS := {
	"esc.S1": {"cat": "esc", "pos": Vector3(-1.05, 0.3, -1.55), "label": "S1", "kind": "sig"},
	"esc.S2": {"cat": "esc", "pos": Vector3(-0.35, 0.3, -1.55), "label": "S2", "kind": "sig"},
	"esc.S3": {"cat": "esc", "pos": Vector3(0.35, 0.3, -1.55), "label": "S3", "kind": "sig"},
	"esc.S4": {"cat": "esc", "pos": Vector3(1.05, 0.3, -1.55), "label": "S4", "kind": "sig"},
	"esc.CUR": {"cat": "esc", "pos": Vector3(1.6, 0.3, -0.9), "label": "CUR", "kind": "cur"},
	"esc.BATP": {"cat": "esc", "pos": Vector3(-0.9, 0.3, 1.6), "label": "BAT+", "kind": "pwr+"},
	"esc.BATN": {"cat": "esc", "pos": Vector3(0.0, 0.3, 1.6), "label": "BAT−", "kind": "pwr-"},
	"esc.CBAT": {"cat": "esc", "pos": Vector3(0.9, 0.3, 1.6), "label": "C BAT", "kind": "cap"},
	"esc.M1": {"cat": "esc", "pos": Vector3(1.6, 0.3, 1.2), "label": "M1", "kind": "motor"},
	"esc.M2": {"cat": "esc", "pos": Vector3(1.6, 0.3, 0.2), "label": "M2", "kind": "motor"},
	"esc.M3": {"cat": "esc", "pos": Vector3(-1.6, 0.3, 1.2), "label": "M3", "kind": "motor"},
	"esc.M4": {"cat": "esc", "pos": Vector3(-1.6, 0.3, 0.2), "label": "M4", "kind": "motor"},
	"fc.M1": {"cat": "fc", "pos": Vector3(-1.05, 0.3, -1.55), "label": "M1", "kind": "sig"},
	"fc.M2": {"cat": "fc", "pos": Vector3(-0.35, 0.3, -1.55), "label": "M2", "kind": "sig"},
	"fc.M3": {"cat": "fc", "pos": Vector3(0.35, 0.3, -1.55), "label": "M3", "kind": "sig"},
	"fc.M4": {"cat": "fc", "pos": Vector3(1.05, 0.3, -1.55), "label": "M4", "kind": "sig"},
	"fc.UART": {"cat": "fc", "pos": Vector3(-0.9, 0.3, 1.55), "label": "UART", "kind": "sig"},
	"fc.CAM": {"cat": "fc", "pos": Vector3(-1.55, 0.3, -0.4), "label": "CAM", "kind": "sig"},
	"fc.CURR": {"cat": "fc", "pos": Vector3(1.55, 0.3, -0.9), "label": "CURR", "kind": "cur"},
	"vtx.UART": {"cat": "vtx", "pos": Vector3(-0.6, 0.3, 1.15), "label": "UART", "kind": "sig"},
	"cam.OUT": {"cat": "cam", "pos": Vector3(0.0, 0.7, 0.95), "label": "OUT", "kind": "sig"},
	"bat.RED": {"cat": "battery", "pos": Vector3(-0.6, 1.4, 5.0), "label": "RED +", "kind": "pwr+"},
	"bat.BLACK": {"cat": "battery", "pos": Vector3(0.6, 1.4, 5.0), "label": "BLACK −", "kind": "pwr-"},
}

## Exploded-view offsets used by the WIRE stage (cm, added to the slot position).
const EXPLODE := {
	"frame": Vector3(0, 0, 0), "motor": Vector3(0, 0, 0), "prop": Vector3(0, 0, 0),
	"esc": Vector3(0, 0, 0), "fc": Vector3(0, 3.6, 0), "vtx": Vector3(0, 7.2, 0),
	"cam": Vector3(0, 0, 0), "battery": Vector3(11.0, 5.0, 3.0),
}

static var _db: Dictionary = {}


static func db() -> Dictionary:
	if _db.is_empty():
		_build_db()
	return _db


static func _add(id: String, d: Dictionary) -> void:
	d["id"] = id
	_db[id] = d


static func _build_db() -> void:
	_add("frame_5", {"cat": "frame", "name": "5\" Carbon X-Frame", "mass": 85.0, "arm": 7.95, "prop_in": 5.0, "drag": 1.0, "duct": 1.0,
		"unlock": "", "desc": "Classic 225 mm freestyle frame. Balanced and quick."})
	_add("frame_3", {"cat": "frame", "name": "3\" Ducted Whoop Frame", "mass": 30.0, "arm": 4.4, "prop_in": 3.0, "drag": 0.55, "duct": 1.8,
		"unlock": "gate_race", "desc": "Tiny ducted frame. Light and agile - duct boosts thrust. Props auto-size to the frame."})
	_add("frame_7", {"cat": "frame", "name": "7\" Long-Range Frame", "mass": 140.0, "arm": 10.4, "prop_in": 7.0, "drag": 1.5, "duct": 1.0,
		"unlock": "battery_challenge", "desc": "Big 300 mm cruiser. Efficient, heavy and slow to turn. Best with 2806 motors."})

	var motors := {
		"2306": {"kv": 2400, "mass": 32.0, "color": Color(0.85, 0.12, 0.12), "size": 1.0, "unlock": "", "desc": "The all-rounder. Punchy and thirsty."},
		"2207": {"kv": 1800, "mass": 31.0, "color": Color(0.15, 0.4, 0.95), "size": 0.95, "unlock": "gate_race", "desc": "Lower KV: gentler thrust, much lighter on the battery."},
		"2806": {"kv": 1300, "mass": 52.0, "color": Color(0.12, 0.72, 0.4), "size": 1.2, "unlock": "battery_challenge", "desc": "Big low-KV stator, made for 7\" props. Efficient."},
	}
	for t in motors:
		for dir in ["cw", "ccw"]:
			var m: Dictionary = motors[t].duplicate()
			m["cat"] = "motor"
			m["type"] = t
			m["spin"] = dir.to_upper()
			m["name"] = "%s %dKV Motor (%s)" % [t, m["kv"], dir.to_upper()]
			m["unlock"] = ("" if m["unlock"] == "" else m["unlock"])
			_add("motor_%s_%s" % [t, dir], m)

	var props := {
		"5143": {"name": "5143 Tri-blade", "blades": 3, "diam": 5.1, "thrust": 1.0, "cur": 1.0, "tau": 0.034, "mass": 4.8, "color": Color(1.0, 0.85, 0.0), "unlock": "",
			"desc": "Tri-blade: lots of grip and thrust. Bright yellow."},
		"5040": {"name": "5040 Bi-blade", "blades": 2, "diam": 5.0, "thrust": 0.86, "cur": 0.95, "tau": 0.026, "mass": 3.6, "color": Color(1.0, 0.45, 0.05), "unlock": "gate_race",
			"desc": "Bi-blade: snappier and more efficient, less thrust. Bright orange."},
	}
	for t in props:
		for dir in ["cw", "ccw"]:
			var p: Dictionary = props[t].duplicate()
			p["cat"] = "prop"
			p["type"] = t
			p["spin"] = dir.to_upper()
			p["name"] = "%s (%s)" % [p["name"], dir.to_upper()]
			_add("prop_%s_%s" % [t, dir], p)

	_add("esc_4in1", {"cat": "esc", "name": "4-in-1 55A ESC", "mass": 14.0, "unlock": "",
		"desc": "Four ESC chips, M1-M4 motor pads, CUR current pin and a C BAT capacitor pad."})
	_add("fc_f4", {"cat": "fc", "name": "F4 Flight Controller", "mass": 8.0, "unlock": "",
		"desc": "Gyro chip, motor pad row, UART and camera pads. Arrow points forward."})
	_add("vtx_25", {"cat": "vtx", "name": "Analog VTX 25-600mW", "mass": 7.0, "unlock": "",
		"desc": "Video transmitter. Antenna points to the rear."})
	_add("cam_fpv", {"cat": "cam", "name": "FPV Camera", "mass": 6.0, "unlock": "",
		"desc": "Micro FPV camera. Lens faces forward."})
	_add("bat_1100", {"cat": "battery", "name": "4S 1100mAh LiPo", "mass": 130.0, "mah": 1100.0, "unlock": "",
		"desc": "Light pack. Short flights."})
	_add("bat_1500", {"cat": "battery", "name": "4S 1500mAh LiPo", "mass": 170.0, "mah": 1500.0, "unlock": "",
		"desc": "The default 4S pack."})
	_add("bat_2200", {"cat": "battery", "name": "4S 2200mAh LiPo", "mass": 255.0, "mah": 2200.0, "unlock": "gate_race",
		"desc": "Big pack. Long flights, but heavy."})


static func part(id: String) -> Dictionary:
	return db().get(id, {})


static func parts_in(cat: String) -> Array:
	var out: Array = []
	for id in db():
		if db()[id]["cat"] == cat:
			out.append(id)
	out.sort()
	return out


static func unlock_text(id: String) -> String:
	var m: String = part(id).get("unlock", "")
	if m == "":
		return ""
	return "Unlock: complete %s" % MISSION_NAMES.get(m, m)


# --- slots ---------------------------------------------------------------------
static func _slot(name: String, cat: String, pos: Vector3, requires: Array, spin: String = "") -> Dictionary:
	return {"name": name, "cat": cat, "pos": pos, "requires": requires, "spin": spin}


## All attach slots for a frame (frame-local coordinates).
static func slots_for(frame_id: String) -> Array:
	var f: Dictionary = part(frame_id)
	var o: float = f.get("arm", 7.95)
	var out: Array = []
	out.append(_slot("frame", "frame", Vector3.ZERO, []))
	for i in 4:
		var sg: Vector2 = MOTOR_SIGNS[i]
		out.append(_slot("motor_%d" % (i + 1), "motor", Vector3(o * sg.x, Y_MOTOR, o * sg.y), ["frame"], MOTOR_SPIN[i]))
	for i in 4:
		var sg: Vector2 = MOTOR_SIGNS[i]
		out.append(_slot("prop_%d" % (i + 1), "prop", Vector3(o * sg.x, Y_PROP, o * sg.y), ["motor_%d" % (i + 1)], MOTOR_SPIN[i]))
	out.append(_slot("esc", "esc", Vector3(0, Y_ESC, 0), ["frame"]))
	out.append(_slot("fc", "fc", Vector3(0, Y_FC, 0), ["esc"]))
	out.append(_slot("vtx", "vtx", Vector3(0, Y_VTX, 0), ["fc"]))
	out.append(_slot("cam", "cam", Vector3(0, 0.6, -o * 0.7), ["frame"]))
	out.append(_slot("battery", "battery", Vector3(0, Y_BATTERY, 0), ["vtx"]))
	return out


static func slot_by_name(frame_id: String, slot_name: String) -> Dictionary:
	for s in slots_for(frame_id):
		if s["name"] == slot_name:
			return s
	return {}


## Whether a part needs rotating to the slot's forward direction.
static func needs_orientation(cat: String) -> bool:
	return cat in ["frame", "esc", "fc", "vtx", "cam", "battery"]


## Footprint radius used for the blue slot marker.
static func marker_radius(cat: String) -> float:
	match cat:
		"frame": return 9.0
		"motor": return 1.9
		"prop": return 3.4
		"battery": return 4.2
		"cam": return 1.6
		_: return 2.6


# --- validation of a placement dictionary ---------------------------------------
## Why `part_id` can't go in `slot` given what's already placed. "" means OK.
static func check_place(placed: Dictionary, slot: Dictionary, part_id: String) -> String:
	var p: Dictionary = part(part_id)
	if p.is_empty() or p["cat"] != slot["cat"]:
		return "That part doesn't go there."
	for r in slot["requires"]:
		if not placed.has(r):
			return "Install the %s first." % _slot_nice(r)
	if slot["cat"] == "frame":
		return ""
	if slot["cat"] in ["motor", "prop"]:
		if p["spin"] != slot["spin"]:
			if slot["cat"] == "prop":
				return "Wrong spin: this slot needs a %s prop (motor arrow is %s)." % [slot["spin"], slot["spin"]]
			return "Wrong spin: this motor position needs a %s motor." % slot["spin"]
		for other in placed:
			if other == slot["name"]:
				continue
			var op: Dictionary = part(placed[other])
			if op.get("cat", "") == slot["cat"] and op.get("type", "") != p["type"]:
				return "All four %ss must be the same model." % ("motor" if slot["cat"] == "motor" else "prop")
	return ""


static func _slot_nice(slot_name: String) -> String:
	if slot_name.begins_with("motor_"):
		return "motor"
	return {"frame": "frame", "esc": "ESC", "fc": "flight controller", "vtx": "VTX"}.get(slot_name, slot_name)


static func placement_is_valid(placed: Dictionary) -> bool:
	if placed.is_empty():
		return true
	if not placed.has("frame"):
		return false
	var slots := slots_for(placed["frame"])
	var names := {}
	for s in slots:
		names[s["name"]] = s
	var seen := {}
	for slot_name in placed:
		if not names.has(slot_name):
			return false
		var s: Dictionary = names[slot_name]
		var tmp := placed.duplicate()
		tmp.erase(slot_name)
		if check_place(tmp, s, placed[slot_name]) != "":
			return false
		seen[slot_name] = true
	return true


## Slots currently installed that depend (directly or indirectly) on `slot_name`.
static func dependents(placed: Dictionary, slot_name: String) -> Array:
	var out: Array = []
	if not placed.has("frame"):
		return out
	var changed := true
	var gone := {slot_name: true}
	var slots := slots_for(placed["frame"])
	while changed:
		changed = false
		for s in slots:
			if placed.has(s["name"]) and not gone.has(s["name"]):
				for r in s["requires"]:
					if gone.has(r):
						gone[s["name"]] = true
						out.append(s["name"])
						changed = true
						break
	return out


static func missing_wires(wires: Array) -> Array:
	var out: Array = []
	for id in WIRES:
		if WIRES[id]["required"] and not wires.has(id):
			out.append(WIRES[id]["label"])
	return out


## Returns {ok, reason, wire} for connecting pad a to pad b.
static func check_connection(a: String, b: String) -> Dictionary:
	if a == b:
		return {"ok": false, "reason": "Pick a second, different pad.", "wire": ""}
	for id in WIRES:
		var w: Dictionary = WIRES[id]
		if (w["a"] == a and w["b"] == b) or (w["a"] == b and w["b"] == a):
			return {"ok": true, "reason": "", "wire": id}
	var ka: String = PADS[a]["kind"]
	var kb: String = PADS[b]["kind"]
	var reason := "That pairing doesn't make sense."
	if "cap" in [ka, kb]:
		reason = "C BAT is the capacitor pad - battery leads go to BAT+ / BAT−."
	elif ka.begins_with("pwr") != kb.begins_with("pwr"):
		reason = "Never connect power to a signal pad!"
	elif ka.begins_with("pwr") and kb.begins_with("pwr"):
		reason = "Wrong polarity or wrong pad: red goes to BAT+, black to BAT−."
	elif "motor" in [ka, kb]:
		reason = "Motor pads are pre-soldered; use the S1-S4 / M1-M4 signal pads."
	elif a.get_slice(".", 0) == b.get_slice(".", 0):
		reason = "Both pads are on the same board."
	elif ka == "sig" and kb == "sig":
		reason = "Wrong pairing: signal wires must match (M1→S1, M2→S2, VTX→UART, camera→CAM)."
	elif "cur" in [ka, kb]:
		reason = "The CUR pin goes to the FC's CURR pad."
	return {"ok": false, "reason": reason, "wire": ""}


# --- derived statistics ----------------------------------------------------------
## Aggregates the build into the numbers the flight model needs.
static func compute_build(placed: Dictionary, broken: Dictionary) -> Dictionary:
	var out := {"complete": false, "missing": [], "missing_text": "", "broken_props": 0}
	if not placed.has("frame"):
		out["missing"] = ["frame"]
		out["missing_text"] = "no frame"
		return out
	var frame: Dictionary = part(placed["frame"])
	var missing: Array = []
	for s in slots_for(placed["frame"]):
		if not placed.has(s["name"]):
			missing.append(s["name"])
	out["missing"] = missing
	if not missing.is_empty():
		var cats := {}
		for m in missing:
			cats[CAT_NAMES.get(slot_cat(placed["frame"], m), m)] = true
		out["missing_text"] = ", ".join(cats.keys())
	out["complete"] = missing.is_empty()
	for k in broken:
		if broken[k]:
			out["broken_props"] += 1

	var o: float = frame["arm"] * 0.01
	var mass := 0.0
	for slot_name in placed:
		mass += float(part(placed[slot_name]).get("mass", 0.0))
	mass += 12.0  # wiring, screws, straps
	var motor: Dictionary = part(placed.get("motor_1", "motor_2306_ccw"))
	var prop: Dictionary = part(placed.get("prop_1", "prop_5143_ccw"))
	var batt: Dictionary = part(placed.get("battery", "bat_1500"))

	var d_in: float = prop["diam"] * frame["prop_in"] / 5.0
	var kv: float = motor["kv"]
	# Thrust ~ KV^1.3 * diameter^3 (per motor at 100% rpm, full pack). Reference: 2306 2400KV with a 5.1" prop = 11.5 N.
	var t0: float = 11.5 * pow(kv / 2400.0, 1.3) * pow(d_in / 5.1, 3.0) * prop["thrust"]
	var thrust_full: float = t0 * frame["duct"]
	# Current ~ thrust^1.5 (power), larger props are more efficient. Reference: 21 A at 100% rpm.
	var amps_full: float = 21.0 * pow(t0 / 11.5, 1.5) * (5.1 / d_in) * prop["cur"]

	# Point-mass inertia model (kg m^2)
	var m_motor: float = (motor["mass"] + prop["mass"]) * 0.001
	var m_arm: float = frame["mass"] * 0.001 * 0.15
	var m_total: float = mass * 0.001
	var m_center: float = maxf(m_total - 4.0 * (m_motor + m_arm), 0.02)
	var ix: float = 4.0 * m_motor * o * o + 4.0 * m_arm * (o * 0.5) * (o * 0.5) + m_center * pow(0.032 + o * 0.15, 2.0)
	var iy: float = 4.0 * m_motor * 2.0 * o * o + 4.0 * m_arm * 2.0 * (o * 0.5) * (o * 0.5) + m_center * pow(0.04 + o * 0.2, 2.0)

	out.merge({
		"frame": placed["frame"], "frame_name": frame["name"],
		"motor_type": motor["type"], "motor_name": "%s %dKV" % [motor["type"], kv], "kv": kv,
		"prop_type": prop["type"], "prop_name": prop["name"].get_slice(" (", 0), "blades": prop["blades"], "prop_tau": prop["tau"],
		"prop_in": d_in,
		"mass_g": mass, "mass": m_total,
		"arm": o,
		"thrust_full": thrust_full, "amps_full": amps_full,
		"inertia": Vector3(ix, iy, ix),
		"capacity_mah": batt["mah"], "battery_name": batt["name"], "cells": 4,
		"drag": 0.0045 * frame["drag"],   # quadratic drag coefficient N/(m/s)^2
		"kq": 0.0036 * d_in,              # prop reaction torque per newton of thrust (m)
		"twr": 4.0 * thrust_full * 0.72 / (m_total * 9.81),
	}, true)
	return out


static func slot_cat(frame_id: String, slot_name: String) -> String:
	var s := slot_by_name(frame_id, slot_name)
	return s.get("cat", slot_name)
