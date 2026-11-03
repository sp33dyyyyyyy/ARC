class_name Campaign
extends RefCounted
## Static campaign data: missions, garage levels and upgrades, customer contracts.
## Everything here is fictional: the hostile force, its equipment and the regions.

const FACTION_PLAYER := "Kalvarian Volunteer Workshops"
const FACTION_ENEMY := "Dravic Ironguard"

const MAP_NAMES := {
	"testing": "Garage & Testing Grounds",
	"rural": "Rural Conflict Zone - Vessa Lowlands",
	"industrial": "Industrial Conflict Zone - Korvo Works",
}

## Target archetypes. hp / armour are abstract game numbers.
const TARGETS := {
	"truck": {"name": "Strelka utility truck", "hp": 60.0, "armour": 0.0, "size": Vector3(1.25, 1.5, 3.2), "score": 100},
	"apc": {"name": "Korsak light armoured carrier", "hp": 110.0, "armour": 0.25, "size": Vector3(1.4, 1.3, 3.5), "score": 250},
	"heavy_apc": {"name": "Bastion tracked transport", "hp": 150.0, "armour": 0.35, "size": Vector3(1.6, 1.4, 3.8), "score": 320},
	"tank": {"name": "IG-70 Warden tank", "hp": 210.0, "armour": 0.5, "size": Vector3(1.8, 1.4, 4.0), "score": 500},
	"radar_truck": {"name": "Okulus mobile radar", "hp": 90.0, "armour": 0.1, "size": Vector3(1.3, 1.6, 3.4), "score": 300},
	"heli_scout": {"name": "Vespa-9 scout helicopter", "hp": 80.0, "armour": 0.1, "size": Vector3(1.2, 1.3, 5.0), "score": 450},
	"heli_transport": {"name": "Tarn-4 transport helicopter", "hp": 140.0, "armour": 0.2, "size": Vector3(1.8, 2.0, 8.0), "score": 650},
	"uav": {"name": "Kestra patrol UAV", "hp": 30.0, "armour": 0.0, "size": Vector3(2.5, 0.4, 1.4), "score": 150},
	"radar_site": {"name": "Radar installation", "hp": 100.0, "armour": 0.15, "size": Vector3(2.5, 3.0, 2.5), "score": 300},
	"jammer": {"name": "Signal jammer mast", "hp": 70.0, "armour": 0.1, "size": Vector3(1.2, 6.0, 1.2), "score": 250},
	"tower": {"name": "Empty guard tower", "hp": 80.0, "armour": 0.1, "size": Vector3(1.6, 4.5, 1.6), "score": 120},
	"board": {"name": "Range target structure", "hp": 40.0, "armour": 0.0, "size": Vector3(1.8, 1.6, 0.5), "score": 80},
	"container": {"name": "Unoccupied supply container", "hp": 50.0, "armour": 0.05, "size": Vector3(1.25, 1.3, 3.0), "score": 90},
	"comms": {"name": "Field communications unit", "hp": 60.0, "armour": 0.05, "size": Vector3(1.4, 1.2, 1.4), "score": 140},
}

## Mission definitions. `objectives`: destroy (ids or kinds) / scan / gates / rtb.
static func missions() -> Array:
	return [
		{"id": "shakedown", "name": "Shakedown Flight", "map": "testing", "type": "gates", "difficulty": 1,
			"time": "noon", "weather": "clear", "wind": 1.5, "reward": 200, "repeat_reward": 40, "rep": 1, "recover": "recoverable",
			"requires": [], "blurb": "Fly the six orange test gates on the field behind the garage, then land back on the pad. Proves the build before it goes anywhere near the front."},
		{"id": "gate_race", "name": "Gate Race", "map": "testing", "type": "race", "difficulty": 2,
			"time": "dusk", "weather": "clear", "wind": 1.0, "reward": 350, "repeat_reward": 80, "rep": 1, "recover": "recoverable",
			"requires": ["shakedown"], "blurb": "Twelve floating rings in order against the clock. Sponsors watch these times."},
		{"id": "battery_challenge", "name": "Battery Challenge", "map": "testing", "type": "battery", "difficulty": 2,
			"time": "dusk", "weather": "clear", "wind": 2.0, "reward": 500, "repeat_reward": 120, "rep": 1, "recover": "recoverable",
			"requires": ["shakedown"], "blurb": "A 3.3 km, 17-checkpoint route on one pack. Endurance builds shine."},
		{"id": "free_flight", "name": "Free Flight - Testing Grounds", "map": "testing", "type": "free", "difficulty": 1,
			"time": "dusk", "weather": "clear", "wind": 1.0, "reward": 0, "repeat_reward": 0, "rep": 0, "recover": "recoverable",
			"requires": [], "blurb": "No objectives. Practise over the hills and the lake."},
		{"id": "range_static", "name": "Training Range: Static Targets", "map": "rural", "type": "strike", "difficulty": 1,
			"time": "noon", "weather": "clear", "wind": 2.0, "reward": 600, "repeat_reward": 150, "rep": 1, "recover": "recoverable",
			"requires": ["shakedown"], "targets": [{"kind": "board", "at": "range", "n": 3, "objective": true}],
			"blurb": "Destroy three range target structures with your mission module (or by impact). Training rules: crashed drones are recovered."},
		{"id": "eyes_road", "name": "Eyes on the Road", "map": "rural", "type": "recon", "difficulty": 2,
			"time": "dawn", "weather": "fog", "wind": 3.0, "reward": 700, "repeat_reward": 180, "rep": 1, "recover": "contested",
			"requires": ["range_static"], "targets": [{"kind": "truck", "at": "checkpoint", "n": 1, "objective": true}, {"kind": "apc", "at": "checkpoint", "n": 1, "objective": true}, {"kind": "comms", "at": "checkpoint", "n": 1, "objective": true}],
			"blurb": "Scan the three vehicles and equipment at the Ironguard road checkpoint (keep them centred in view), then bring the drone home and land at the launch point."},
		{"id": "convoy", "name": "Convoy Interdiction", "map": "rural", "type": "strike", "difficulty": 3,
			"time": "noon", "weather": "overcast", "wind": 4.0, "reward": 1400, "repeat_reward": 300, "rep": 2, "recover": "contested",
			"requires": ["eyes_road"], "targets": [{"kind": "convoy", "units": ["truck", "apc", "truck"], "objective_index": 1}],
			"blurb": "A supply convoy is moving along the valley road. Stop the Korsak armoured carrier in the middle of the column. The trucks are a bonus."},
		{"id": "radar_blackout", "name": "Radar Blackout", "map": "industrial", "type": "strike", "difficulty": 3,
			"time": "dusk", "weather": "clear", "wind": 3.0, "reward": 1800, "repeat_reward": 380, "rep": 2, "recover": "contested",
			"requires": ["convoy"], "targets": [{"kind": "radar_site", "at": "radar", "n": 1, "objective": true}, {"kind": "jammer", "at": "radar_jam", "n": 1, "objective": true}, {"kind": "radar_truck", "at": "yard", "n": 1, "objective": false}],
			"blurb": "Knock out the radar installation and the jammer mast on the factory roofline. The jammer scrambles your video when you get close - take it down first."},
		{"id": "warehouse_recon", "name": "Warehouse Recon", "map": "industrial", "type": "recon", "difficulty": 2,
			"time": "dusk", "weather": "fog", "wind": 2.0, "reward": 1100, "repeat_reward": 250, "rep": 1, "recover": "contested",
			"requires": ["eyes_road"], "targets": [{"kind": "container", "at": "yard", "n": 3, "objective": true}, {"kind": "radar_truck", "at": "yard", "n": 1, "objective": true}],
			"blurb": "Scan the stockpile in the rail yard between the warehouses and return to the launch point."},
		{"id": "rotor_hunt", "name": "Rotor Hunt", "map": "industrial", "type": "strike", "difficulty": 4,
			"time": "noon", "weather": "overcast", "wind": 4.5, "reward": 2200, "repeat_reward": 450, "rep": 2, "recover": "contested",
			"requires": ["convoy"], "targets": [{"kind": "heli_scout", "at": "helipad", "n": 1, "objective": true, "patrol": "loop"}],
			"blurb": "A Vespa-9 scout helicopter flies a patrol loop over the works and lands on the yard helipad between legs. Catch it on the pad or in the air."},
		{"id": "iron_column", "name": "Iron Column", "map": "rural", "type": "strike", "difficulty": 4,
			"time": "dusk", "weather": "rain", "wind": 5.0, "reward": 3000, "repeat_reward": 600, "rep": 3, "recover": "contested",
			"requires": ["rotor_hunt"], "targets": [{"kind": "convoy", "units": ["apc", "tank", "heavy_apc", "truck"], "objective_index": 1}],
			"blurb": "A heavy column led by a Warden tank. The tank has thick armour: bring a heavy pod or two drones' worth of hits."},
		{"id": "transport_hunt", "name": "Transport Hunt", "map": "industrial", "type": "strike", "difficulty": 5,
			"time": "dawn", "weather": "clear", "wind": 5.5, "reward": 3500, "repeat_reward": 700, "rep": 3, "recover": "contested",
			"requires": ["rotor_hunt"], "targets": [{"kind": "heli_transport", "at": "helipad", "n": 1, "objective": true, "patrol": "wide"}, {"kind": "uav", "at": "sky", "n": 2, "objective": false}],
			"blurb": "A Tarn-4 transport helicopter is shuttling between the works and the hills, escorted by patrol UAVs. Bring it down."},
		{"id": "rural_free", "name": "Free Flight - Vessa Lowlands", "map": "rural", "type": "free", "difficulty": 1,
			"time": "noon", "weather": "clear", "wind": 2.0, "reward": 0, "repeat_reward": 0, "rep": 0, "recover": "recoverable",
			"requires": ["range_static"], "blurb": "Explore the countryside. Parked vehicles near the farm make good scan practice."},
		{"id": "industrial_free", "name": "Free Flight - Korvo Works", "map": "industrial", "type": "free", "difficulty": 1,
			"time": "noon", "weather": "clear", "wind": 2.0, "reward": 0, "repeat_reward": 0, "rep": 0, "recover": "recoverable",
			"requires": ["warehouse_recon"], "blurb": "Fly between the warehouses and chimneys."},
	]


static func mission(id: String) -> Dictionary:
	for m in missions():
		if m["id"] == id:
			return m
	return {}


## Garage level ladder. Each level adds visible equipment.
const LEVELS := [
	{"level": 1, "name": "Home Garage", "cost": 0, "rep": 0, "rack": 3, "docks": 1, "storage": 60,
		"adds": "Workbench, computer, one shelf, single charging dock, test station."},
	{"level": 2, "name": "Improved Workshop", "cost": 2500, "rep": 3, "rack": 5, "docks": 2, "storage": 110,
		"adds": "3D printer, second charging dock, extra shelving, a bigger drone rack, more parts in the market."},
	{"level": 3, "name": "Small Drone Factory", "cost": 6000, "rep": 6, "rack": 7, "docks": 3, "storage": 180,
		"adds": "Automated assembly station, tier-3 parts (armoured frames, heavy modules), third dock."},
	{"level": 4, "name": "Advanced Drone Production Garage", "cost": 12000, "rep": 10, "rack": 9, "docks": 4, "storage": 280,
		"adds": "Faster assembly line, paint booth, flood lights, fourth dock."},
	{"level": 5, "name": "Professional Drone Development Facility", "cost": 22000, "rep": 15, "rack": 12, "docks": 6, "storage": 450,
		"adds": "Development lab bench, fast chargers everywhere, premium contracts."},
]

## One-off workshop upgrades bought in GARAGE UPGRADES.
const UPGRADES := {
	"power_driver": {"name": "Power screwdriver", "cost": 250, "level": 1, "desc": "Drives all screws of a part in one go at the workbench."},
	"fast_charger": {"name": "Fast charger firmware", "cost": 600, "level": 1, "desc": "Charging docks charge twice as fast."},
	"extra_shelf": {"name": "Extra shelving unit", "cost": 400, "level": 1, "desc": "+40 storage space for components."},
	"bulk_supplier": {"name": "Bulk supplier account", "cost": 900, "level": 2, "desc": "10 % off every PARTS MARKET order."},
	"express_post": {"name": "Express courier contract", "cost": 700, "level": 2, "desc": "Deliveries arrive in half the time."},
	"assembly_speed": {"name": "Servo-driven assembly arms", "cost": 2500, "level": 3, "desc": "The automated assembly station works twice as fast."},
}

const PAINTS := [
	{"name": "Raw carbon", "color": Color(0.055, 0.055, 0.065)},
	{"name": "Olive drab", "color": Color(0.27, 0.3, 0.17)},
	{"name": "Field grey", "color": Color(0.36, 0.38, 0.38)},
	{"name": "Desert tan", "color": Color(0.62, 0.52, 0.34)},
	{"name": "Sky blue", "color": Color(0.25, 0.48, 0.75)},
	{"name": "Signal orange", "color": Color(0.95, 0.45, 0.08)},
	{"name": "Racing red", "color": Color(0.75, 0.08, 0.08)},
	{"name": "Night black", "color": Color(0.02, 0.02, 0.025)},
]

## Customer contract templates. `req` keys are checked by contract_check().
const CONTRACT_TEMPLATES := [
	{"customer": "Skylark Racing League", "kind": "Racing drone", "level": 1, "req": {"min_twr": 6.0, "min_top": 95.0}, "qty": [1, 2], "margin": 1.7,
		"text": "Light, fast quads for a club race series. Thrust-to-weight 6+ and a top speed of 95 km/h or better."},
	{"customer": "Northfield Flight School", "kind": "Training drone", "level": 1, "req": {"guard": true, "max_cost": 420}, "qty": [1, 3], "margin": 1.6,
		"text": "Forgiving trainers for new pilots: prop guards or armour plates fitted, cheap to replace."},
	{"customer": "Harrow Agro Co-op", "kind": "Camera drone", "level": 1, "req": {"min_endurance": 4.5}, "qty": [1, 2], "margin": 1.6,
		"text": "Field-survey quads for crop photos. At least 4.5 minutes of hover endurance."},
	{"customer": "Civil Survey Bureau", "kind": "Reconnaissance drone", "level": 2, "req": {"long_range": true, "min_endurance": 4.0}, "qty": [1, 2], "margin": 1.8,
		"text": "Long-range mapping quads: long-range receiver and 4+ minutes of endurance."},
	{"customer": "Field Logistics Depot", "kind": "Utility drone", "level": 2, "req": {"payload": true, "min_twr": 3.0}, "qty": [1, 2], "margin": 1.75,
		"text": "Utility carriers with any mission module fitted and enough thrust to lift it (TWR 3+)."},
	{"customer": "Volunteer Defence Training Centre", "kind": "Training drone", "level": 2, "req": {"digital": true, "max_cost": 700}, "qty": [2, 3], "margin": 1.7,
		"text": "Digital-video trainers for the volunteer pilot course."},
	{"customer": "Meridian Film Collective", "kind": "Camera drone", "level": 3, "req": {"digital": true, "damped": true, "min_endurance": 5.0}, "qty": [1, 1], "margin": 2.0,
		"text": "Cinema quad: digital video, damped camera mount, 5+ minutes in the air."},
]


## Why `drone` (a Career roster entry) doesn't satisfy `contract`. "" = it does.
static func contract_check(contract: Dictionary, drone: Dictionary) -> String:
	var st := Parts.compute_build(drone.get("placed", {}), drone.get("broken", {}), drone.get("cond", {}))
	if not st.get("complete", false):
		return "Build is incomplete."
	if st["broken_props"] > 0:
		return "Has broken props."
	for k in drone.get("cond", {}):
		if float(drone["cond"][k]) < 0.9:
			return "Has damaged parts - repair them first."
	if not drone.get("certified", false):
		return "Not certified - run diagnostics first."
	var req: Dictionary = contract.get("req", {})
	if req.has("min_twr") and st["twr"] < req["min_twr"]:
		return "Thrust-to-weight %.1f < %.1f." % [st["twr"], req["min_twr"]]
	if req.has("min_top") and st["top_kmh"] < req["min_top"]:
		return "Top speed %d < %d km/h." % [int(st["top_kmh"]), int(req["min_top"])]
	if req.has("min_endurance") and st["endurance_min"] < req["min_endurance"]:
		return "Endurance %.1f < %.1f min." % [st["endurance_min"], req["min_endurance"]]
	if req.has("max_cost") and st["cost"] > req["max_cost"]:
		return "Parts cost %d > %d cr." % [st["cost"], req["max_cost"]]
	var placed: Dictionary = drone.get("placed", {})
	if req.get("guard", false) and not placed.has("guard"):
		return "Needs prop guards or armour plates."
	if req.get("payload", false) and not placed.has("payload"):
		return "Needs a mission module."
	if req.get("long_range", false) and placed.get("rx", "") != "rx_lr":
		return "Needs the long-range receiver."
	if req.get("digital", false) and not st["digital"]:
		return "Needs digital video."
	if req.get("damped", false) and placed.get("cam_mount", "") != "mount_damp":
		return "Needs the damped camera mount."
	return ""


static func req_text(req: Dictionary) -> String:
	var t: Array = []
	if req.has("min_twr"):
		t.append("TWR ≥ %.1f" % req["min_twr"])
	if req.has("min_top"):
		t.append("top speed ≥ %d km/h" % int(req["min_top"]))
	if req.has("min_endurance"):
		t.append("endurance ≥ %.1f min" % req["min_endurance"])
	if req.has("max_cost"):
		t.append("parts ≤ %d cr" % int(req["max_cost"]))
	if req.get("guard", false):
		t.append("guards/armour")
	if req.get("payload", false):
		t.append("mission module")
	if req.get("long_range", false):
		t.append("long-range RX")
	if req.get("digital", false):
		t.append("digital video")
	if req.get("damped", false):
		t.append("damped mount")
	return ", ".join(t)


## Parts the player starts the career with: exactly one complete drone, plus a few spare props.
static func starter_kit() -> Dictionary:
	var kit := {}
	for slot in DroneVisual.default_placement():
		var id: String = DroneVisual.default_placement()[slot]
		kit[id] = int(kit.get(id, 0)) + 1
	kit["prop_5143_cw"] = int(kit["prop_5143_cw"]) + 2
	kit["prop_5143_ccw"] = int(kit["prop_5143_ccw"]) + 2
	kit["pod_s"] = 1
	return kit
