class_name Parts
extends RefCounted
## Static catalogue: parts, slot layouts, solder pads, wire harness and the
## derived airframe statistics used by the flight model.
##
## Units: the workshop uses 1 unit = 1 cm. Forward is -Z, up is +Y, right is +X.

const CATEGORIES := ["frame", "motor", "prop", "esc", "fc", "rx", "vtx", "antenna", "cam_mount", "cam", "battery", "guard", "payload"]
const CAT_NAMES := {
	"frame": "Frame", "motor": "Motors", "prop": "Props", "esc": "ESC",
	"fc": "Flight ctrl", "rx": "Receiver", "vtx": "VTX", "antenna": "Antenna", "cam_mount": "Cam mount",
	"cam": "Camera", "battery": "Battery", "guard": "Protection", "payload": "Module",
}
const CAT_QUOTA := {"frame": 1, "motor": 4, "prop": 4, "esc": 1, "fc": 1, "rx": 1, "vtx": 1, "antenna": 1, "cam_mount": 1, "cam": 1, "battery": 1, "guard": 1, "payload": 1}
## Categories a drone can fly without.
const OPTIONAL_CATS := ["guard", "payload"]
## Screws / fasteners the player drives in after placing a part (simplified tool interaction).
const SCREWS := {"motor": 4, "prop": 1, "esc": 4, "fc": 4, "vtx": 2, "antenna": 1, "cam_mount": 2, "cam": 2, "battery": 1, "guard": 4, "payload": 2}
const ELECTRONICS := ["esc", "fc", "rx", "vtx"]

## Parts unlocked by finishing a mission (saved in save.json).
const UNLOCKS := {
	"gate_race": ["frame_3", "motor_2207_cw", "motor_2207_ccw", "prop_5040_cw", "prop_5040_ccw", "bat_2200"],
	"battery_challenge": ["frame_7", "motor_2806_cw", "motor_2806_ccw"],
}
const MISSION_NAMES := {"free_flight": "Free Flight", "gate_race": "Gate Race", "battery_challenge": "Battery Challenge"}

## Fictional manufacturers (PARTS MARKET).
const BRANDS := {
	"kestrel": {"name": "Kestrel Dynamics", "blurb": "Carbon frames and airframe hardware."},
	"voltforge": {"name": "Voltforge Motors", "blurb": "Brushless motors, wound in-house."},
	"aerofoil": {"name": "Aerofoil Works", "blurb": "Injection-moulded propellers."},
	"hexacore": {"name": "Hexacore Labs", "blurb": "Flight controllers and power boards."},
	"stepline": {"name": "Stepline Radio", "blurb": "Receivers, video transmitters and antennas."},
	"lumen": {"name": "Lumen Optics", "blurb": "FPV cameras and mounts."},
	"boreal": {"name": "Boreal Cells", "blurb": "Simulated LiPo packs (game abstraction)."},
	"ironweave": {"name": "Ironweave Fabrication", "blurb": "Guards, armour plates and mission modules."},
}

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
	# tier = garage level at which the PARTS MARKET starts stocking it. print = filament cost if the 3D printer can make it.
	_add("frame_5", {"cat": "frame", "name": "5\" Carbon X-Frame", "mass": 85.0, "arm": 7.95, "prop_in": 5.0, "drag": 1.0, "duct": 1.0, "durability": 1.0,
		"unlock": "", "brand": "kestrel", "price": 90, "quality": 3, "tier": 1, "desc": "Classic 225 mm freestyle frame. Balanced and quick."})
	_add("frame_3", {"cat": "frame", "name": "3\" Ducted Whoop Frame", "mass": 30.0, "arm": 4.4, "prop_in": 3.0, "drag": 0.55, "duct": 1.8, "durability": 0.7,
		"unlock": "gate_race", "brand": "kestrel", "price": 70, "quality": 3, "tier": 1, "desc": "Tiny ducted frame. Light and agile - duct boosts thrust. Props auto-size to the frame. Too small for mission modules."})
	_add("frame_7", {"cat": "frame", "name": "7\" Long-Range Frame", "mass": 140.0, "arm": 10.4, "prop_in": 7.0, "drag": 1.5, "duct": 1.0, "durability": 1.25,
		"unlock": "battery_challenge", "brand": "kestrel", "price": 160, "quality": 4, "tier": 2, "desc": "Big 300 mm cruiser. Efficient, heavy and slow to turn. Best with 2806 motors. Carries the heavy module."})
	_add("frame_5a", {"cat": "frame", "name": "5\" Armoured X-Frame", "mass": 125.0, "arm": 7.95, "prop_in": 5.0, "drag": 1.15, "duct": 1.0, "durability": 1.7,
		"unlock": "", "brand": "ironweave", "price": 150, "quality": 4, "tier": 3, "desc": "Thick-plate 5\" frame with reinforced arms. Shrugs off crashes, costs agility."})

	var motors := {
		"2306": {"kv": 2400, "mass": 32.0, "color": Color(0.85, 0.12, 0.12), "size": 1.0, "unlock": "", "price": 22, "quality": 3, "tier": 1, "desc": "The all-rounder. Punchy and thirsty."},
		"2207": {"kv": 1800, "mass": 31.0, "color": Color(0.15, 0.4, 0.95), "size": 0.95, "unlock": "gate_race", "price": 26, "quality": 4, "tier": 1, "desc": "Lower KV: gentler thrust, much lighter on the battery."},
		"2806": {"kv": 1300, "mass": 52.0, "color": Color(0.12, 0.72, 0.4), "size": 1.2, "unlock": "battery_challenge", "price": 34, "quality": 4, "tier": 2, "desc": "Big low-KV stator, made for 7\" props. Efficient."},
	}
	for t in motors:
		for dir in ["cw", "ccw"]:
			var m: Dictionary = motors[t].duplicate()
			m["cat"] = "motor"
			m["type"] = t
			m["spin"] = dir.to_upper()
			m["brand"] = "voltforge"
			m["name"] = "%s %dKV Motor (%s)" % [t, m["kv"], dir.to_upper()]
			_add("motor_%s_%s" % [t, dir], m)

	var props := {
		"5143": {"name": "5143 Tri-blade", "blades": 3, "diam": 5.1, "thrust": 1.0, "cur": 1.0, "tau": 0.034, "mass": 4.8, "color": Color(1.0, 0.85, 0.0), "unlock": "", "price": 3, "quality": 3, "tier": 1,
			"desc": "Tri-blade: lots of grip and thrust. Bright yellow."},
		"5040": {"name": "5040 Bi-blade", "blades": 2, "diam": 5.0, "thrust": 0.86, "cur": 0.95, "tau": 0.026, "mass": 3.6, "color": Color(1.0, 0.45, 0.05), "unlock": "gate_race", "price": 3, "quality": 3, "tier": 1,
			"desc": "Bi-blade: snappier and more efficient, less thrust. Bright orange."},
	}
	for t in props:
		for dir in ["cw", "ccw"]:
			var p: Dictionary = props[t].duplicate()
			p["cat"] = "prop"
			p["type"] = t
			p["spin"] = dir.to_upper()
			p["brand"] = "aerofoil"
			p["name"] = "%s (%s)" % [p["name"], dir.to_upper()]
			_add("prop_%s_%s" % [t, dir], p)

	_add("esc_4in1", {"cat": "esc", "name": "4-in-1 55A ESC", "mass": 14.0, "unlock": "", "brand": "hexacore", "price": 55, "quality": 3, "tier": 1, "climit": 1.0,
		"desc": "Four ESC chips, M1-M4 motor pads, CUR current pin and a C BAT capacitor pad."})
	_add("esc_65", {"cat": "esc", "name": "4-in-1 65A HV ESC", "mass": 17.0, "unlock": "", "brand": "hexacore", "price": 85, "quality": 4, "tier": 3, "climit": 1.3,
		"desc": "Heavier-duty power board. Higher current limit for big builds and heavy modules."})
	_add("fc_f4", {"cat": "fc", "name": "F4 Flight Controller", "mass": 8.0, "unlock": "", "brand": "hexacore", "price": 45, "quality": 3, "tier": 1, "gyro": 1.0,
		"desc": "Gyro chip, motor pad row, UART and camera pads. Arrow points forward."})
	_add("fc_f7", {"cat": "fc", "name": "F7 Flight Controller", "mass": 8.0, "unlock": "", "brand": "hexacore", "price": 75, "quality": 5, "tier": 2, "gyro": 0.6,
		"desc": "Faster processor and a cleaner gyro: less vibration in the video, steadier hover."})
	_add("rx_24", {"cat": "rx", "name": "SR-2.4 Receiver", "mass": 2.0, "unlock": "", "brand": "stepline", "price": 15, "quality": 3, "tier": 1, "range": 900.0,
		"desc": "Plug-in 2.4 GHz control receiver. Fail-safe at about 900 m."})
	_add("rx_lr", {"cat": "rx", "name": "LR-900 Long-Range Receiver", "mass": 4.0, "unlock": "", "brand": "stepline", "price": 38, "quality": 4, "tier": 2, "range": 2400.0,
		"desc": "Sub-GHz long-range control link. Fail-safe at about 2.4 km."})
	_add("vtx_25", {"cat": "vtx", "name": "Analog VTX 25-600mW", "mass": 7.0, "unlock": "", "brand": "stepline", "price": 35, "quality": 3, "tier": 1, "digital": false,
		"desc": "Analogue video transmitter: breaks up gradually into static at range."})
	_add("vtx_hd", {"cat": "vtx", "name": "Digital HD VTX", "mass": 12.0, "unlock": "", "brand": "stepline", "price": 120, "quality": 5, "tier": 2, "digital": true,
		"desc": "Digital video link: crisp picture, longer range, then blocky freezes when it fades. Needs a digital camera."})
	_add("ant_stub", {"cat": "antenna", "name": "Stubby Antenna", "mass": 1.5, "unlock": "", "brand": "stepline", "price": 6, "quality": 2, "tier": 1, "gain": 0.8,
		"desc": "Short, crash-proof video antenna. About 80 % of the normal video range."})
	_add("ant_pagoda", {"cat": "antenna", "name": "Pagoda Antenna", "mass": 3.0, "unlock": "", "brand": "stepline", "price": 10, "quality": 3, "tier": 1, "gain": 1.0,
		"desc": "Circular-polarised omni antenna. The standard."})
	_add("ant_patch", {"cat": "antenna", "name": "Hi-Gain Patch Antenna", "mass": 6.0, "unlock": "", "brand": "stepline", "price": 28, "quality": 4, "tier": 2, "gain": 1.5,
		"desc": "Directional high-gain antenna. +50 % video range."})
	_add("mount_20", {"cat": "cam_mount", "name": "TPU Camera Mount 20°", "mass": 3.0, "unlock": "", "brand": "lumen", "price": 4, "quality": 2, "tier": 1, "tilt": 20.0, "damp": 1.0, "print": 2,
		"desc": "Soft printed mount, 20° up-tilt: easy cruising view."})
	_add("mount_35", {"cat": "cam_mount", "name": "Race Camera Mount 35°", "mass": 3.0, "unlock": "", "brand": "lumen", "price": 6, "quality": 3, "tier": 1, "tilt": 35.0, "damp": 1.0, "print": 3,
		"desc": "Steep 35° up-tilt for fast forward flight."})
	_add("mount_damp", {"cat": "cam_mount", "name": "Damped Gimbal Mount 25°", "mass": 9.0, "unlock": "", "brand": "lumen", "price": 18, "quality": 4, "tier": 2, "tilt": 25.0, "damp": 0.35,
		"desc": "Rubber-isolated mount: removes most prop vibration from the image."})
	_add("cam_fpv", {"cat": "cam", "name": "Micro FPV Camera (analogue)", "mass": 6.0, "unlock": "", "brand": "lumen", "price": 25, "quality": 3, "tier": 1, "digital": false,
		"desc": "Micro analogue FPV camera. Lens faces forward. Pairs with an analogue VTX."})
	_add("cam_hd", {"cat": "cam", "name": "HD FPV Camera (digital)", "mass": 9.0, "unlock": "", "brand": "lumen", "price": 70, "quality": 5, "tier": 2, "digital": true,
		"desc": "Digital camera for the HD VTX. Sharp image, better for scanning targets."})
	_add("bat_1100", {"cat": "battery", "name": "4S 1100mAh Pack", "mass": 130.0, "mah": 1100.0, "unlock": "", "brand": "boreal", "price": 25, "quality": 3, "tier": 1,
		"desc": "Light pack. Short flights."})
	_add("bat_1500", {"cat": "battery", "name": "4S 1500mAh Pack", "mass": 170.0, "mah": 1500.0, "unlock": "", "brand": "boreal", "price": 32, "quality": 3, "tier": 1,
		"desc": "The default 4S pack."})
	_add("bat_2200", {"cat": "battery", "name": "4S 2200mAh Pack", "mass": 255.0, "mah": 2200.0, "unlock": "gate_race", "brand": "boreal", "price": 45, "quality": 4, "tier": 1,
		"desc": "Big pack. Long flights, but heavy."})
	_add("bat_3000", {"cat": "battery", "name": "4S 3000mAh Long-Range Pack", "mass": 330.0, "mah": 3000.0, "unlock": "", "brand": "boreal", "price": 68, "quality": 4, "tier": 3,
		"desc": "Endurance pack for 7\" cruisers. Very heavy on a 5\"."})
	_add("guard_ring", {"cat": "guard", "name": "Printed Prop Guard Set", "mass": 38.0, "unlock": "", "brand": "ironweave", "price": 18, "quality": 2, "tier": 1, "protect": 0.45, "bump": 2.5, "drag": 0.18, "print": 6,
		"desc": "Four rings around the props: bumps that would break props become harmless. Adds drag. Not for ducted frames."})
	_add("guard_plate", {"cat": "guard", "name": "Armour Plate Kit", "mass": 60.0, "unlock": "", "brand": "ironweave", "price": 34, "quality": 4, "tier": 2, "protect": 0.6, "bump": 1.0, "drag": 0.05,
		"desc": "Bolt-on arm and top plates. Greatly reduces crash damage to the frame and electronics."})
	_add("pod_s", {"cat": "payload", "name": "Training Drop Pod", "mass": 110.0, "unlock": "", "brand": "ironweave", "price": 40, "quality": 3, "tier": 1, "charges": 1, "power": 70.0, "radius": 5.0, "kind": "drop",
		"desc": "Fictional mission module: one releasable training pod (abstract damage 70). Release with the PAYLOAD button."})
	_add("pod_twin", {"cat": "payload", "name": "Twin Drop Rack", "mass": 175.0, "unlock": "", "brand": "ironweave", "price": 75, "quality": 4, "tier": 2, "charges": 2, "power": 50.0, "radius": 4.5, "kind": "drop",
		"desc": "Two smaller releasable pods (abstract damage 50 each)."})
	_add("pod_heavy", {"cat": "payload", "name": "Heavy Breaching Pod", "mass": 300.0, "unlock": "", "brand": "ironweave", "price": 120, "quality": 4, "tier": 3, "charges": 1, "power": 170.0, "radius": 6.0, "kind": "drop", "big": true,
		"desc": "One heavy pod (abstract damage 170) for armoured targets. Needs a 7\" or armoured frame."})
	_add("pod_scan", {"cat": "payload", "name": "Recon Sensor Pod", "mass": 55.0, "unlock": "", "brand": "ironweave", "price": 85, "quality": 4, "tier": 2, "charges": 0, "power": 0.0, "radius": 0.0, "kind": "scan",
		"desc": "Wide-angle sensor pod: scans targets twice as fast and from twice as far."})


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
	out.append(_slot("rx", "rx", Vector3(0, 0.35, minf(o * 0.42, 3.4)), ["fc"]))
	out.append(_slot("vtx", "vtx", Vector3(0, Y_VTX, 0), ["fc"]))
	out.append(_slot("antenna", "antenna", Vector3(0, Y_VTX + 0.45, 1.7), ["vtx"]))
	out.append(_slot("cam_mount", "cam_mount", Vector3(0, 0.35, -o * 0.7), ["frame"]))
	out.append(_slot("cam", "cam", Vector3(0, 0.6, -o * 0.7), ["cam_mount"]))
	out.append(_slot("battery", "battery", Vector3(0, Y_BATTERY, 0), ["vtx"]))
	var g := _slot("guard", "guard", Vector3(0, 0.0, 0), ["frame"])
	g["optional"] = true
	out.append(g)
	var pl := _slot("payload", "payload", Vector3(0, -0.15, 0.6), ["frame"])
	pl["optional"] = true
	out.append(pl)
	return out


static func slot_by_name(frame_id: String, slot_name: String) -> Dictionary:
	for s in slots_for(frame_id):
		if s["name"] == slot_name:
			return s
	return {}


## Whether a part needs rotating to the slot's forward direction.
static func needs_orientation(cat: String) -> bool:
	return cat in ["frame", "esc", "fc", "vtx", "cam", "battery", "cam_mount", "rx", "payload"]


## Footprint radius used for the blue slot marker.
static func marker_radius(cat: String) -> float:
	match cat:
		"frame": return 9.0
		"motor": return 1.9
		"prop": return 3.4
		"battery": return 4.2
		"cam": return 1.6
		"cam_mount": return 1.4
		"rx": return 1.2
		"antenna": return 1.0
		"guard": return 9.0
		"payload": return 3.0
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
	var frame: Dictionary = part(placed.get("frame", ""))
	match slot["cat"]:
		"guard":
			if part_id == "guard_ring" and frame.get("duct", 1.0) > 1.0:
				return "The whoop frame is already ducted - prop guards don't fit."
		"payload":
			if frame.get("arm", 7.95) < 6.0 and p.get("kind", "") != "scan":
				return "The 3\" whoop is too small to carry a drop module."
			if p.get("big", false) and not (placed.get("frame", "") in ["frame_7", "frame_5a"]):
				return "The heavy pod needs a 7\" or armoured frame."
		"cam":
			if placed.has("vtx") and bool(part(placed["vtx"]).get("digital", false)) != bool(p.get("digital", false)):
				return "Incompatible: a %s camera needs a %s VTX." % (["digital", "digital"] if p.get("digital", false) else ["analogue", "analogue"])
		"vtx":
			if placed.has("cam") and bool(part(placed["cam"]).get("digital", false)) != bool(p.get("digital", false)):
				return "Incompatible: the installed camera is %s - this VTX is %s." % ["digital" if part(placed["cam"]).get("digital", false) else "analogue", "digital" if p.get("digital", false) else "analogue"]
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
	return {"frame": "frame", "esc": "ESC", "fc": "flight controller", "vtx": "VTX", "cam_mount": "camera mount"}.get(slot_name, slot_name)


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
## `cond` maps slot -> condition 0..1 (missing = 1.0 = new). Damaged parts degrade the stats.
static func compute_build(placed: Dictionary, broken: Dictionary, cond: Dictionary = {}) -> Dictionary:
	var out := {"complete": false, "missing": [], "missing_text": "", "broken_props": 0}
	if not placed.has("frame"):
		out["missing"] = ["frame"]
		out["missing_text"] = "no frame"
		return out
	var frame: Dictionary = part(placed["frame"])
	var missing: Array = []
	for s in slots_for(placed["frame"]):
		if not placed.has(s["name"]) and not s.get("optional", false):
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
	var cost := 0
	for slot_name in placed:
		var pp: Dictionary = part(placed[slot_name])
		mass += float(pp.get("mass", 0.0))
		cost += int(pp.get("price", 0))
	mass += 12.0  # wiring, screws, straps
	var motor: Dictionary = part(placed.get("motor_1", "motor_2306_ccw"))
	var prop: Dictionary = part(placed.get("prop_1", "prop_5143_ccw"))
	var batt: Dictionary = part(placed.get("battery", "bat_1500"))
	var guard: Dictionary = part(placed.get("guard", ""))
	var pay: Dictionary = part(placed.get("payload", ""))
	var c := func(slot: String) -> float: return clampf(float(cond.get(slot, 1.0)), 0.0, 1.0)

	var d_in: float = prop["diam"] * frame["prop_in"] / 5.0
	var kv: float = motor["kv"]
	# Thrust ~ KV^1.3 * diameter^3 (per motor at 100% rpm, full pack). Reference: 2306 2400KV with a 5.1" prop = 11.5 N.
	var t0: float = 11.5 * pow(kv / 2400.0, 1.3) * pow(d_in / 5.1, 3.0) * prop["thrust"]
	var thrust_full: float = t0 * frame["duct"]
	# Current ~ thrust^1.5 (power), larger props are more efficient. Reference: 21 A at 100% rpm.
	var amps_full: float = 21.0 * pow(t0 / 11.5, 1.5) * (5.1 / d_in) * prop["cur"]
	var motor_health: Array = []
	for i in 4:
		motor_health.append(0.55 + 0.45 * float(c.call("motor_%d" % (i + 1))))

	# Point-mass inertia model (kg m^2)
	var m_motor: float = (motor["mass"] + prop["mass"]) * 0.001
	var m_arm: float = frame["mass"] * 0.001 * 0.15
	var m_total: float = mass * 0.001
	var m_center: float = maxf(m_total - 4.0 * (m_motor + m_arm), 0.02)
	var ix: float = 4.0 * m_motor * o * o + 4.0 * m_arm * (o * 0.5) * (o * 0.5) + m_center * pow(0.032 + o * 0.15, 2.0)
	var iy: float = 4.0 * m_motor * 2.0 * o * o + 4.0 * m_arm * 2.0 * (o * 0.5) * (o * 0.5) + m_center * pow(0.04 + o * 0.2, 2.0)

	var elec := 1.0
	for e in ELECTRONICS:
		elec = minf(elec, c.call(e))
	var vtx: Dictionary = part(placed.get("vtx", "vtx_25"))
	var mount: Dictionary = part(placed.get("cam_mount", "mount_20"))
	var fc: Dictionary = part(placed.get("fc", "fc_f4"))
	var drag_mult: float = frame["drag"] + float(guard.get("drag", 0.0))
	var durability: float = float(frame.get("durability", 1.0)) * (0.55 + 0.45 * float(c.call("frame"))) + float(guard.get("protect", 0.0))
	out.merge({
		"frame": placed["frame"], "frame_name": frame["name"],
		"motor_type": motor["type"], "motor_name": "%s %dKV" % [motor["type"], kv], "kv": kv,
		"prop_type": prop["type"], "prop_name": prop["name"].get_slice(" (", 0), "blades": prop["blades"], "prop_tau": prop["tau"],
		"prop_in": d_in,
		"mass_g": mass, "mass": m_total,
		"arm": o,
		"thrust_full": thrust_full, "amps_full": amps_full,
		"motor_health": motor_health,
		"inertia": Vector3(ix, iy, ix),
		"capacity_mah": batt["mah"] * (0.6 + 0.4 * float(c.call("battery"))), "battery_name": batt["name"], "cells": 4,
		"drag": 0.0045 * drag_mult,       # quadratic drag coefficient N/(m/s)^2
		"kq": 0.0036 * d_in,              # prop reaction torque per newton of thrust (m)
		"twr": 4.0 * thrust_full * 0.72 / (m_total * 9.81),
		"cost": cost,
		"rx_range": float(part(placed.get("rx", "rx_24")).get("range", 900.0)) * (0.5 + 0.5 * float(c.call("rx"))),
		"video_gain": float(part(placed.get("antenna", "ant_pagoda")).get("gain", 1.0)) * (0.5 + 0.5 * float(c.call("vtx"))) * (1.35 if vtx.get("digital", false) else 1.0),
		"digital": bool(vtx.get("digital", false)),
		"cam_tilt": float(mount.get("tilt", 20.0)),
		"vibration": float(mount.get("damp", 1.0)) * float(fc.get("gyro", 1.0)) * (1.0 + (1.0 - float(c.call("frame"))) * 1.5),
		"cam_noise": (1.0 - float(c.call("cam"))) * 0.6,
		"glitch": (1.0 - elec),
		"durability": durability,
		"crash_speed": 7.0 + float(guard.get("bump", 0.0)) + (float(frame.get("durability", 1.0)) - 1.0) * 2.0,
		"current_mult": float(part(placed.get("esc", "esc_4in1")).get("climit", 1.0)),
		"payload_id": placed.get("payload", ""),
		"payload_kind": pay.get("kind", ""),
		"payload_charges": int(pay.get("charges", 0)),
		"payload_power": float(pay.get("power", 0.0)),
		"payload_radius": float(pay.get("radius", 0.0)),
		"payload_unit_mass": (float(pay.get("mass", 0.0)) * 0.6 / maxf(float(pay.get("charges", 1)), 1.0)) * 0.001,
		"scan_mult": 2.0 if pay.get("kind", "") == "scan" else (1.3 if part(placed.get("cam", "cam_fpv")).get("digital", false) else 1.0),
	}, true)
	out.merge(performance(out), true)
	return out


## Derived "spec sheet" numbers for the UI (endurance, speed, agility, durability).
static func performance(st: Dictionary) -> Dictionary:
	if not st.has("thrust_full"):
		return {}
	var w_hover := sqrt(clampf(st["mass"] * 9.81 / 4.0 / maxf(st["thrust_full"] * 0.9, 0.01), 0.0, 1.0))
	var amps_hover: float = 4.0 * (0.1 + st["amps_full"] * pow(w_hover, 2.2) * (16.8 / 15.2)) + 0.55
	var endurance_min: float = st["capacity_mah"] * 0.8 / 1000.0 / maxf(amps_hover, 0.1) * 60.0
	var t_total: float = 4.0 * st["thrust_full"] * 0.72
	var weight: float = st["mass"] * 9.81
	var fh := sqrt(maxf(t_total * t_total - weight * weight, 0.0))
	var top_kmh := sqrt(fh / maxf(st["drag"], 0.0001)) * 3.6 * 0.62
	var agility := clampf((st["twr"] - 2.0) / 9.0, 0.0, 1.0) * 70.0 + clampf(1.0 - (st["inertia"].x - 0.0006) / 0.004, 0.0, 1.0) * 30.0
	return {
		"hover_throttle": w_hover, "hover_amps": amps_hover, "endurance_min": endurance_min,
		"top_kmh": top_kmh, "agility": agility, "durability_pct": clampf(st["durability"] / 2.4, 0.0, 1.0) * 100.0,
	}


## Readable one-line warnings about a build ("" = none).
static func build_warnings(st: Dictionary) -> Array:
	var w: Array = []
	if not st.get("complete", false):
		return w
	if st["twr"] < 2.2:
		w.append("Very low thrust-to-weight (%.1f) - it will barely climb." % st["twr"])
	elif st["twr"] < 3.2:
		w.append("Low thrust-to-weight (%.1f) - sluggish with a module." % st["twr"])
	if st["endurance_min"] < 2.5:
		w.append("Short endurance (~%.1f min)." % st["endurance_min"])
	if st["glitch"] > 0.3:
		w.append("Damaged electronics - expect video/control glitches.")
	for i in 4:
		if st["motor_health"][i] < 0.8:
			w.append("Motor %d is damaged (%.0f %% thrust)." % [i + 1, st["motor_health"][i] * 100.0])
			break
	return w


static func slot_cat(frame_id: String, slot_name: String) -> String:
	var s := slot_by_name(frame_id, slot_name)
	return s.get("cat", slot_name)
