class_name HowToPlay
extends Control
## The full in-game guide: chapters on the left, pages on the right. Shown on the first
## career start, and from the main menu, the garage (F1 / pause menu) and the tablet.

signal closed

var start_chapter := 0
var _chapter := 0
var _nav: VBoxContainer
var _body: VBoxContainer
var _page_lbl: Label
var _nav_buttons: Array = []

const CHAPTERS := ["Welcome", "Moving around", "Getting parts", "Building a drone", "Certify, charge, deploy",
	"Flying", "Missions & combat", "Running the business", "Tips & settings"]


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var p := PanelContainer.new()
	p.position = Vector2(150, 70)
	p.size = Vector2(1620, 940)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UITheme.title("HOW TO PLAY", 38, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_page_lbl = UITheme.label("", 18, UITheme.MUTED)
	top.add_child(_page_lbl)
	top.add_child(UITheme.button("Close", func(): closed.emit(), Vector2(130, 42)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_nav = VBoxContainer.new()
	_nav.custom_minimum_size = Vector2(330, 0)
	_nav.add_theme_constant_override("separation", 6)
	h.add_child(_nav)
	for i in CHAPTERS.size():
		var ii := i
		var b := UITheme.button("%d   %s" % [i + 1, CHAPTERS[i]], func(): _show(ii), Vector2(330, 52))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_nav.add_child(b)
		_nav_buttons.append(b)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	sc.add_child(_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(foot)
	foot.add_child(UITheme.label("Mouse, arrow keys or D-pad to browse  •  Esc / Circle to close", 17, UITheme.MUTED))
	foot.add_child(UITheme.button("<  Previous", func(): _show(maxi(_chapter - 1, 0)), Vector2(180, 46)))
	foot.add_child(UITheme.accent_button("Next  >", func():
		if _chapter == CHAPTERS.size() - 1:
			closed.emit()
		else:
			_show(_chapter + 1), Vector2(180, 46)))
	_show(clampi(start_chapter, 0, CHAPTERS.size() - 1))
	Pad.focus_first(_nav, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _show(i: int) -> void:
	_chapter = i
	_page_lbl.text = "Chapter %d / %d" % [i + 1, CHAPTERS.size()]
	for k in _nav_buttons.size():
		var b: Button = _nav_buttons[k]
		if k == i:
			b.add_theme_stylebox_override("normal", UITheme.flat(Color(0.3, 0.21, 0.09), 7, UITheme.ACCENT, 2, 14))
		else:
			b.remove_theme_stylebox_override("normal")
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(UITheme.header(CHAPTERS[i], 30))
	match i:
		0: _welcome()
		1: _moving()
		2: _parts()
		3: _building()
		4: _deploy()
		5: _flying()
		6: _missions()
		7: _business()
		8: _tips()
	Audio.play("click", 1.2)


# --- widgets ------------------------------------------------------------------------------
func _p(text: String, size: int = 21, col: Color = UITheme.TEXT) -> void:
	var l := UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1150, 0)
	_body.add_child(l)


func _steps(items: Array) -> void:
	for k in items.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var n := UITheme.label("%d" % (k + 1), 22, Color(0.08, 0.06, 0.02))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size = Vector2(38, 38)
		n.add_theme_stylebox_override("normal", UITheme.flat(UITheme.ACCENT, 19, Color(0, 0, 0, 0), 0, 4))
		h.add_child(n)
		var l := UITheme.label(items[k], 20)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1090, 0)
		h.add_child(l)
		_body.add_child(h)


## Table of actions with the current keyboard and gamepad bindings.
func _keys(rows: Array) -> void:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 30)
	g.add_theme_constant_override("v_separation", 6)
	for t in ["ACTION", "KEYBOARD / MOUSE", "CONTROLLER"]:
		g.add_child(UITheme.label(t, 17, UITheme.ACCENT))
	for r in rows:
		var b: Dictionary = Settings.bindings.get(r[1], {})
		g.add_child(UITheme.label(r[0], 19))
		for slot in ["kb", "pad"]:
			var txt := Settings.binding_text(str(b.get(slot, ""))) if r.size() < 3 else str(r[2 if slot == "kb" else 3])
			var l := UITheme.label(" %s " % txt, 18, Color(1, 0.85, 0.55))
			l.add_theme_stylebox_override("normal", UITheme.flat(Color(1, 1, 1, 0.07), 5, Color(1, 1, 1, 0.12), 1, 8))
			g.add_child(l)
	_body.add_child(g)


func _note(text: String) -> void:
	var l := UITheme.label(text, 19, UITheme.ACCENT2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1150, 0)
	l.add_theme_stylebox_override("normal", UITheme.flat(Color(UITheme.ACCENT2, 0.08), 6, Color(UITheme.ACCENT2, 0.5), 1, 14))
	_body.add_child(l)


# --- chapters ---------------------------------------------------------------------------------
func _welcome() -> void:
	_p("You run a small drone workshop from your home garage for the Kalvarian Volunteer Workshops. Every drone you fly, you build yourself - part by part - and every part costs money. Missions and customer contracts pay for more parts, better equipment and a bigger workshop.")
	_p("THE LOOP", 22, UITheme.ACCENT)
	_steps([
		"Get parts: unpack the starter kit, later order more on the garage computer (PARTS MARKET). A van delivers them to the driveway.",
		"Build: at the WORKBENCH place every part on its glowing slot, tighten the screws, wire it, check the setup and SAVE the drone to the rack.",
		"Certify: carry the drone to the TEST STATION and run diagnostics.",
		"Fly: test it on the outdoor TEST PAD, then pick missions on the DEPLOYMENT MAP.",
		"Maintain: crashes damage parts. Repair or replace them at the bench, charge batteries at the dock.",
		"Grow: earn credits and reputation, take customer contracts, upgrade the garage (Levels 1-5).",
	])
	_note("The STEP card at the bottom-left of the garage screen and the floating orange arrow always show your next step. You can turn these hints off in Options > Gameplay.")


func _moving() -> void:
	_p("Walk around the garage in first person. Anything you can use glows when you look at it, and the prompt under the crosshair shows the exact key or button.")
	_keys([["Walk", "move_forward", "W A S D", "Left stick"], ["Look", "", "Mouse", "Right stick"], ["Interact / use", "use"], ["Pick up / drop", "pickup"],
		["Place held item", "place"], ["Rotate held item (hold)", "rotate_item"], ["Inspect / secondary", "secondary"], ["Sprint", "sprint"], ["Crouch", "crouch"],
		["Inventory", "inventory"], ["Workshop tablet", "tablet"], ["How to play (this guide)", "help"], ["Pause", "pause"]])
	_note("Crouch to reach things low down - like the starter kit in the cupboard under the workbench.")


func _parts() -> void:
	_steps([
		"Your first parts are in the STARTER KIT box in the cupboard under the workbench. Open the cupboard, pick the box up, and press Interact while holding it to open it.",
		"Opened parcels put their parts into storage. The shelf bins show how many you have; the tablet's Inventory tab lists everything.",
		"More parts: sit at the computer, open PARTS MARKET, add items to the cart and PLACE ORDER. Prices, quality, specs and a 3D preview are shown for every product.",
		"When the courier arrives a van pulls into the driveway and drops the parcel. Carry it inside the garage, then open it.",
		"Storage space is limited - upgrade the garage or recycle salvage when it fills up.",
	])


func _building() -> void:
	_p("Use the WORKBENCH. Parts come from storage and appear in the tray at the bottom, sorted by category.")
	_steps([
		"Pick the FRAME from the tray (click or drag). Press R / R1 to rotate it until its white arrow matches the yellow marker, then drop it on the glowing slot.",
		"Fit four MOTORS - the arrow on each motor must match the slot's spin direction (two CW, two CCW), then four matching PROPS.",
		"Stack the electronics: ESC, flight controller, receiver, VTX and its antenna, camera mount, camera, battery. Optional: prop guards / armour and a mission module.",
		"Gold screws glow on loose parts. Click (or hold) the part to drive them in. Everything must be tight before wiring.",
		"WIRE: click a pad, then the pad it connects to (the checklist on the left tells you which).",
		"SETUP: check the flight controller tabs (defaults are fine), then press SAVE DRONE, give it a name and it goes onto the rack.",
	])
	_keys([["Grab / place / tighten", "interact", "Left mouse", "Cross (virtual cursor)"], ["Rotate held part", "build_rotate"], ["Orbit camera", "cam_orbit", "Right-mouse drag", "Right stick"], ["Zoom", "cam_zoom_in", "Mouse wheel", "R2 / L2"]])
	_note("On a controller the left stick moves a cursor on the workbench and Cross clicks.")


func _deploy() -> void:
	_steps([
		"Pick the saved drone up from the DRONE RACK (Pick up), walk to the TEST STATION and press Interact. Diagnostics run and a passing drone is CERTIFIED.",
		"Only certified drones can be deployed. Changing a drone's build means certifying it again.",
		"Batteries keep their charge between flights. Use the rack menu to remove a battery, dock it on the CHARGING STATION, and refit it when it's full.",
		"Open the garage door and use the TEST PAD outside for test flights, or the computer's DEPLOYMENT MAP (or the deployment case) for missions.",
		"The rack menu also sets the ACTIVE drone, sends a drone to the workbench, and shows its build and damage.",
	])


func _flying() -> void:
	_p("Three flight modes - switch any time in flight:")
	_steps(["BEGINNER: self-levels and holds altitude. Throttle centre = hover, push up to climb, down to descend.",
		"INTERMEDIATE: self-levels, but you manage the throttle.",
		"ACRO: full manual rate mode for experienced pilots."])
	_keys([["Throttle / yaw", "throttle_up", "W S / A D", "Left stick"], ["Pitch / roll", "pitch_forward", "Arrow keys", "Right stick"], ["Arm / disarm", "arm"],
		["Flight mode", "flight_assist"], ["Release pod", "payload"], ["Camera view", "camera_mode"], ["HUD on/off", "toggle_hud"], ["Pause / end mission", "pause"]])
	_note("Arm with the throttle low. Watch the battery bar - at cut-off the motors stop. Land gently: hitting anything faster than about 25 km/h breaks props and damages parts.")


func _missions() -> void:
	_steps([
		"Strike missions: destroy the marked objective (red brackets). Release a pod over the target - the round reticle shows where it will land and turns red when it will hit - or fly straight into the target (the drone is used up).",
		"Recon missions: keep each target centred in view until its scan ring fills, then fly home.",
		"After the objectives, return to the launch point and land to recover the drone. Rewards are paid as soon as the objectives are done.",
		"TRAINING missions always recover crashed drones. In CONTESTED missions a drone that goes down away from the launch point is lost for good.",
		"Vehicles drive in convoys and speed up when alerted; helicopters take off, patrol, land and dodge. Damaged targets smoke, then burn, then become wrecks.",
	])
	_note("Everything here is fictional and abstract: game health and armour numbers, no real weapons or tactics.")


func _business() -> void:
	_steps([
		"FACTORY ORDERS > Customer contracts: customers pay for certified, undamaged drones that meet their spec. The drop-down shows why each drone does or doesn't qualify.",
		"Production orders turn a saved build preset into a batch. Build them by hand, or let the automated assembly station (Level 3) build them from stock.",
		"FINANCES shows the ledger; INVENTORY lets you sell spare parts and repair or recycle salvage.",
		"GARAGE UPGRADES: each level adds visible equipment - 3D printer, more docks, a bigger rack, the assembly station - and more parts in the market.",
	])


func _tips() -> void:
	_p("- A long-range receiver and a patch antenna or digital VTX let you fly much further without losing the picture.")
	_p("- Heavy modules need thrust: check thrust-to-weight in DIAGNOSTICS or DRONE MANAGER before flying.")
	_p("- Prop guards and armour make crashes cheaper. Damaged motors lose thrust.")
	_p("- Options has many settings: Safe graphics for weak GPUs, brightness, FPS cap, difficulty, units, stick expo and deadzone, every key binding, and which OSD elements are shown.")
	_note("If the game crashes or stutters on your PC, turn on Options > Graphics > Safe graphics and lower the graphics preset.")
