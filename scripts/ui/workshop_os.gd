class_name WorkshopOS
extends Control
## WORKSHOP OS: the garage computer's desktop and its applications.
## Everything is built from focusable Controls, so it works with mouse, keyboard or a
## DualSense (D-pad / left stick to move, Cross to select, Circle to go back).

const APPS := [
	{"id": "market", "name": "PARTS MARKET", "icon": "PM", "color": Color(0.95, 0.55, 0.12)},
	{"id": "drones", "name": "DRONE MANAGER", "icon": "DM", "color": Color(0.35, 0.7, 1.0)},
	{"id": "factory", "name": "FACTORY ORDERS", "icon": "FO", "color": Color(0.9, 0.8, 0.2)},
	{"id": "deploy", "name": "DEPLOYMENT MAP", "icon": "DP", "color": Color(0.9, 0.3, 0.25)},
	{"id": "inventory", "name": "INVENTORY", "icon": "IN", "color": Color(0.55, 0.8, 0.45)},
	{"id": "diag", "name": "DIAGNOSTICS", "icon": "DG", "color": Color(0.4, 1.0, 0.6)},
	{"id": "finance", "name": "FINANCES", "icon": "$", "color": Color(0.5, 0.9, 0.8)},
	{"id": "upgrades", "name": "GARAGE UPGRADES", "icon": "UP", "color": Color(0.75, 0.55, 1.0)},
	{"id": "settings", "name": "SETTINGS", "icon": "ST", "color": Color(0.7, 0.72, 0.76)},
]
const MONO := Color(0.78, 0.86, 0.8)

var garage: Node          # Garage (for launching missions / closing)
var start_app := ""
var _desk: Control
var _win: PanelContainer
var _win_title: Label
var _win_body: Control
var _clock: Label
var _app := ""
var _cart: Dictionary = {}
var _market_cat := "frame"
var _market_sel := "frame_5"
var _drone_sel := ""
var _compare_sel := ""
var _mission_sel := ""
var _deploy_drone := ""
var _factory_tab := 0
var _job_preset := ""
var _job_qty := 1
var _job_auto := false
var _diag_sel := ""
var _preview_vp: SubViewport
var _preview_pivot: Node3D


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_desktop()
	Audio.play("beep", 0.8)
	if start_app != "":
		open_app(start_app)
	else:
		Pad.focus_first(_desk, true)


## Esc / Circle: close the open app first; returns true when handled.
func back() -> bool:
	if _app != "":
		close_app()
		return true
	return false


func _process(dt: float) -> void:
	if _clock:
		_clock.text = "%d cr    Day %d  %s" % [Career.credits(), int(Career.data["day"]), Career.clock_text()]
	if _preview_pivot and is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y += dt * 0.7


# =====================================================================================
# desktop
# =====================================================================================
func _build_desktop() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.08, 0.09)
	add_child(bg)
	var grid_bg := Control.new()
	grid_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_bg.draw.connect(func():
		for x in range(0, 1920, 48):
			grid_bg.draw_line(Vector2(x, 0), Vector2(x, 1080), Color(0.2, 0.4, 0.35, 0.08))
		for y in range(0, 1080, 48):
			grid_bg.draw_line(Vector2(0, y), Vector2(1920, y), Color(0.2, 0.4, 0.35, 0.08))
		grid_bg.draw_string(ThemeDB.fallback_font, Vector2(1240, 980), "WORKSHOP OS 2.4", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.3, 0.6, 0.5, 0.18)))
	add_child(grid_bg)
	_desk = Control.new()
	_desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	_desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desk)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(80, 70)
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 26)
	_desk.add_child(grid)
	for a in APPS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 150)
		b.focus_mode = Control.FOCUS_ALL
		b.text = "\n\n\n" + a["name"]
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", UITheme.flat(Color(0.08, 0.12, 0.12, 0.9), 6, Color(a["color"], 0.35), 1, 10))
		b.add_theme_stylebox_override("hover", UITheme.flat(Color(0.12, 0.18, 0.17, 0.95), 6, a["color"], 2, 10))
		b.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 6, a["color"], 3, 10))
		var icon := Label.new()
		icon.text = a["icon"]
		icon.add_theme_font_size_override("font_size", 46)
		icon.add_theme_color_override("font_color", a["color"])
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.position = Vector2(0, 18)
		icon.size = Vector2(250, 60)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var id: String = a["id"]
		b.pressed.connect(func():
			Audio.play("click")
			open_app(id))
		grid.add_child(b)
	# notifications panel on the desktop
	var np := PanelContainer.new()
	np.position = Vector2(950, 70)
	np.custom_minimum_size = Vector2(880, 0)
	np.add_theme_stylebox_override("panel", UITheme.flat(Color(0.06, 0.1, 0.1, 0.92), 6, Color(0.3, 0.6, 0.5, 0.4), 1, 16))
	_desk.add_child(np)
	var nv := VBoxContainer.new()
	np.add_child(nv)
	nv.add_child(_mono("STATUS", 22, UITheme.ACCENT))
	nv.add_child(_mono("%s - Level %d %s  •  Reputation %d" % [Campaign.FACTION_PLAYER, Career.level(), Career.level_info()["name"], int(Career.data["rep"])], 18))
	var g := Career.guide_text()
	if g != "":
		var gl := _mono("Guide: " + g, 18, UITheme.ACCENT)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.custom_minimum_size = Vector2(840, 0)
		nv.add_child(gl)
	nv.add_child(_mono("Drones %d  •  Deliveries in transit %d  •  Open contracts %d  •  Storage %d / %d" % [Career.roster().size(), Career.data["orders"].size(), Career.open_contracts().size(), Career.stored_count(), Career.storage_cap()], 18))
	for e in Career.data["ledger"].slice(-5):
		nv.add_child(_mono("  %s  %+d cr  %s" % [e.get("time", ""), int(e["amount"]), e["text"]], 16, UITheme.MUTED))
	# taskbar
	var bar := PanelContainer.new()
	bar.position = Vector2(0, 1030)
	bar.size = Vector2(1920, 50)
	bar.add_theme_stylebox_override("panel", UITheme.flat(Color(0.02, 0.03, 0.035, 0.98), 0, Color(0.3, 0.6, 0.5, 0.3), 1, 10))
	add_child(bar)
	var hb := HBoxContainer.new()
	bar.add_child(hb)
	hb.add_child(_mono("◆ WORKSHOP OS", 20, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	_clock = _mono("", 20)
	hb.add_child(_clock)
	var off := UITheme.button("Log off", func(): _close_os(), Vector2(130, 36))
	hb.add_child(off)
	# window
	_win = PanelContainer.new()
	_win.position = Vector2(40, 30)
	_win.size = Vector2(1840, 990)
	_win.add_theme_stylebox_override("panel", UITheme.flat(Color(0.075, 0.085, 0.095, 0.99), 6, Color(0.3, 0.6, 0.5, 0.5), 2, 14))
	_win.visible = false
	add_child(_win)
	var wv := VBoxContainer.new()
	_win.add_child(wv)
	var th := HBoxContainer.new()
	wv.add_child(th)
	_win_title = _mono("", 26, UITheme.ACCENT)
	th.add_child(_win_title)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp2)
	th.add_child(UITheme.button("✕  Close app", close_app, Vector2(170, 38)))
	var holder := MarginContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wv.add_child(holder)
	_win_body = holder


func _close_os() -> void:
	if garage and garage.has_method("close_overlay"):
		garage.close_overlay()
	else:
		queue_free()


func _mono(text: String, size: int = 18, col: Color = MONO) -> Label:
	var l := UITheme.label(text, size, col)
	return l


func open_app(id: String) -> void:
	_app = id
	_desk.visible = false
	_win.visible = true
	for a in APPS:
		if a["id"] == id:
			_win_title.text = "▣ " + a["name"]
	_refresh()


func close_app() -> void:
	_app = ""
	_win.visible = false
	_desk.visible = true
	_preview_pivot = null
	for c in _win_body.get_children():
		c.queue_free()
	Pad.focus_first(_desk)


func _refresh() -> void:
	for c in _win_body.get_children():
		_win_body.remove_child(c)
		c.queue_free()
	_preview_pivot = null
	var body: Control
	match _app:
		"market": body = _app_market()
		"drones": body = _app_drones()
		"factory": body = _app_factory()
		"deploy": body = _app_deploy()
		"inventory": body = _app_inventory()
		"diag": body = _app_diag()
		"finance": body = _app_finance()
		"upgrades": body = _app_upgrades()
		"settings": body = _app_settings()
		_: body = Control.new()
	_win_body.add_child(body)
	Pad.focus_first(body)


# --- small widgets ---------------------------------------------------------------------
func _col(min_w: float, expand: bool = false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(min_w, 0)
	v.add_theme_constant_override("separation", 6)
	if expand:
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _scroll_col(min_w: float, expand: bool = false) -> Array:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(min_w, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if expand:
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _col(min_w - 20)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return [sc, v]


func _wrap(text: String, w: float, size: int = 18, col: Color = MONO) -> Label:
	var l := _mono(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l


func _sel_button(text: String, selected: bool, cb: Callable, w: float = 300.0) -> Button:
	var b := UITheme.button(text, cb, Vector2(w, 40))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	if selected:
		b.add_theme_stylebox_override("normal", UITheme.flat(Color(0.28, 0.2, 0.08), 6, UITheme.ACCENT, 2, 12))
	return b


func _stars(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(maxi(5 - n, 0))


## A small rotating 3D preview (part or whole drone).
func _preview(model: Node3D, radius: float, size: Vector2) -> Control:
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = size
	svc.stretch = true
	_preview_vp = SubViewport.new()
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	_preview_vp.size = Vector2i(size)
	svc.add_child(_preview_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_preview_vp.add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-50, 30, 0)
	_preview_vp.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 35
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(0, radius * 1.4, radius * 2.6)).looking_at(Vector3.ZERO, Vector3.UP)
	_preview_vp.add_child(cam)
	_preview_pivot = Node3D.new()
	_preview_vp.add_child(_preview_pivot)
	_preview_pivot.add_child(model)
	for lb in model.find_children("*", "Label3D", true, false):
		lb.visible = false
	return svc


# =====================================================================================
# PARTS MARKET
# =====================================================================================
func _app_market() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var cats := _col(220)
	cats.add_child(_mono("CATEGORIES", 18, UITheme.ACCENT))
	for c in Parts.CATEGORIES:
		var cc: String = c
		cats.add_child(_sel_button(Parts.CAT_NAMES[c], c == _market_cat, func():
			_market_cat = cc
			var ids := Parts.parts_in(cc)
			_market_sel = ids[0] if not ids.is_empty() else ""
			_refresh(), 210))
	h.add_child(cats)
	# product list
	var r := _scroll_col(760)
	var list: VBoxContainer = r[1]
	list.add_child(_mono("PRODUCTS  -  %s" % Parts.CAT_NAMES[_market_cat], 18, UITheme.ACCENT))
	var ids := Parts.parts_in(_market_cat)
	ids.sort_custom(func(a, b): return Parts.part(a)["price"] < Parts.part(b)["price"])
	for id in ids:
		var p := Parts.part(id)
		var avail := Career.part_available(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var pid: String = id
		var name_b := _sel_button("%s%s" % [p["name"], "" if avail else "  (Lv %d)" % p.get("tier", 1)], id == _market_sel, func():
			_market_sel = pid
			_refresh(), 400)
		if not avail:
			name_b.modulate = Color(1, 1, 1, 0.5)
		row.add_child(name_b)
		var info := _mono("%4d cr  %s  own %d" % [Career.price_of(id), _stars(int(p.get("quality", 3))), Career.stock(id)], 16)
		info.custom_minimum_size = Vector2(220, 0)
		row.add_child(info)
		var minus := UITheme.button("−", func():
			_cart[pid] = maxi(int(_cart.get(pid, 0)) - 1, 0)
			if _cart[pid] == 0:
				_cart.erase(pid)
			_refresh(), Vector2(40, 38))
		var plus := UITheme.button("+", func():
			if avail:
				_cart[pid] = mini(int(_cart.get(pid, 0)) + 1, Career.market_stock(pid))
			_refresh(), Vector2(40, 38))
		plus.disabled = not avail or Career.market_stock(id) == 0
		row.add_child(minus)
		row.add_child(_mono("%d" % int(_cart.get(id, 0)), 18, UITheme.ACCENT))
		row.add_child(plus)
		list.add_child(row)
	h.add_child(r[0])
	# details + cart
	var det := _col(760, true)
	if _market_sel != "":
		var p := Parts.part(_market_sel)
		det.add_child(_mono(p["name"], 24, UITheme.ACCENT))
		det.add_child(_mono("by %s  •  quality %s  •  %d g" % [Parts.BRANDS.get(p.get("brand", ""), {}).get("name", "?"), _stars(int(p.get("quality", 3))), int(p.get("mass", 0))], 17))
		var hh := HBoxContainer.new()
		var mdl := MeshFactory.make_part(_market_sel, "frame_5")
		var b := MeshFactory.bounds(_market_sel)
		mdl.position = -b["c"]
		hh.add_child(_preview(mdl, b["r"], Vector2(300, 220)))
		var st := _col(420)
		st.add_child(_wrap(p["desc"], 420, 17))
		st.add_child(_wrap(_spec_text(p), 420, 16, UITheme.MUTED))
		var stock := Career.market_stock(_market_sel)
		st.add_child(_mono("Market stock today: %d   •   In storage: %d" % [stock, Career.stock(_market_sel)], 16, UITheme.GOOD if stock > 0 else UITheme.BAD))
		if not Career.part_available(_market_sel):
			st.add_child(_mono("Stocked from garage level %d." % int(p.get("tier", 1)), 16, UITheme.BAD))
		hh.add_child(st)
		det.add_child(hh)
	det.add_child(HSeparator.new())
	det.add_child(_mono("CART", 20, UITheme.ACCENT))
	var total := 0
	var n := 0
	for id in _cart:
		total += Career.price_of(id) * int(_cart[id])
		n += int(_cart[id])
		det.add_child(_mono("  %d x %s   %d cr" % [_cart[id], Parts.part(id)["name"], Career.price_of(id) * int(_cart[id])], 16))
	if _cart.is_empty():
		det.add_child(_mono("  empty", 16, UITheme.MUTED))
	det.add_child(_mono("Total %d cr   •   Delivery ~%s   •   Storage %d / %d" % [total, Career._fmt_s(Career.delivery_time(_cart)), Career.stored_count() + n, Career.storage_cap()], 18))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	var order := UITheme.accent_button("PLACE ORDER", func():
		var err := Career.place_order(_cart)
		if err != "":
			Audio.play("error")
			_toast(err)
		else:
			Audio.play("cash")
			_cart.clear()
			_refresh(), Vector2(240, 48))
	order.disabled = _cart.is_empty()
	bh.add_child(order)
	bh.add_child(UITheme.button("Clear cart", func():
		_cart.clear()
		_refresh(), Vector2(160, 48)))
	bh.add_child(UITheme.button("+ Spare prop set", func():
		var d := Career.active_drone()
		var t: String = Parts.part(d.get("placed", {}).get("prop_1", "prop_5143_ccw")).get("type", "5143")
		for dir in ["cw", "ccw"]:
			var pid := "prop_%s_%s" % [t, dir]
			_cart[pid] = mini(int(_cart.get(pid, 0)) + 2, Career.market_stock(pid))
		_refresh(), Vector2(230, 48)))
	det.add_child(bh)
	h.add_child(det)
	return h


func _spec_text(p: Dictionary) -> String:
	var t: Array = []
	match p["cat"]:
		"frame": t.append("Arm %.1f cm, %d\" props, durability x%.2f, drag x%.2f" % [p["arm"], int(p["prop_in"]), p.get("durability", 1.0), p["drag"]])
		"motor": t.append("%d KV, %s spin (needs 2 CW + 2 CCW of one model)" % [p["kv"], p["spin"]])
		"prop": t.append("%d blades, thrust x%.2f, %s spin" % [p["blades"], p["thrust"], p["spin"]])
		"esc": t.append("Current limit x%.1f" % p.get("climit", 1.0))
		"fc": t.append("Gyro noise x%.1f" % p.get("gyro", 1.0))
		"rx": t.append("Control range ~%d m" % int(p["range"]))
		"vtx": t.append("%s video" % ("Digital" if p["digital"] else "Analogue"))
		"antenna": t.append("Video range x%.1f" % p["gain"])
		"cam_mount": t.append("Camera tilt %d°, vibration x%.2f" % [int(p["tilt"]), p["damp"]])
		"cam": t.append("%s camera - needs a matching VTX" % ("Digital" if p["digital"] else "Analogue"))
		"battery": t.append("%d mAh (simulated pack)" % int(p["mah"]))
		"guard": t.append("Crash protection +%d %%, bump tolerance +%.1f m/s" % [int(p["protect"] * 100.0), p["bump"]])
		"payload":
			if p.get("kind", "") == "scan":
				t.append("Scan speed and range x2")
			else:
				t.append("%d release(s), abstract power %d, radius %.1f m" % [p["charges"], int(p["power"]), p["radius"]])
	if p.has("print"):
		t.append("Can be 3D printed at Level 2+ for %d cr of filament." % p["print"])
	return "\n".join(t)


# =====================================================================================
# DRONE MANAGER
# =====================================================================================
func _app_drones() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var r := _scroll_col(360)
	var list: VBoxContainer = r[1]
	list.add_child(_mono("ROSTER (%d)" % Career.roster().size(), 18, UITheme.ACCENT))
	if _drone_sel == "" and not Career.roster().is_empty():
		_drone_sel = Career.roster()[0]["id"]
	for d in Career.roster():
		var did: String = d["id"]
		list.add_child(_sel_button("%s%s  [%s]" % ["★ " if Career.data["active_drone"] == did else "", d["name"], d["location"]], did == _drone_sel, func():
			_drone_sel = did
			_refresh(), 340))
	if not Game.placed.is_empty():
		list.add_child(_mono("On the workbench: %s" % (Game.bench_name if Game.bench_name != "" else "unsaved build"), 16, UITheme.MUTED))
	list.add_child(HSeparator.new())
	list.add_child(_mono("BUILD PRESETS", 18, UITheme.ACCENT))
	for p in Career.data["presets"]:
		list.add_child(_mono("  " + p["name"], 16))
	h.add_child(r[0])
	var d := Career.get_drone(_drone_sel)
	if d.is_empty():
		h.add_child(_wrap("No drones yet. Assemble one at the workbench and SAVE it - it will appear here.", 800, 20))
		return h
	var mid := _col(560)
	var mdl := DroneVisual.assemble(d["placed"], d.get("broken", {}), d.get("cond", {}), Career.paint_of(d))
	mdl.position = Vector3(0, -3, 0)
	mid.add_child(_preview(mdl, 14.0, Vector2(560, 380)))
	var name_row := HBoxContainer.new()
	var le := LineEdit.new()
	le.text = d["name"]
	le.custom_minimum_size = Vector2(300, 40)
	le.max_length = 24
	name_row.add_child(le)
	name_row.add_child(UITheme.button("Rename", func():
		d["name"] = le.text.strip_edges() if le.text.strip_edges() != "" else d["name"]
		Career.mark_dirty()
		_refresh(), Vector2(120, 40)))
	name_row.add_child(UITheme.button("Random", func():
		d["name"] = Career.drone_name_suggestion()
		Career.data["next_no"] = int(Career.data["next_no"]) + 1
		Career.mark_dirty()
		_refresh(), Vector2(120, 40)))
	mid.add_child(name_row)
	var acts := GridContainer.new()
	acts.columns = 2
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	acts.add_child(UITheme.button("Set as active drone", func():
		Career.data["active_drone"] = d["id"]
		Career.mark_dirty()
		_refresh(), Vector2(270, 42)))
	acts.add_child(UITheme.button("Save build as preset", func():
		Career.save_preset(d["name"].get_slice("-", 0).get_slice(" #", 0) + " build", d["placed"], d["cfg"])
		_toast("Preset saved - use it in FACTORY ORDERS.")
		_refresh(), Vector2(270, 42)))
	acts.add_child(UITheme.button("Duplicate (production order)", func():
		var pn: String = d["name"].get_slice(" #", 0) + " build"
		Career.save_preset(pn, d["placed"], d["cfg"])
		Career.add_job(pn, 1, Career.level() >= 3)
		_toast("Production order added for one more '%s'." % pn)
		_refresh(), Vector2(270, 42)))
	var paint_i := 0
	for i in Campaign.PAINTS.size():
		if Career.paint_of(d).is_equal_approx(Campaign.PAINTS[i]["color"]):
			paint_i = i
	acts.add_child(UITheme.button("Repaint: %s (5 cr)" % Campaign.PAINTS[(paint_i + 1) % Campaign.PAINTS.size()]["name"], func():
		if Career.spend(5, "Paint for %s" % d["name"]):
			var c: Color = Campaign.PAINTS[(paint_i + 1) % Campaign.PAINTS.size()]["color"]
			d["paint"] = [c.r, c.g, c.b, 1.0]
			Career.mark_dirty()
			_refresh(), Vector2(270, 42)))
	var cmp := OptionButton.new()
	cmp.custom_minimum_size = Vector2(270, 42)
	cmp.add_item("Compare with…")
	var cmp_ids: Array = [""]
	for o in Career.roster():
		if o["id"] != d["id"]:
			cmp.add_item(o["name"])
			cmp_ids.append(o["id"])
	cmp.selected = maxi(cmp_ids.find(_compare_sel), 0)
	cmp.item_selected.connect(func(i):
		_compare_sel = cmp_ids[i]
		_refresh())
	acts.add_child(cmp)
	var dis := UITheme.button("Disassemble into parts", Callable(), Vector2(270, 42))
	dis.pressed.connect(func():
		if dis.text != "Really disassemble?":
			dis.text = "Really disassemble?"
			return
		Career.disassemble(d["id"])
		_drone_sel = ""
		_refresh())
	acts.add_child(dis)
	mid.add_child(acts)
	h.add_child(mid)
	var rr := _scroll_col(820, true)
	var right: VBoxContainer = rr[1]
	right.add_child(_wrap(DiagnosticsPanel.Report.text(d), 780, 17))
	var dmg: Array = []
	for slot in d.get("cond", {}):
		if float(d["cond"][slot]) < 0.95:
			dmg.append("%s %d %%" % [slot.replace("_", " "), int(float(d["cond"][slot]) * 100.0)])
	for slot in d.get("broken", {}):
		dmg.append("%s BROKEN" % slot.replace("_", " "))
	right.add_child(_wrap("Condition: " + (", ".join(dmg) if not dmg.is_empty() else "all parts like new"), 780, 17, UITheme.BAD if not dmg.is_empty() else UITheme.GOOD))
	right.add_child(_wrap("Battery %d %%%s  •  %s  •  missions %d  •  targets %d" % [int(float(d.get("charge", 1.0)) * 100.0), "" if d.get("battery_in", true) else " (on charger)", "CERTIFIED" if d.get("certified", false) else "not certified", int(d.get("missions", 0)), int(d.get("targets", 0))], 780, 17))
	var o := Career.get_drone(_compare_sel)
	if not o.is_empty():
		right.add_child(HSeparator.new())
		right.add_child(_mono("COMPARISON", 18, UITheme.ACCENT))
		var a := Career.drone_stats(d)
		var b := Career.drone_stats(o)
		if a.has("twr") and b.has("twr"):
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 30)
			for row in [["", d["name"], o["name"]], ["Weight g", int(a["mass_g"]), int(b["mass_g"])], ["TWR", "%.1f" % a["twr"], "%.1f" % b["twr"]],
				["Endurance min", "%.1f" % a["endurance_min"], "%.1f" % b["endurance_min"]], ["Top km/h", int(a["top_kmh"]), int(b["top_kmh"])],
				["Agility", int(a["agility"]), int(b["agility"])], ["Durability", int(a["durability_pct"]), int(b["durability_pct"])], ["Cost cr", a["cost"], b["cost"]]]:
				for c in row:
					grid.add_child(_mono(str(c), 17))
			right.add_child(grid)
	h.add_child(rr[0])
	return h


# =====================================================================================
# FACTORY ORDERS
# =====================================================================================
func _app_factory() -> Control:
	var v := _col(1780, true)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	for i in 3:
		var ii: int = i
		tabs.add_child(_sel_button(["CUSTOMER CONTRACTS", "PRODUCTION ORDERS", "BUILD PRESETS"][i], _factory_tab == i, func():
			_factory_tab = ii
			_refresh(), 300))
	v.add_child(tabs)
	var r := _scroll_col(1780, true)
	var body: VBoxContainer = r[1]
	v.add_child(r[0])
	match _factory_tab:
		0:
			body.add_child(_wrap("Customers buy finished, certified, undamaged drones that meet their spec. Delivering pays credits and reputation.", 1700, 17, UITheme.MUTED))
			for c in Career.open_contracts():
				var p := PanelContainer.new()
				var pv := _col(1700)
				p.add_child(pv)
				pv.add_child(_mono("%s  -  %s  x%d   (%d delivered)   %d cr each   due day %d" % [c["customer"], c["kind"], c["qty"], c["delivered_n"], c["pay"], c["deadline"]], 20, UITheme.ACCENT))
				pv.add_child(_wrap(c["text"], 1680, 17))
				pv.add_child(_mono("Requires: " + Campaign.req_text(c["req"]), 17, MONO))
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 10)
				var ob := OptionButton.new()
				ob.custom_minimum_size = Vector2(420, 40)
				var ids: Array = []
				for d in Career.roster():
					var why := Campaign.contract_check(c, d)
					ob.add_item("%s  %s" % [d["name"], "✓ qualifies" if why == "" else "✗ " + why])
					ids.append(d["id"])
				row.add_child(ob)
				var cid: String = c["id"]
				var deliver := UITheme.accent_button("DELIVER", func():
					if ids.is_empty():
						return
					var err := Career.deliver_to_contract(cid, ids[ob.selected])
					if err != "":
						_toast(err)
						Audio.play("error")
					_refresh(), Vector2(180, 40))
				deliver.disabled = ids.is_empty()
				row.add_child(deliver)
				pv.add_child(row)
				body.add_child(p)
		1:
			body.add_child(_wrap("Production orders track batches of a build preset. Build them at the workbench (they count when you save a matching drone), or - from garage level 3 - let the automated assembly station make them from stock.", 1700, 17, UITheme.MUTED))
			for j in Career.data["jobs"]:
				var pr := ""
				if j["auto"] and int(j["done"]) < int(j["qty"]):
					pr = "  assembling %d %%" % int(float(j["progress"]) / Career.assembly_time() * 100.0)
				body.add_child(_mono("%s x%d - %d done  (%s)%s" % [j["preset"], j["qty"], j["done"], "automated" if j["auto"] else "manual at bench", pr], 19, UITheme.GOOD if int(j["done"]) >= int(j["qty"]) else MONO))
			if Career.data["jobs"].any(func(j): return int(j["done"]) >= int(j["qty"])):
				body.add_child(UITheme.button("Clear finished orders", func():
					Career.data["jobs"] = Career.data["jobs"].filter(func(j): return int(j["done"]) < int(j["qty"]))
					_refresh(), Vector2(260, 40)))
			body.add_child(HSeparator.new())
			body.add_child(_mono("NEW PRODUCTION ORDER", 20, UITheme.ACCENT))
			if Career.data["presets"].is_empty():
				body.add_child(_wrap("No presets yet - save one in DRONE MANAGER or the BUILD PRESETS tab.", 1700, 17, UITheme.MUTED))
			else:
				if _job_preset == "":
					_job_preset = Career.data["presets"][0]["name"]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 10)
				var ob := OptionButton.new()
				ob.custom_minimum_size = Vector2(360, 40)
				var sel := 0
				for i in Career.data["presets"].size():
					ob.add_item(Career.data["presets"][i]["name"])
					if Career.data["presets"][i]["name"] == _job_preset:
						sel = i
				ob.selected = sel
				ob.item_selected.connect(func(i):
					_job_preset = Career.data["presets"][i]["name"]
					_refresh())
				row.add_child(ob)
				row.add_child(UITheme.button("−", func():
					_job_qty = maxi(_job_qty - 1, 1)
					_refresh(), Vector2(44, 40)))
				row.add_child(_mono("x%d" % _job_qty, 20, UITheme.ACCENT))
				row.add_child(UITheme.button("+", func():
					_job_qty = mini(_job_qty + 1, 10)
					_refresh(), Vector2(44, 40)))
				var auto := CheckButton.new()
				auto.text = "Automated assembly"
				auto.button_pressed = _job_auto
				auto.disabled = Career.level() < 3
				auto.toggled.connect(func(on): _job_auto = on)
				row.add_child(auto)
				row.add_child(UITheme.accent_button("ADD ORDER", func():
					var err := Career.add_job(_job_preset, _job_qty, _job_auto)
					if err != "":
						_toast(err)
					_refresh(), Vector2(180, 40)))
				body.add_child(row)
				var preset := {}
				for p in Career.data["presets"]:
					if p["name"] == _job_preset:
						preset = p
				if not preset.is_empty():
					var need := Career.preset_parts(preset["placed"])
					var miss := Career.missing_for(preset["placed"], _job_qty)
					var cost := 0
					for id in need:
						cost += Career.price_of(id) * int(need[id]) * _job_qty
					body.add_child(_mono("Required components for x%d  (estimated parts cost %d cr):" % [_job_qty, cost], 18))
					for id in need:
						var want: int = int(need[id]) * _job_qty
						body.add_child(_mono("   %-34s need %2d   in stock %2d   %s" % [Parts.part(id)["name"], want, Career.stock(id), "missing %d" % miss[id] if miss.has(id) else "ok"], 16, UITheme.BAD if miss.has(id) else UITheme.GOOD))
					if not miss.is_empty():
						body.add_child(UITheme.button("Order the missing parts", func():
							var err := Career.place_order(miss)
							_toast(err if err != "" else "Missing parts ordered.")
							_refresh(), Vector2(300, 42)))
		2:
			body.add_child(_wrap("Presets are build templates. Saving the bench drone as a preset lets you batch-produce it.", 1700, 17, UITheme.MUTED))
			var bench_ok: bool = Game.stats().get("complete", false)
			var row := HBoxContainer.new()
			var le := LineEdit.new()
			le.placeholder_text = "Preset name"
			le.text = (Game.bench_name if Game.bench_name != "" else "Bench") + " build"
			le.custom_minimum_size = Vector2(360, 40)
			row.add_child(le)
			var b := UITheme.button("Save workbench build as preset", func():
				Career.save_preset(le.text, Game.placed, Game.cfg)
				_refresh(), Vector2(360, 40))
			b.disabled = not bench_ok
			row.add_child(b)
			body.add_child(row)
			for i in Career.data["presets"].size():
				var p: Dictionary = Career.data["presets"][i]
				var st := Parts.compute_build(p["placed"], {})
				var line := HBoxContainer.new()
				line.add_child(_mono("%-28s  %s, TWR %.1f, %.1f min, %d cr" % [p["name"], st.get("frame_name", "?"), st.get("twr", 0.0), st.get("endurance_min", 0.0), st.get("cost", 0)], 17))
				var ii: int = i
				line.add_child(UITheme.button("Delete", func():
					Career.data["presets"].remove_at(ii)
					Career.mark_dirty()
					_refresh(), Vector2(110, 36)))
				body.add_child(line)
	return v


# =====================================================================================
# DEPLOYMENT MAP
# =====================================================================================
func _app_deploy() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var r := _scroll_col(520)
	var list: VBoxContainer = r[1]
	var last_map := ""
	for m in Campaign.missions():
		if m["map"] != last_map:
			last_map = m["map"]
			list.add_child(_mono(Campaign.MAP_NAMES[m["map"]].to_upper(), 17, UITheme.ACCENT))
		var mid: String = m["id"]
		var unlocked := Career.mission_unlocked(m)
		if _mission_sel == "" and unlocked:
			_mission_sel = mid
		var tag := "✓ " if Career.mission_count(mid) > 0 else ""
		var b := _sel_button("%s%s  %s" % [tag, m["name"], "★".repeat(int(m["difficulty"]))], mid == _mission_sel, func():
			_mission_sel = mid
			_refresh(), 500)
		if not unlocked:
			b.modulate = Color(1, 1, 1, 0.4)
		list.add_child(b)
	h.add_child(r[0])
	var m := Campaign.mission(_mission_sel)
	if m.is_empty():
		return h
	var mid_col := _col(560)
	var mapv := MissionMapView.new()
	mapv.mission = m
	mapv.custom_minimum_size = Vector2(560, 420)
	mid_col.add_child(mapv)
	mid_col.add_child(_wrap("Region: %s\nConditions: %s, %s, wind %.1f m/s" % [Campaign.MAP_NAMES[m["map"]], m["time"], m["weather"], m["wind"]], 560, 17))
	h.add_child(mid_col)
	var right := _col(640, true)
	right.add_child(_mono(m["name"], 28, UITheme.ACCENT))
	right.add_child(_mono("Difficulty %s   •   %s" % [_stars(int(m["difficulty"])), "Training rules - crashed drones are recovered" if m["recover"] == "recoverable" else "Contested - a drone that goes down is lost"], 17, UITheme.BAD if m["recover"] == "contested" else UITheme.GOOD))
	right.add_child(_wrap(m["blurb"], 640, 19))
	right.add_child(_mono("Reward: %d cr first time%s, %d cr repeat   •   +%d reputation" % [m["reward"], "" if Career.mission_count(m["id"]) == 0 else " (claimed)", m["repeat_reward"], m["rep"]], 18, UITheme.GOOD))
	if not Career.mission_unlocked(m):
		var req: Array = []
		for x in m["requires"]:
			req.append(Campaign.mission(x)["name"])
		right.add_child(_mono("LOCKED - complete: " + ", ".join(req), 18, UITheme.BAD))
		return _with(h, right)
	right.add_child(HSeparator.new())
	right.add_child(_mono("SELECT DRONE", 18, UITheme.ACCENT))
	if _deploy_drone == "" or Career.get_drone(_deploy_drone).is_empty():
		_deploy_drone = Career.data["active_drone"]
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(620, 42)
	var ids: Array = []
	for d in Career.roster():
		var why := Career.deploy_check(d)
		ob.add_item("%s  %s" % [d["name"], "- ready" if why == "" else "- " + why])
		ids.append(d["id"])
	if ids.is_empty():
		right.add_child(_mono("No drones in the roster.", 18, UITheme.BAD))
		return _with(h, right)
	ob.selected = maxi(ids.find(_deploy_drone), 0)
	_deploy_drone = ids[ob.selected]
	ob.item_selected.connect(func(i):
		_deploy_drone = ids[i]
		_refresh())
	right.add_child(ob)
	var d := Career.get_drone(_deploy_drone)
	var st := Career.drone_stats(d)
	if st.has("twr"):
		right.add_child(_mono("TWR %.1f  •  %.1f min  •  %s  •  battery %d %%" % [st["twr"], st["endurance_min"], ("module: " + Parts.part(st["payload_id"])["name"]) if st["payload_id"] != "" else "no mission module", int(float(d.get("charge", 1.0)) * 100.0)], 17))
	if m["type"] == "strike" and st.get("payload_kind", "") != "drop":
		right.add_child(_wrap("Note: no drop module fitted - you can still hit targets by impact, but the drone won't survive it.", 620, 16, UITheme.ACCENT))
	if int(d.get("pods_used", 0)) > 0 and d["placed"].has("payload"):
		right.add_child(_mono("Module rearm on deployment: %d cr" % (int(float(Parts.part(d["placed"]["payload"])["price"]) * 0.35) * int(d["pods_used"])), 17, UITheme.ACCENT))
	var why := Career.deploy_check(d)
	if why != "":
		right.add_child(_wrap(why, 620, 18, UITheme.BAD))
	var go := UITheme.accent_button("DEPLOY", func():
		if garage and garage.has_method("launch"):
			var err: String = garage.launch(_mission_sel, _deploy_drone)
			if err != "":
				_toast(err), Vector2(300, 56))
	go.disabled = why != ""
	right.add_child(go)
	return _with(h, right)


func _with(h: HBoxContainer, right: Control) -> HBoxContainer:
	h.add_child(right)
	return h


# =====================================================================================
# INVENTORY / DIAGNOSTICS / FINANCES / UPGRADES / SETTINGS
# =====================================================================================
func _app_inventory() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var r := _scroll_col(1000)
	var v: VBoxContainer = r[1]
	v.add_child(_mono("COMPONENT STORAGE  %d / %d" % [Career.stored_count(), Career.storage_cap()], 20, UITheme.ACCENT))
	for cat in Parts.CATEGORIES:
		var ids: Array = Parts.parts_in(cat).filter(func(i): return Career.stock(i) > 0)
		if ids.is_empty():
			continue
		v.add_child(_mono(Parts.CAT_NAMES[cat].to_upper(), 17, UITheme.ACCENT))
		for id in ids:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var l := _mono("  %3d x  %s" % [Career.stock(id), Parts.part(id)["name"]], 17)
			l.custom_minimum_size = Vector2(620, 0)
			row.add_child(l)
			var pid: String = id
			var sell := int(Career.price_of(id) * 0.5)
			row.add_child(UITheme.button("Sell 1 (+%d cr)" % sell, func():
				if Career.take(pid):
					Career.earn(sell, "Sold %s" % Parts.part(pid)["name"])
				_refresh(), Vector2(200, 34)))
			v.add_child(row)
	h.add_child(r[0])
	var r2 := _scroll_col(720, true)
	var v2: VBoxContainer = r2[1]
	v2.add_child(_mono("SALVAGE BIN", 20, UITheme.ACCENT))
	v2.add_child(_wrap("Damaged parts removed at the workbench or from disassembled drones. Repair them back into stock, or recycle them for scrap value.", 680, 16, UITheme.MUTED))
	if Career.data["salvage"].is_empty():
		v2.add_child(_mono("Empty.", 17, UITheme.MUTED))
	for i in Career.data["salvage"].size():
		var s: Dictionary = Career.data["salvage"][i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := _mono("%s %d %%" % [Parts.part(s["id"])["name"], int(float(s["cond"]) * 100.0)], 16)
		l.custom_minimum_size = Vector2(330, 0)
		row.add_child(l)
		var idx: int = i
		if float(s["cond"]) > 0.0:
			row.add_child(UITheme.button("Repair %d cr" % Career.repair_cost(s["id"], s["cond"]), func():
				Career.repair_salvage(idx)
				_refresh(), Vector2(160, 34)))
		row.add_child(UITheme.button("Recycle +%d" % Career.recycle_value(s["id"], s["cond"]), func():
			Career.recycle_salvage(idx)
			_refresh(), Vector2(160, 34)))
		v2.add_child(row)
	h.add_child(r2[0])
	return h


func _app_diag() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var list := _col(360)
	list.add_child(_mono("SELECT DRONE", 18, UITheme.ACCENT))
	if _diag_sel == "" and not Career.roster().is_empty():
		_diag_sel = Career.roster()[0]["id"]
	for d in Career.roster():
		var did: String = d["id"]
		list.add_child(_sel_button("%s  %s" % [d["name"], "✓" if d.get("certified", false) else "✗"], did == _diag_sel, func():
			_diag_sel = did
			_refresh(), 340))
	h.add_child(list)
	var d := Career.get_drone(_diag_sel)
	if d.is_empty():
		h.add_child(_wrap("No drones to inspect.", 600, 20))
		return h
	var v := _col(600)
	v.add_child(_mono("VIRTUAL CHECKS", 18, UITheme.ACCENT))
	for c in DiagnosticsPanel.Report.checks(d):
		var ok: bool = c["ok"]
		v.add_child(_wrap("%s  %s%s" % ["OK  " if ok and not c.get("warn", false) else ("WARN" if ok else "FAIL"), c["name"], "" if c.get("note", "") == "" else " - " + c["note"]], 580, 17, UITheme.GOOD if ok and not c.get("warn", false) else (UITheme.ACCENT if ok else UITheme.BAD)))
	v.add_child(_wrap("Certification needs the physical TEST STATION in the garage: pick the drone up from the rack and press %s on the station." % Pad.glyph("use"), 580, 16, UITheme.MUTED))
	h.add_child(v)
	h.add_child(_wrap(DiagnosticsPanel.Report.text(d), 760, 17))
	return h


func _app_finance() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	var v := _col(560)
	var inc := 0
	var spent := 0
	for e in Career.data["ledger"]:
		if int(e["amount"]) > 0:
			inc += int(e["amount"])
		else:
			spent -= int(e["amount"])
	v.add_child(_mono("BALANCE  %d cr" % Career.credits(), 30, UITheme.ACCENT))
	v.add_child(_mono("Income (recent)    %d cr" % inc, 20, UITheme.GOOD))
	v.add_child(_mono("Spending (recent)  %d cr" % spent, 20, UITheme.BAD))
	v.add_child(HSeparator.new())
	var s: Dictionary = Career.data["stats"]
	v.add_child(_mono("Drones built     %d" % int(s["drones_built"]), 19))
	v.add_child(_mono("Drones lost      %d" % int(s["drones_lost"]), 19))
	v.add_child(_mono("Flights          %d" % int(s["flights"]), 19))
	v.add_child(_mono("Targets          %d" % int(s["targets"]), 19))
	v.add_child(_mono("Contracts done   %d" % int(s["contracts"]), 19))
	v.add_child(_mono("Reputation       %d" % int(Career.data["rep"]), 19))
	var fleet := 0
	for d in Career.roster():
		fleet += int(Career.drone_stats(d).get("cost", 0))
	var stock := 0
	for id in Career.data["inventory"]:
		stock += Career.price_of(id) * int(Career.data["inventory"][id])
	v.add_child(_mono("Fleet value      %d cr" % fleet, 19))
	v.add_child(_mono("Stock value      %d cr" % stock, 19))
	h.add_child(v)
	var r := _scroll_col(1100, true)
	var l: VBoxContainer = r[1]
	l.add_child(_mono("LEDGER", 20, UITheme.ACCENT))
	var led: Array = Career.data["ledger"].duplicate()
	led.reverse()
	for e in led:
		l.add_child(_mono("Day %-3d %s   %+6d cr   %s" % [int(e["day"]), e.get("time", ""), int(e["amount"]), e["text"]], 16, UITheme.GOOD if int(e["amount"]) > 0 else MONO))
	h.add_child(r[0])
	return h


func _app_upgrades() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	var v := _col(880)
	v.add_child(_mono("GARAGE LEVEL", 22, UITheme.ACCENT))
	for li in Campaign.LEVELS:
		var cur: bool = int(li["level"]) == Career.level()
		var done: bool = int(li["level"]) <= Career.level()
		v.add_child(_wrap("%s Level %d - %s   (%d cr, %d rep)\n    %s\n    Rack %d drones, %d charging docks, storage %d" % ["▶" if cur else ("✓" if done else " "), li["level"], li["name"], li["cost"], li["rep"], li["adds"], li["rack"], li["docks"], li["storage"]],
			860, 17, UITheme.GOOD if done else MONO))
	if Career.level() < Campaign.LEVELS.size():
		var nxt := Career.level_info(Career.level() + 1)
		v.add_child(UITheme.accent_button("EXPAND TO LEVEL %d  (%d cr, needs %d rep)" % [nxt["level"], nxt["cost"], nxt["rep"]], func():
			var err := Career.upgrade_level()
			if err != "":
				_toast(err)
				Audio.play("error")
			else:
				_toast("Upgraded! New equipment is installed in the garage.")
			_refresh(), Vector2(620, 54)))
		v.add_child(_wrap("New equipment appears in the garage the next time you walk in.", 860, 16, UITheme.MUTED))
	h.add_child(v)
	var u := _col(800, true)
	u.add_child(_mono("WORKSHOP UPGRADES", 22, UITheme.ACCENT))
	for id in Campaign.UPGRADES:
		var up: Dictionary = Campaign.UPGRADES[id]
		var have := Career.has_upgrade(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_wrap("%s%s - %s" % ["✓ " if have else "", up["name"], up["desc"]], 520, 17, UITheme.GOOD if have else MONO))
		var uid: String = id
		var b := UITheme.button("Owned" if have else "%d cr (Lv %d)" % [up["cost"], up["level"]], func():
			var err := Career.buy_upgrade(uid)
			if err != "":
				_toast(err)
			_refresh(), Vector2(220, 40))
		b.disabled = have or Career.level() < int(up["level"])
		row.add_child(b)
		u.add_child(row)
	h.add_child(u)
	return h


func _app_settings() -> Control:
	var v := _col(900)
	v.add_child(_wrap("Graphics, audio, flight assist, OSD, controller and key bindings.", 900, 18))
	v.add_child(UITheme.accent_button("OPEN SETTINGS", func():
		var o := OptionsMenu.new()
		add_child(o), Vector2(320, 54)))
	v.add_child(UITheme.button("Save game now", func():
		Career.save()
		Game.save_drone()
		_toast("Saved."), Vector2(320, 48)))
	return v


func _toast(text: String) -> void:
	var l := _wrap(text, 700, 20, Color.WHITE)
	l.add_theme_stylebox_override("normal", UITheme.flat(Color(0.1, 0.05, 0.02, 0.95), 6, UITheme.ACCENT, 1, 14))
	l.position = Vector2(610, 940)
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


## Stylised briefing map for a mission (launch point, objective area, routes).
class MissionMapView:
	extends Control
	var mission: Dictionary = {}

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var map: String = mission.get("map", "testing")
		var base: Color = {"testing": Color(0.22, 0.32, 0.2), "rural": Color(0.3, 0.36, 0.18), "industrial": Color(0.28, 0.28, 0.27)}.get(map, Color(0.2, 0.2, 0.2))
		draw_rect(r, base)
		var rng := RandomNumberGenerator.new()
		rng.seed = map.hash()
		for i in 40:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var s := Vector2(rng.randf_range(20, 90), rng.randf_range(20, 70))
			var c: Color = base.lightened(rng.randf_range(-0.1, 0.15)) if map != "industrial" else Color(0.38, 0.38, 0.4) if rng.randf() < 0.5 else base.darkened(0.2)
			draw_rect(Rect2(p, s), c)
		var info := FlyWorld.map_info(map)
		var half: float = info["half"]
		var to_px := func(v: Vector2) -> Vector2: return (v / (half * 2.0) + Vector2(0.5, 0.5)) * size
		var road: Array = info.get("road", [])
		for i in range(1, road.size()):
			draw_line(to_px.call(road[i - 1]), to_px.call(road[i]), Color(0.15, 0.15, 0.16), 6.0)
		var launch: Vector2 = info["launch"]
		draw_circle(to_px.call(launch), 9.0, Color(0.3, 0.8, 1.0))
		draw_string(ThemeDB.fallback_font, to_px.call(launch) + Vector2(12, 5), "LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		var area: Vector2 = info["anchors"].get(_area_key(), launch)
		var ap: Vector2 = to_px.call(area)
		draw_arc(ap, 34.0, 0, TAU, 32, Color(1, 0.35, 0.2), 3.0)
		draw_line(ap + Vector2(-44, 0), ap + Vector2(-24, 0), Color(1, 0.35, 0.2), 2.0)
		draw_line(ap + Vector2(24, 0), ap + Vector2(44, 0), Color(1, 0.35, 0.2), 2.0)
		draw_string(ThemeDB.fallback_font, ap + Vector2(40, -30), "OBJECTIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.6, 0.5))
		draw_dashed_line(to_px.call(launch), ap, Color(1, 1, 1, 0.5), 2.0, 10.0)
		draw_rect(r, Color(0.3, 0.6, 0.5, 0.6), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(10, 22), Campaign.MAP_NAMES.get(map, map).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))

	func _area_key() -> String:
		var t: Array = mission.get("targets", [])
		if t.is_empty():
			return "course"
		var first: Dictionary = t[0]
		if first.get("kind", "") == "convoy":
			return "convoy"
		return first.get("at", "course")
