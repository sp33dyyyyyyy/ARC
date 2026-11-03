extends Node
## The garage business: credits, component inventory, salvage, the drone roster,
## deliveries, production jobs, contracts, garage level and the career guide.
## Persisted to user://career.json. Ticks in the background on every screen.

signal changed
signal notify(text: String, kind: String)       # kind: info / good / bad / delivery
signal delivery_ready(order: Dictionary)

const PATH := "user://career.json"
const START_CREDITS := 1500
const DELIVERY_BASE := 35.0          # seconds of play time for a standard delivery
const CHARGE_RATE := 1.0 / 90.0       # pack fraction per second in a dock (fast charger doubles it)
const AUTOSAVE_S := 20.0

var data: Dictionary = {}
var _autosave_t := 0.0
var _tut_t := 0.0
var _dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_career()


# --- defaults / persistence ---------------------------------------------------
func defaults() -> Dictionary:
	return {
		"version": 2,
		"credits": START_CREDITS,
		"rep": 0,
		"level": 1,
		"day": 1,
		"clock": 9.0 * 60.0,        # minutes since midnight
		"playtime": 0.0,
		"inventory": {},
		"salvage": [],
		"roster": [],
		"next_no": 1,
		"bench_drone": "",
		"active_drone": "",
		"presets": [],
		"orders": [],
		"parcels": [{"id": "starter", "label": "STARTER KIT", "items": Campaign.starter_kit(), "where": "cupboard", "opened": false}],
		"jobs": [],
		"contracts": [],
		"ledger": [],
		"missions_done": {},
		"upgrades": {},
		"docks": [],
		"printer": {},
		"layout": {"door_open": false, "lights_on": true, "items": []},
		"tutorial": 0,
		"flags": {},
		"bought": {},
		"stats": {"flights": 0, "targets": 0, "drones_lost": 0, "drones_built": 0, "contracts": 0},
	}


func new_career() -> void:
	data = defaults()
	Game.reset_build()
	_refresh_contracts()
	save()
	changed.emit()


func load_career() -> void:
	data = defaults()
	if not FileAccess.file_exists(PATH):
		_refresh_contracts()
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("career.json is corrupt - starting a new career")
		_refresh_contracts()
		return
	for k in data:
		if parsed.has(k) and typeof(parsed[k]) == typeof(data[k]):
			data[k] = parsed[k]
		elif parsed.has(k) and (data[k] is float or data[k] is int) and (parsed[k] is float or parsed[k] is int):
			data[k] = type_convert(parsed[k], typeof(data[k]))
	# sanitise
	var inv := {}
	for id in data["inventory"]:
		if Parts.db().has(id):
			inv[id] = maxi(int(data["inventory"][id]), 0)
	data["inventory"] = inv
	data["roster"] = data["roster"].filter(func(d): return d is Dictionary and d.get("placed") is Dictionary)
	for d in data["roster"]:
		_sanitise_drone(d)
	_refresh_contracts()


func _sanitise_drone(d: Dictionary) -> void:
	for k in ["broken", "cond", "cfg"]:
		if not (d.get(k) is Dictionary):
			d[k] = {}
	if not (d.get("wires") is Array):
		d["wires"] = []
	var cfg := FlightMath.default_cfg()
	Game._merge_cfg(cfg, d["cfg"])
	d["cfg"] = cfg
	d["charge"] = clampf(float(d.get("charge", 1.0)), 0.0, 1.0)
	if not d.has("battery_in"):
		d["battery_in"] = true
	if not d.has("location"):
		d["location"] = "rack"
	if not d.has("paint") or not (d["paint"] is Array):
		d["paint"] = []


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write career.json")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_dirty = false


func mark_dirty() -> void:
	_dirty = true
	changed.emit()


# --- money ----------------------------------------------------------------------
func credits() -> int:
	return int(data["credits"])


func earn(amount: int, text: String) -> void:
	if amount == 0:
		return
	data["credits"] = credits() + amount
	_ledger(text, amount)
	mark_dirty()


func spend(amount: int, text: String) -> bool:
	if amount > credits():
		notify.emit("Not enough credits (%d cr needed)." % amount, "bad")
		return false
	data["credits"] = credits() - amount
	_ledger(text, -amount)
	mark_dirty()
	return true


func _ledger(text: String, amount: int) -> void:
	data["ledger"].append({"day": int(data["day"]), "time": clock_text(), "text": text, "amount": amount})
	if data["ledger"].size() > 200:
		data["ledger"].pop_front()


# --- inventory ------------------------------------------------------------------------
func stock(id: String) -> int:
	return int(data["inventory"].get(id, 0))


func give(id: String, n: int = 1) -> void:
	data["inventory"][id] = stock(id) + n
	mark_dirty()


func take(id: String, n: int = 1) -> bool:
	if stock(id) < n:
		return false
	data["inventory"][id] = stock(id) - n
	if int(data["inventory"][id]) <= 0:
		data["inventory"].erase(id)
	mark_dirty()
	return true


func stored_count() -> int:
	var n := 0
	for id in data["inventory"]:
		n += int(data["inventory"][id])
	return n + data["salvage"].size()


func storage_cap() -> int:
	return int(level_info()["storage"]) + (40 if has_upgrade("extra_shelf") else 0)


func add_salvage(id: String, c: float) -> void:
	data["salvage"].append({"id": id, "cond": snappedf(c, 0.01)})
	mark_dirty()


func repair_cost(id: String, c: float) -> int:
	return maxi(int(ceil(float(Parts.part(id).get("price", 10)) * (1.0 - c) * 0.6)), 1)


func recycle_value(id: String, c: float) -> int:
	return int(float(Parts.part(id).get("price", 10)) * (0.1 + 0.25 * c))


func repair_salvage(i: int) -> bool:
	var s: Dictionary = data["salvage"][i]
	if float(s["cond"]) <= 0.0:
		notify.emit("Broken beyond repair - recycle it instead.", "bad")
		return false
	if not spend(repair_cost(s["id"], s["cond"]), "Repaired %s" % Parts.part(s["id"])["name"]):
		return false
	data["salvage"].remove_at(i)
	give(s["id"])
	set_flag("repaired")
	return true


func recycle_salvage(i: int) -> void:
	var s: Dictionary = data["salvage"][i]
	data["salvage"].remove_at(i)
	earn(recycle_value(s["id"], s["cond"]), "Recycled %s" % Parts.part(s["id"])["name"])


# --- market / deliveries ----------------------------------------------------------------
func part_available(id: String) -> bool:
	var p := Parts.part(id)
	if p.is_empty():
		return false
	return int(p.get("tier", 1)) <= level() or SaveData.is_unlocked(id) and int(p.get("tier", 1)) <= level() + 1


func price_of(id: String) -> int:
	var pr := int(Parts.part(id).get("price", 10))
	if has_upgrade("bulk_supplier"):
		pr = int(ceil(pr * 0.9))
	return pr


## Units the market has today (restocks every morning).
func market_stock(id: String) -> int:
	var base := 4 + absi(("%s%d" % [id, int(data["day"])]).hash()) % 14
	var bought: Dictionary = data.get("bought", {})
	if int(bought.get("day", -1)) != int(data["day"]):
		return base
	return maxi(base - int(bought.get(id, 0)), 0)


func _note_bought(id: String, n: int) -> void:
	if not data.has("bought") or int(data["bought"].get("day", -1)) != int(data["day"]):
		data["bought"] = {"day": int(data["day"])}
	data["bought"][id] = int(data["bought"].get(id, 0)) + n


func delivery_time(cart: Dictionary) -> float:
	var t := DELIVERY_BASE + 4.0 * cart.size()
	return t * (0.5 if has_upgrade("express_post") else 1.0)


## Places an order. Returns "" on success or the reason it failed.
func place_order(cart: Dictionary) -> String:
	var total := 0
	var count := 0
	for id in cart:
		if int(cart[id]) <= 0:
			continue
		if not part_available(id):
			return "%s is not stocked at your garage level." % Parts.part(id)["name"]
		if int(cart[id]) > market_stock(id):
			return "Only %d x %s in stock today." % [market_stock(id), Parts.part(id)["name"]]
		total += price_of(id) * int(cart[id])
		count += int(cart[id])
	if count == 0:
		return "The cart is empty."
	if stored_count() + count + _incoming_count() > storage_cap():
		return "Not enough storage space (%d / %d). Upgrade or sell salvage." % [stored_count() + _incoming_count(), storage_cap()]
	if total > credits():
		return "Not enough credits: %d cr needed." % total
	spend(total, "PARTS MARKET order (%d items)" % count)
	var items := {}
	for id in cart:
		if int(cart[id]) > 0:
			items[id] = int(cart[id])
			_note_bought(id, int(cart[id]))
	var eta: float = float(data["playtime"]) + delivery_time(items)
	data["orders"].append({"id": "ord%d" % int(Time.get_ticks_usec() % 1000000), "items": items, "cost": total, "eta": eta, "status": "transit"})
	notify.emit("Order placed: %d items, %d cr. Courier ETA %s." % [count, total, _fmt_s(eta - float(data["playtime"]))], "info")
	mark_dirty()
	return ""


func _incoming_count() -> int:
	var n := 0
	for o in data["orders"]:
		for id in o["items"]:
			n += int(o["items"][id])
	for p in data["parcels"]:
		if not p.get("opened", false):
			for id in p["items"]:
				n += int(p["items"][id])
	return n


## Called by the garage when the van has dropped a parcel for `order`.
func order_delivered(order: Dictionary, pos: Vector3) -> Dictionary:
	data["orders"].erase(order)
	var parcel := {"id": "p" + str(order["id"]), "label": "PARTS MARKET", "items": order["items"], "where": "floor", "pos": [pos.x, pos.y, pos.z], "opened": false}
	data["parcels"].append(parcel)
	mark_dirty()
	return parcel


func orders_due() -> Array:
	return data["orders"].filter(func(o): return o["status"] == "transit" and float(o["eta"]) <= float(data["playtime"]))


## Opens a parcel: its parts go into storage.
func open_parcel(parcel_id: String) -> Dictionary:
	for p in data["parcels"]:
		if p["id"] == parcel_id and not p.get("opened", false):
			p["opened"] = true
			for id in p["items"]:
				give(id, int(p["items"][id]))
			data["parcels"].erase(p)
			if parcel_id != "starter":
				set_flag("first_parcel")
			else:
				set_flag("starter_opened")
			Audio.play("box_open")
			mark_dirty()
			return p
	return {}


func parcel(parcel_id: String) -> Dictionary:
	for p in data["parcels"]:
		if p["id"] == parcel_id:
			return p
	return {}


# --- roster -------------------------------------------------------------------------------
func roster() -> Array:
	return data["roster"]


func get_drone(id: String) -> Dictionary:
	for d in data["roster"]:
		if d["id"] == id:
			return d
	return {}


func drone_name_suggestion() -> String:
	var a := ["Wasp", "Kite", "Hornet", "Sparrow", "Moth", "Falcon", "Shrike", "Magpie", "Swift", "Lark", "Raven", "Gadfly"]
	return "%s-%02d" % [a[int(data["next_no"]) % a.size()], int(data["next_no"])]


## Saves the drone on the workbench into the roster (new or existing entry). Clears the bench.
func store_bench_drone(name: String) -> Dictionary:
	var id: String = data["bench_drone"]
	var d := get_drone(id)
	if d.is_empty():
		id = "d%d" % int(data["next_no"])
		data["next_no"] = int(data["next_no"]) + 1
		d = {"id": id, "created_day": int(data["day"]), "missions": 0, "targets": 0, "charge": 1.0, "battery_in": true}
		data["roster"].append(d)
		data["stats"]["drones_built"] = int(data["stats"]["drones_built"]) + 1
	var prev_placed: Dictionary = d.get("placed", {})
	d["name"] = name if name.strip_edges() != "" else drone_name_suggestion()
	d["placed"] = Game.placed.duplicate()
	d["broken"] = Game.broken.duplicate()
	d["cond"] = Game.cond.duplicate()
	d["wires"] = Game.wires.duplicate()
	d["cfg"] = Game.cfg.duplicate(true)
	d["paint"] = [Game.paint.r, Game.paint.g, Game.paint.b, Game.paint.a]
	d["location"] = "rack"
	# a changed build has to be re-certified on the test station
	if prev_placed != d["placed"] or not d.has("certified"):
		d["certified"] = false
	if prev_placed.get("battery", "") != d["placed"].get("battery", ""):
		d["charge"] = Game.bench_charge
	d["battery_in"] = true
	if data["active_drone"] == "":
		data["active_drone"] = id
	data["bench_drone"] = ""
	Game.reset_build()
	mark_dirty()
	save()
	return d


## Moves a roster drone onto the workbench (replacing whatever is there, which is stored first).
func move_to_bench(id: String) -> bool:
	var d := get_drone(id)
	if d.is_empty():
		return false
	if not Game.placed.is_empty() and data["bench_drone"] != id:
		store_bench_drone(Game.bench_name if Game.bench_name != "" else drone_name_suggestion())
	data["bench_drone"] = id
	undock(id)
	d["location"] = "bench"
	Game.placed = d["placed"].duplicate()
	Game.broken = d["broken"].duplicate()
	Game.cond = d["cond"].duplicate()
	Game.wires = d["wires"].duplicate()
	Game.cfg = FlightMath.default_cfg()
	Game._merge_cfg(Game.cfg, d["cfg"])
	Game.loose = {}
	Game.paint = paint_of(d)
	Game.bench_name = d["name"]
	Game.bench_charge = float(d.get("charge", 1.0))
	Game.save_drone()
	mark_dirty()
	return true


func paint_of(d: Dictionary) -> Color:
	var p: Array = d.get("paint", [])
	if p.size() >= 4:
		return Color(p[0], p[1], p[2], p[3])
	return Color(0, 0, 0, 0)


func remove_drone(id: String) -> void:
	var d := get_drone(id)
	if d.is_empty():
		return
	undock(id)
	data["roster"].erase(d)
	if data["active_drone"] == id:
		data["active_drone"] = data["roster"][0]["id"] if not data["roster"].is_empty() else ""
	mark_dirty()


## Strips a roster drone into parts: good ones to storage, damaged ones to salvage.
func disassemble(id: String) -> void:
	var d := get_drone(id)
	if d.is_empty():
		return
	for slot in d["placed"]:
		var pid: String = d["placed"][slot]
		var c: float = 0.0 if d["broken"].get(slot, false) else float(d["cond"].get(slot, 1.0))
		if c >= 0.9:
			give(pid)
		else:
			add_salvage(pid, c)
	remove_drone(id)
	notify.emit("%s disassembled - parts moved to storage / salvage." % d["name"], "info")


func active_drone() -> Dictionary:
	return get_drone(data["active_drone"])


func rack_drones() -> Array:
	return data["roster"].filter(func(d): return d["location"] in ["rack"])


func drone_stats(d: Dictionary) -> Dictionary:
	return Parts.compute_build(d.get("placed", {}), d.get("broken", {}), d.get("cond", {}))


## Can this roster drone be deployed? "" = yes.
func deploy_check(d: Dictionary) -> String:
	if d.is_empty():
		return "No drone selected."
	var st := drone_stats(d)
	if not st.get("complete", false):
		return "%s is incomplete: %s." % [d["name"], st["missing_text"]]
	if st["broken_props"] > 0:
		return "%s has broken props." % d["name"]
	if Parts.missing_wires(d.get("wires", [])).size() > 0:
		return "%s is not fully wired." % d["name"]
	if not d.get("battery_in", true):
		return "%s has no battery fitted (it's on the charger)." % d["name"]
	if float(d.get("charge", 1.0)) < 0.25:
		return "%s's battery is nearly flat (%d %%) - charge it first." % [d["name"], int(float(d["charge"]) * 100.0)]
	if not d.get("certified", false):
		return "%s has not passed diagnostics yet - connect it to the test station." % d["name"]
	if d["location"] == "bench":
		return "%s is on the workbench - save it first." % d["name"]
	return ""


# --- charging -------------------------------------------------------------------------------
func dock_count() -> int:
	return int(level_info()["docks"])


func dock_battery(drone_id: String) -> int:
	var docks: Array = data["docks"]
	while docks.size() < dock_count():
		docks.append("")
	if docks.has(drone_id):
		return docks.find(drone_id)
	for i in dock_count():
		if docks[i] == "":
			docks[i] = drone_id
			var d := get_drone(drone_id)
			d["battery_in"] = false
			mark_dirty()
			return i
	return -1


func undock(drone_id: String) -> void:
	var docks: Array = data["docks"]
	for i in docks.size():
		if docks[i] == drone_id:
			docks[i] = ""
			var d := get_drone(drone_id)
			if not d.is_empty():
				d["battery_in"] = true
			mark_dirty()


func charge_rate() -> float:
	return CHARGE_RATE * (2.0 if has_upgrade("fast_charger") else 1.0) * (1.5 if level() >= 5 else 1.0)


# --- production -------------------------------------------------------------------------------
func save_preset(name: String, placed: Dictionary, cfg: Dictionary) -> void:
	for p in data["presets"]:
		if p["name"] == name:
			p["placed"] = placed.duplicate()
			p["cfg"] = cfg.duplicate(true)
			mark_dirty()
			return
	data["presets"].append({"name": name, "placed": placed.duplicate(), "cfg": cfg.duplicate(true)})
	mark_dirty()


func preset_parts(placed: Dictionary) -> Dictionary:
	var need := {}
	for slot in placed:
		need[placed[slot]] = int(need.get(placed[slot], 0)) + 1
	return need


func missing_for(placed: Dictionary, qty: int) -> Dictionary:
	var miss := {}
	var need := preset_parts(placed)
	for id in need:
		var short: int = int(need[id]) * qty - stock(id)
		if short > 0:
			miss[id] = short
	return miss


func add_job(preset_name: String, qty: int, auto: bool) -> String:
	var preset := {}
	for p in data["presets"]:
		if p["name"] == preset_name:
			preset = p
	if preset.is_empty():
		return "Unknown preset."
	if auto and level() < 3:
		return "The automated assembly station unlocks at garage level 3."
	data["jobs"].append({"preset": preset_name, "qty": qty, "done": 0, "auto": auto, "progress": 0.0})
	mark_dirty()
	return ""


func assembly_time() -> float:
	return 40.0 / (2.0 if has_upgrade("assembly_speed") else 1.0) / (1.5 if level() >= 4 else 1.0)


## Builds one drone of a preset straight into the roster (automated assembly). Returns "" on success.
func auto_build(preset: Dictionary) -> String:
	var miss := missing_for(preset["placed"], 1)
	if not miss.is_empty():
		return "Missing parts: " + ", ".join(miss.keys().map(func(k): return "%s x%d" % [Parts.part(k)["name"], miss[k]]))
	if rack_drones().size() >= int(level_info()["rack"]):
		return "The drone rack is full."
	var need := preset_parts(preset["placed"])
	for id in need:
		take(id, int(need[id]))
	var id := "d%d" % int(data["next_no"])
	data["next_no"] = int(data["next_no"]) + 1
	var cfg := FlightMath.default_cfg()
	Game._merge_cfg(cfg, preset.get("cfg", {}))
	var d := {"id": id, "name": "%s #%d" % [preset["name"], int(data["next_no"]) - 1], "placed": preset["placed"].duplicate(), "broken": {}, "cond": {},
		"wires": Parts.WIRES.keys(), "cfg": cfg, "paint": [], "charge": 1.0, "battery_in": true, "location": "rack", "certified": true,
		"created_day": int(data["day"]), "missions": 0, "targets": 0}
	data["roster"].append(d)
	data["stats"]["drones_built"] = int(data["stats"]["drones_built"]) + 1
	mark_dirty()
	return ""


## A drone just saved on the bench may count towards a manual production job.
func credit_manual_job(d: Dictionary) -> void:
	for j in data["jobs"]:
		if j["auto"] or int(j["done"]) >= int(j["qty"]):
			continue
		for p in data["presets"]:
			if p["name"] == j["preset"] and p["placed"] == d["placed"]:
				j["done"] = int(j["done"]) + 1
				notify.emit("Production order '%s': %d / %d built." % [j["preset"], j["done"], j["qty"]], "good")
				mark_dirty()
				return


# --- contracts ------------------------------------------------------------------------------------
func _refresh_contracts() -> void:
	var open: Array = data["contracts"].filter(func(c): return not c.get("delivered", false))
	if open.size() >= 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data["day"]) * 7919 + int(data["stats"]["contracts"]) * 31 + data["contracts"].size()
	var pool: Array = Campaign.CONTRACT_TEMPLATES.filter(func(t): return int(t["level"]) <= level())
	var guard := 0
	while open.size() < 3 and guard < 20:
		guard += 1
		var t: Dictionary = pool[rng.randi() % pool.size()]
		if open.any(func(c): return c["customer"] == t["customer"]):
			continue
		var qty: int = rng.randi_range(t["qty"][0], t["qty"][1])
		var base_cost: float = 330.0 + 60.0 * t["req"].size()
		var c := {"id": "c%d_%d" % [int(data["day"]), rng.randi() % 100000], "customer": t["customer"], "kind": t["kind"], "req": t["req"], "text": t["text"],
			"qty": qty, "delivered_n": 0, "pay": int(base_cost * float(t["margin"]) / 10.0) * 10, "rep": 1, "deadline": int(data["day"]) + 3 + qty, "delivered": false}
		data["contracts"].append(c)
		open.append(c)


func open_contracts() -> Array:
	return data["contracts"].filter(func(c): return not c.get("delivered", false))


func deliver_to_contract(contract_id: String, drone_id: String) -> String:
	var c := {}
	for x in data["contracts"]:
		if x["id"] == contract_id:
			c = x
	var d := get_drone(drone_id)
	if c.is_empty() or d.is_empty():
		return "Unknown contract or drone."
	var why := Campaign.contract_check(c, d)
	if why != "":
		return why
	remove_drone(drone_id)
	c["delivered_n"] = int(c["delivered_n"]) + 1
	earn(int(c["pay"]), "%s: %s delivered (%s)" % [c["customer"], c["kind"], d["name"]])
	if int(c["delivered_n"]) >= int(c["qty"]):
		c["delivered"] = true
		data["rep"] = int(data["rep"]) + int(c["rep"])
		data["stats"]["contracts"] = int(data["stats"]["contracts"]) + 1
		set_flag("contract_done")
		notify.emit("Contract complete for %s! +%d reputation." % [c["customer"], c["rep"]], "good")
		_refresh_contracts()
	Audio.play("cash")
	mark_dirty()
	save()
	return ""


# --- garage level / upgrades ---------------------------------------------------------------------------
func level() -> int:
	return int(data["level"])


func level_info(l: int = -1) -> Dictionary:
	if l < 0:
		l = level()
	return Campaign.LEVELS[clampi(l, 1, Campaign.LEVELS.size()) - 1]


func has_upgrade(id: String) -> bool:
	return data["upgrades"].get(id, false)


func buy_upgrade(id: String) -> String:
	var u: Dictionary = Campaign.UPGRADES.get(id, {})
	if u.is_empty() or has_upgrade(id):
		return "Already installed."
	if level() < int(u["level"]):
		return "Needs garage level %d." % u["level"]
	if not spend(int(u["cost"]), "Upgrade: %s" % u["name"]):
		return "Not enough credits."
	data["upgrades"][id] = true
	Audio.play("cash")
	save()
	return ""


func upgrade_level() -> String:
	if level() >= Campaign.LEVELS.size():
		return "Already at the top level."
	var nxt := level_info(level() + 1)
	if int(data["rep"]) < int(nxt["rep"]):
		return "Needs %d reputation (you have %d). Complete missions and contracts." % [nxt["rep"], data["rep"]]
	if not spend(int(nxt["cost"]), "Garage expansion: %s" % nxt["name"]):
		return "Not enough credits."
	data["level"] = level() + 1
	_refresh_contracts()
	notify.emit("Garage upgraded to Level %d - %s!" % [level(), nxt["name"]], "good")
	Audio.play("success")
	save()
	return ""


# --- missions ------------------------------------------------------------------------------------------
func mission_unlocked(m: Dictionary) -> bool:
	for r in m.get("requires", []):
		if not data["missions_done"].has(r):
			return false
	return true


func mission_count(id: String) -> int:
	return int(data["missions_done"].get(id, 0))


## Pays out a finished mission. Returns the credits earned.
func complete_mission(m: Dictionary, bonus: int) -> int:
	var first := mission_count(m["id"]) == 0
	var pay: int = int(m["reward"]) if first else int(m["repeat_reward"])
	pay += bonus
	data["missions_done"][m["id"]] = mission_count(m["id"]) + 1
	if first:
		data["rep"] = int(data["rep"]) + int(m["rep"])
	if pay > 0:
		earn(pay, "Mission: %s" % m["name"])
	advance_clock(120.0)
	save()
	return pay


func advance_clock(minutes: float) -> void:
	data["clock"] = float(data["clock"]) + minutes
	while float(data["clock"]) >= 1440.0:
		data["clock"] = float(data["clock"]) - 1440.0
		data["day"] = int(data["day"]) + 1
		_refresh_contracts()


func clock_text() -> String:
	var m := int(data["clock"])
	return "%02d:%02d" % [m / 60, m % 60]


func set_flag(f: String) -> void:
	if not data["flags"].get(f, false):
		data["flags"][f] = true
		mark_dirty()


func flag(f: String) -> bool:
	return data["flags"].get(f, false)


# --- career guide ------------------------------------------------------------------------------------------
const GUIDE := [
	"Open the cupboard under the workbench (E) and pick up the STARTER KIT box (F).",
	"Open the starter kit (hold it and press E, or press E on it): the parts go into storage.",
	"Use the WORKBENCH (E). Assemble a drone from your parts and tighten every screw.",
	"Wire it, check SETUP, then press SAVE DRONE - name it and it goes on the rack.",
	"Pick the drone up from the rack (F) and connect it to the TEST STATION (E) to run diagnostics.",
	"Open the garage door and use the TEST PAD outside to fly the Shakedown test flight.",
	"At the computer open DEPLOYMENT MAP and fly 'Training Range: Static Targets'.",
	"Order parts in PARTS MARKET, then collect the parcel the van drops on the driveway and open it inside.",
	"Repair or replace any damaged part at the workbench (or repair salvage in INVENTORY).",
	"Deliver a customer contract in FACTORY ORDERS, or fly 'Eyes on the Road'.",
	"Expand the business: buy garage Level 2 in GARAGE UPGRADES.",
]


func guide_text() -> String:
	var s := int(data["tutorial"])
	if s >= GUIDE.size():
		return ""
	return GUIDE[s]


func _guide_done(step: int) -> bool:
	match step:
		0: return flag("starter_picked") or flag("starter_opened")
		1: return flag("starter_opened")
		2: return (Game.stats()["complete"] and Game.loose.is_empty()) or not data["roster"].is_empty()
		3: return not data["roster"].is_empty()
		4: return data["roster"].any(func(d): return d.get("certified", false))
		5: return data["missions_done"].has("shakedown")
		6: return data["missions_done"].has("range_static")
		7: return flag("first_parcel")
		8: return flag("repaired")
		9: return flag("contract_done") or data["missions_done"].has("eyes_road")
		10: return level() >= 2
	return true


# --- tick ----------------------------------------------------------------------------------------------------
func _process(dt: float) -> void:
	if data.is_empty():
		return
	data["playtime"] = float(data["playtime"]) + dt
	# in-world clock: 1 real second = 1 game minute while in the garage or on the bench
	if Game.screen in ["garage", "workshop"]:
		advance_clock(dt)
	# docks
	var docks: Array = data["docks"]
	for i in docks.size():
		if docks[i] != "":
			var d := get_drone(docks[i])
			if d.is_empty():
				docks[i] = ""
				continue
			var before := float(d["charge"])
			d["charge"] = minf(before + charge_rate() * dt, 1.0)
			if before < 1.0 and float(d["charge"]) >= 1.0:
				notify.emit("%s's battery is fully charged." % d["name"], "good")
				Audio.play("beep")
	# 3D printer
	var pr: Dictionary = data["printer"]
	if pr.has("item"):
		pr["t"] = float(pr["t"]) - dt
		if float(pr["t"]) <= 0.0:
			give(pr["item"])
			notify.emit("3D print finished: %s (added to storage)." % Parts.part(pr["item"])["name"], "good")
			Audio.play("success")
			data["printer"] = {}
	# automated assembly
	if level() >= 3:
		for j in data["jobs"]:
			if not j["auto"] or int(j["done"]) >= int(j["qty"]):
				continue
			j["progress"] = float(j["progress"]) + dt
			if float(j["progress"]) >= assembly_time():
				j["progress"] = 0.0
				var preset := {}
				for p in data["presets"]:
					if p["name"] == j["preset"]:
						preset = p
				var err := "Preset missing." if preset.is_empty() else auto_build(preset)
				if err == "":
					j["done"] = int(j["done"]) + 1
					notify.emit("Assembly station finished a '%s' (%d / %d)." % [j["preset"], j["done"], j["qty"]], "good")
				else:
					j["progress"] = assembly_time() * 0.5
					if not j.get("warned", false):
						notify.emit("Assembly station stalled: %s" % err, "bad")
						j["warned"] = true
			break
	# guide
	_tut_t += dt
	if _tut_t > 0.5:
		_tut_t = 0.0
		var s := int(data["tutorial"])
		var moved := false
		while s < GUIDE.size() and _guide_done(s):
			s += 1
			moved = true
		if moved:
			data["tutorial"] = s
			if s < GUIDE.size():
				notify.emit("Next: " + GUIDE[s], "guide")
			else:
				notify.emit("Career guide complete - the business is yours to grow.", "good")
			mark_dirty()
	_autosave_t += dt
	if _autosave_t > AUTOSAVE_S and _dirty:
		_autosave_t = 0.0
		save()


func start_print(id: String) -> String:
	var p := Parts.part(id)
	if not p.has("print"):
		return "That part can't be printed."
	if data["printer"].has("item"):
		return "The printer is busy."
	if level() < 2:
		return "The 3D printer arrives with garage level 2."
	if not spend(int(p["print"]), "Filament: %s" % p["name"]):
		return "Not enough credits."
	data["printer"] = {"item": id, "t": 25.0 + float(p["print"]) * 4.0, "total": 25.0 + float(p["print"]) * 4.0}
	Audio.play("printer")
	mark_dirty()
	return ""


func _fmt_s(s: float) -> String:
	s = maxf(s, 0.0)
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func eta_text(o: Dictionary) -> String:
	return _fmt_s(float(o["eta"]) - float(data["playtime"]))
