class_name Tablet
extends Control
## Handheld workshop tablet (Q / touchpad): business status, career guide, deliveries,
## charging, production, and the inventory / salvage (Tab / Triangle).

signal closed

var start_tab := "status"
var garage: Node
var _tabs: TabContainer


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var frame := PanelContainer.new()
	frame.position = Vector2(360, 110)
	frame.size = Vector2(1200, 860)
	frame.add_theme_stylebox_override("panel", UITheme.flat(Color(0.05, 0.05, 0.06), 28, Color(0.25, 0.25, 0.28), 10, 26))
	add_child(frame)
	var v := VBoxContainer.new()
	frame.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UITheme.label("WORKSHOP TABLET", 26, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UITheme.label("%d cr   Day %d  %s" % [Career.credits(), int(Career.data["day"]), Career.clock_text()], 22))
	if garage and garage.has_method("open_help"):
		top.add_child(UITheme.button("How to play", func(): garage.call_deferred("open_help", 0), Vector2(170, 40)))
	top.add_child(UITheme.button("Close", func(): closed.emit(), Vector2(120, 40)))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_tabs.add_child(_status_tab())
	_tabs.add_child(_inventory_tab())
	_tabs.add_child(_drones_tab())
	_tabs.current_tab = {"status": 0, "inventory": 1, "drones": 2}.get(start_tab, 0)
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	Pad.focus_first(self)
	if Pad.using_pad:
		_tabs.get_tab_bar().grab_focus()


func _scroll(name_: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	return [sc, vb]


func _line(vb: VBoxContainer, text: String, size: int = 19, col: Color = UITheme.TEXT) -> Label:
	var l := UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1080, 0)
	vb.add_child(l)
	return l


func _status_tab() -> Control:
	var r := _scroll("Status")
	var vb: VBoxContainer = r[1]
	var li := Career.level_info()
	_line(vb, "Level %d - %s   •   Reputation %d   •   Credits %d" % [Career.level(), li["name"], int(Career.data["rep"]), Career.credits()], 22, UITheme.ACCENT)
	var g := Career.guide_text()
	if g != "":
		_line(vb, "CAREER GUIDE  (step %d / %d)" % [int(Career.data["tutorial"]) + 1, Career.GUIDE.size()], 20, UITheme.ACCENT)
		_line(vb, g)
	_line(vb, "")
	_line(vb, "DELIVERIES", 20, UITheme.ACCENT)
	if Career.data["orders"].is_empty() and Career.data["parcels"].is_empty():
		_line(vb, "Nothing on the way.", 18, UITheme.MUTED)
	for o in Career.data["orders"]:
		var n := 0
		for id in o["items"]:
			n += int(o["items"][id])
		_line(vb, "Order of %d items (%d cr) - ETA %s" % [n, o["cost"], Career.eta_text(o)])
	for p in Career.data["parcels"]:
		_line(vb, "Unopened parcel: %s (%s)" % [p.get("label", "Parcel"), "in the bench cupboard" if p.get("where", "") == "cupboard" else "in the garage / driveway"])
	_line(vb, "")
	_line(vb, "CHARGING DOCKS (%d)" % Career.dock_count(), 20, UITheme.ACCENT)
	for i in Career.dock_count():
		var id: String = Career.data["docks"][i] if i < Career.data["docks"].size() else ""
		var d := Career.get_drone(id)
		_line(vb, "Dock %d: %s" % [i + 1, "empty" if d.is_empty() else "%s - %d %%" % [d["name"], int(float(d["charge"]) * 100.0)]])
	if Career.data["printer"].has("item"):
		_line(vb, "3D printer: %s, %d s left" % [Parts.part(Career.data["printer"]["item"])["name"], int(Career.data["printer"]["t"])])
	if not Career.data["jobs"].is_empty():
		_line(vb, "")
		_line(vb, "PRODUCTION", 20, UITheme.ACCENT)
		for j in Career.data["jobs"]:
			_line(vb, "%s x%d - %d done%s" % [j["preset"], j["qty"], j["done"], " (automated)" if j["auto"] else " (build at the bench)"])
	_line(vb, "")
	_line(vb, "CONTROLS", 20, UITheme.ACCENT)
	_line(vb, "Walk %s/%s/%s/%s  •  Interact %s  •  Pick up / put down %s  •  Place %s  •  Rotate held item: hold %s  •  Inspect %s  •  Sprint %s  •  Crouch %s" % [
		Pad.glyph("move_forward"), Pad.glyph("move_left"), Pad.glyph("move_back"), Pad.glyph("move_right"), Pad.glyph("use"), Pad.glyph("pickup"), Pad.glyph("place"),
		Pad.glyph("rotate_item"), Pad.glyph("secondary"), Pad.glyph("sprint"), Pad.glyph("crouch")], 17, UITheme.MUTED)
	return r[0]


func _inventory_tab() -> Control:
	var r := _scroll("Inventory")
	var vb: VBoxContainer = r[1]
	_line(vb, "STORAGE  %d / %d" % [Career.stored_count(), Career.storage_cap()], 20, UITheme.ACCENT)
	for cat in Parts.CATEGORIES:
		var items: Array = []
		for id in Parts.parts_in(cat):
			if Career.stock(id) > 0:
				items.append("%d x %s" % [Career.stock(id), Parts.part(id)["name"]])
		if not items.is_empty():
			_line(vb, "%s:  %s" % [Parts.CAT_NAMES[cat], ",   ".join(items)])
	_line(vb, "")
	_line(vb, "SALVAGE BIN (damaged parts)", 20, UITheme.ACCENT)
	if Career.data["salvage"].is_empty():
		_line(vb, "Empty.", 18, UITheme.MUTED)
	for i in Career.data["salvage"].size():
		var s: Dictionary = Career.data["salvage"][i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		vb.add_child(h)
		var l := UITheme.label("%s  -  %d %%" % [Parts.part(s["id"])["name"], int(float(s["cond"]) * 100.0)], 18)
		l.custom_minimum_size = Vector2(560, 0)
		h.add_child(l)
		var idx: int = i
		if float(s["cond"]) > 0.0:
			h.add_child(UITheme.button("Repair (%d cr)" % Career.repair_cost(s["id"], s["cond"]), func():
				Career.repair_salvage(idx)
				_rebuild(1), Vector2(190, 36)))
		h.add_child(UITheme.button("Recycle (+%d cr)" % Career.recycle_value(s["id"], s["cond"]), func():
			Career.recycle_salvage(idx)
			_rebuild(1), Vector2(190, 36)))
	return r[0]


func _drones_tab() -> Control:
	var r := _scroll("Drones")
	var vb: VBoxContainer = r[1]
	if Career.roster().is_empty():
		_line(vb, "No drones yet - build one at the workbench.", 19, UITheme.MUTED)
	for d in Career.roster():
		var st := Career.drone_stats(d)
		var star := "★ " if Career.data["active_drone"] == d["id"] else ""
		_line(vb, "%s%s  [%s]  %s  -  battery %d %%  -  %s" % [star, d["name"], d["location"], "certified" if d.get("certified", false) else "NOT certified",
			int(float(d.get("charge", 1.0)) * 100.0), "TWR %.1f, %.1f min" % [st.get("twr", 0.0), st.get("endurance_min", 0.0)] if st.has("twr") else "incomplete"],
			19, UITheme.GOOD if d.get("certified", false) else UITheme.TEXT)
	return r[0]


func _rebuild(tab: int) -> void:
	var old := _tabs.get_child(tab)
	var n: Control = [_status_tab, _inventory_tab, _drones_tab][tab].call()
	_tabs.add_child(n)
	_tabs.move_child(n, tab)
	old.queue_free()
	_tabs.current_tab = tab
