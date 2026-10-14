class_name SetupStage
extends Node
## SETUP stage: a Betaflight-style configurator (UI only). Tabs: Firmware, Gyro,
## Port, PID, Motor. "Save & Fly" sends the drone out.

const MISSIONS := ["free_flight", "gate_race", "battery_challenge"]
const MISSION_BLURB := {
	"free_flight": "Roam freely over the hills, trees and lake. Practise and test your tune.",
	"gate_race": "Fly through 12 floating rings in order against the clock. Finish it to unlock new parts; beat the par time for bragging rights.",
	"battery_challenge": "Fly the whole route on ONE battery. Manage your current - throttle discipline wins.",
}

var ws: Workshop
var active := false

var _ui: Control
var _tabs: TabContainer
var _gyro: GyroView
var _gyro_labels: Dictionary = {}
var _mission_opt: OptionButton
var _mission_info: Label
var _fw_labels: Dictionary = {}
var _fw_status: RichTextLabel
var _sliders: Dictionary = {}        # key -> {"slider": HSlider, "label": Label}
var _rate_chart: RateChart
var _step_chart: StepChart
var _tune_label: Label
var _tune_axis := "roll"
var _motor_diagram: MotorDiagram
var _motor_sliders: Array = []
var _motor_bars: Array = []
var _motor_vals: Array = []
var _motor_hold: Array = [false, false, false, false]
var _motor_out: Array = [1000.0, 1000.0, 1000.0, 1000.0]
var _vtx_cb: CheckBox
var _rx_cb: CheckBox
var _port_note: Label
var _suspend := false


func _ready() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	ws.ui_root.add_child(_ui)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.075, 0.095)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 36)
	m.add_theme_constant_override("margin_right", 36)
	m.add_theme_constant_override("margin_top", 92)
	m.add_theme_constant_override("margin_bottom", 24)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(UITheme.label("CONFIGURATOR", 30, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UITheme.label("Board: PWASHF4  •  Firmware PROPWASH 4.5.0", 18, UITheme.MUTED))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 22)
	vb.add_child(_tabs)
	_tabs.add_child(_make_firmware_tab())
	_tabs.add_child(_make_gyro_tab())
	_tabs.add_child(_make_port_tab())
	_tabs.add_child(_make_pid_tab())
	_tabs.add_child(_make_motor_tab())
	_tabs.tab_changed.connect(func(_i: int): Audio.play("click", 1.2))

	# footer
	var foot := PanelContainer.new()
	vb.add_child(foot)
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 16)
	foot.add_child(fh)
	fh.add_child(UITheme.button("<< WIRE", func(): ws.switch_stage("wire"), Vector2(130, 52)))
	fh.add_child(UITheme.label("Mission:", 22))
	_mission_opt = OptionButton.new()
	_mission_opt.custom_minimum_size = Vector2(300, 52)
	for mid in MISSIONS:
		var suffix := ""
		if mid != "free_flight" and SaveData.best_time(mid) > 0.0:
			suffix = "   (best %s)" % _fmt(SaveData.best_time(mid))
		_mission_opt.add_item(Parts.MISSION_NAMES[mid] + suffix)
	_mission_opt.item_selected.connect(func(i: int):
		Game.mission = MISSIONS[i]
		_update_mission_info())
	fh.add_child(_mission_opt)
	_mission_info = UITheme.label("", 18, UITheme.MUTED)
	_mission_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fh.add_child(_mission_info)
	fh.add_child(UITheme.accent_button("SAVE & FLY", save_and_fly, Vector2(260, 60)))
	set_active(false)


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


# --- helpers -----------------------------------------------------------------------------
func _tab_root(title: String) -> MarginContainer:
	var m := MarginContainer.new()
	m.name = title
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	return m


func _panel(title: String, min_w: float = 0.0) -> Array:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(min_w, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UITheme.label(title, 22, UITheme.ACCENT))
	return [p, v]


func _slider_key(key: String, lo: float, hi: float, step: float, value: float, fmt: String, cb: Callable, width: float = 200.0) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var s := UITheme.slider(lo, hi, step, value)
	s.custom_minimum_size = Vector2(width, 28)
	var l := UITheme.label(fmt % value, 18, UITheme.ACCENT)
	l.custom_minimum_size = Vector2(62, 0)
	s.value_changed.connect(func(x: float):
		l.text = fmt % x
		if not _suspend:
			cb.call(x))
	hb.add_child(s)
	hb.add_child(l)
	_sliders[key] = {"slider": s, "label": l, "fmt": fmt}
	return hb


func _set_slider(key: String, v: float) -> void:
	var d: Dictionary = _sliders[key]
	d["slider"].value = v
	d["label"].text = d["fmt"] % v


# --- FIRMWARE ------------------------------------------------------------------------------
func _make_firmware_tab() -> Control:
	var root := _tab_root("Firmware")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	root.add_child(h)

	var a := _panel("Flight controller")
	h.add_child(a[0])
	for k in ["Target", "Firmware", "Gyro", "Loop rate", "Sensors", "Link"]:
		var l := UITheme.label("", 20)
		_fw_labels[k] = l
		a[1].add_child(l)
	_fw_status = RichTextLabel.new()
	_fw_status.bbcode_enabled = true
	_fw_status.fit_content = true
	_fw_status.add_theme_font_size_override("normal_font_size", 18)
	_fw_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	a[1].add_child(_fw_status)

	var b := _panel("Airframe")
	h.add_child(b[0])
	for k in ["Frame", "Motors", "Props", "Battery", "AUW", "Thrust-to-weight", "Hover throttle", "Hover current", "Hover endurance", "Max current"]:
		var l := UITheme.label("", 20)
		_fw_labels[k] = l
		b[1].add_child(l)

	var c := _panel("Presets & options")
	h.add_child(c[0])
	c[1].add_child(UITheme.label("Tuning preset", 20))
	var ob := OptionButton.new()
	for p in FlightMath.PRESETS:
		ob.add_item(p)
	ob.custom_minimum_size = Vector2(300, 46)
	ob.item_selected.connect(func(i: int):
		FlightMath.apply_preset(Game.cfg, FlightMath.PRESETS.keys()[i])
		_pull_cfg()
		Audio.play("snap"))
	_fw_labels["preset_opt"] = ob
	c[1].add_child(ob)
	c[1].add_child(UITheme.label("Flight mode at take-off", 20))
	var fm := OptionButton.new()
	fm.add_item("Acro (rate) - full manual")
	fm.add_item("Angle (self-level) - beginner friendly")
	fm.custom_minimum_size = Vector2(300, 46)
	fm.item_selected.connect(func(i: int):
		if not _suspend:
			Game.cfg["angle_mode"] = (i == 1))
	_fw_labels["angle_opt"] = fm
	c[1].add_child(fm)
	var fmn := UITheme.label("Press V in flight to switch between the two modes.", 16, UITheme.MUTED)
	c[1].add_child(fmn)
	c[1].add_child(UITheme.label("FPV camera angle (up-tilt)", 20))
	c[1].add_child(_slider_key("cam_angle", 0, 45, 1, Game.cfg["cam_angle"], "%d°", func(x: float): Game.cfg["cam_angle"] = x, 280))
	var note := UITheme.label("A steeper tilt lets you fly faster with the camera still looking forward - but the view drops towards the ground when hovering.", 16, UITheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(380, 0)
	c[1].add_child(note)
	c[1].add_child(UITheme.button("Reset everything to defaults", func():
		Game.cfg = Game.default_cfg()
		_pull_cfg()
		ws.say("Configuration reset to defaults.", true), Vector2(320, 46)))
	return root


func _refresh_firmware() -> void:
	var s := Game.stats()
	if not s["complete"]:
		return
	_fw_labels["Target"].text = "Target:   PWASHF4 (F4 flight controller)"
	_fw_labels["Firmware"].text = "Firmware:   PROPWASH 4.5.0  (Betaflight-compatible UI)"
	_fw_labels["Gyro"].text = "Gyro:   detected - ICM-42688 (simulated)"
	_fw_labels["Loop rate"].text = "Loop rate:   %d Hz (sim)" % int(1.0 / FlightMath.LOOP_DT)
	_fw_labels["Sensors"].text = "Sensors:   ACC  GYRO  CURRENT %s" % ("[ON]" if Game.wires.has("cur") else "[not wired]")
	_fw_labels["Link"].text = "Link:   RX %s   VTX %s" % ["ON" if Game.cfg["rx_enabled"] else "OFF", "ON" if Game.cfg["vtx_enabled"] else "OFF"]
	_fw_labels["Frame"].text = "Frame:   " + s["frame_name"]
	_fw_labels["Motors"].text = "Motors:   4 x " + s["motor_name"]
	_fw_labels["Props"].text = "Props:   %s  (%.1f\")" % [s["prop_name"], s["prop_in"]]
	_fw_labels["Battery"].text = "Battery:   " + s["battery_name"]
	_fw_labels["AUW"].text = "All-up weight:   %.0f g" % s["mass_g"]
	_fw_labels["Thrust-to-weight"].text = "Thrust-to-weight:   %.1f : 1" % s["twr"]
	var w_h: float = sqrt(s["mass"] * 9.81 / (4.0 * s["thrust_full"]))
	var c_h: float = w_h / 0.88
	var stick: float = clampf((c_h - FlightMath.IDLE) / (1.0 - FlightMath.IDLE), 0.0, 1.0)
	var amps: float = 4.0 * (0.1 + s["amps_full"] * pow(w_h, 2.2) / 0.88) + DroneSim.BASE_LOAD_A
	_fw_labels["Hover throttle"].text = "Hover throttle:   ~%d %%" % int(stick * 100.0)
	_fw_labels["Hover current"].text = "Hover current:   ~%.1f A" % amps
	var minutes: float = s["capacity_mah"] * 0.001 * 0.85 / amps * 60.0
	_fw_labels["Hover endurance"].text = "Hover endurance:   ~%.1f min" % minutes
	_fw_labels["Max current"].text = "Full-throttle current:   ~%.0f A" % (4.0 * s["amps_full"] * 0.7)
	var txt := ""
	txt += "[color=#7CFC8A]OK[/color]  All required parts detected.\n"
	txt += "[color=#7CFC8A]OK[/color]  Motor signal wires: M1-M4.\n"
	txt += ("[color=#7CFC8A]OK[/color]  Current sensor wired - total amps on HUD.\n" if Game.wires.has("cur") else "[color=#FFD060]WARN[/color]  CUR pin not wired - HUD total amps unavailable.\n")
	if not Game.cfg["rx_enabled"]:
		txt += "[color=#FF6050]FAIL[/color]  Receiver UART disabled (Port tab): you will not be able to arm!\n"
	if not Game.cfg["vtx_enabled"]:
		txt += "[color=#FF6050]FAIL[/color]  VTX UART disabled (Port tab): no video feed!\n"
	if s["twr"] < 2.5:
		txt += "[color=#FFD060]WARN[/color]  Thrust-to-weight is low - expect a sluggish flight.\n"
	_fw_status.text = txt
	var opt: OptionButton = _fw_labels["preset_opt"]
	var names: Array = FlightMath.PRESETS.keys()
	opt.select(maxi(names.find(Game.cfg.get("preset", "Freestyle")), 0))


# --- GYRO ----------------------------------------------------------------------------------
func _make_gyro_tab() -> Control:
	var root := _tab_root("Gyro")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	root.add_child(h)
	var left := _panel("Live attitude")
	left[0].size_flags_stretch_ratio = 1.6
	h.add_child(left[0])
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(700, 480)
	left[1].add_child(holder)
	_gyro = GyroView.new()
	_gyro.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_gyro)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseMotion:
			if ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_gyro.drag(ev.relative.x, ev.relative.y, false)
			elif ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_gyro.drag(ev.relative.x, 0.0, true)
		elif ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				_gyro.roll = clampf(_gyro.roll + 4.0, -180, 180)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_gyro.roll = clampf(_gyro.roll - 4.0, -180, 180))
	holder.add_child(overlay)
	left[1].add_child(UITheme.label("Drag: yaw / pitch   •   Right-drag or wheel: roll", 17, UITheme.MUTED))

	var right := _panel("Readouts")
	h.add_child(right[0])
	for k in ["Roll", "Pitch", "Yaw"]:
		var l := UITheme.label("", 44, Color.WHITE)
		_gyro_labels[k] = l
		right[1].add_child(l)
	var rl := UITheme.label("", 20, UITheme.MUTED)
	_gyro_labels["rates"] = rl
	right[1].add_child(rl)
	right[1].add_child(UITheme.button("Calibrate accelerometer", func():
		_gyro.calibrate()
		ws.say("Accelerometer calibrated.", true), Vector2(300, 46)))
	right[1].add_child(UITheme.label("Gyro low-pass filter", 20))
	right[1].add_child(_slider_key("gyro_lpf", 30, 300, 5, Game.cfg["gyro_lpf"], "%d Hz", func(x: float):
		Game.cfg["gyro_lpf"] = x
		_update_tune(), 300))
	var n := UITheme.label("Lower cut-off = smoother but laggier gyro (more phase lag -> oscillation at high P).\nHigher cut-off = crisper but noisier (D-term amplifies noise).", 16, UITheme.MUTED)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(380, 0)
	right[1].add_child(n)
	return root


# --- PORT ------------------------------------------------------------------------------------
func _make_port_tab() -> Control:
	var root := _tab_root("Port")
	var p := _panel("Ports")
	root.add_child(p[0])
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 60)
	g.add_theme_constant_override("v_separation", 16)
	p[1].add_child(g)
	for hd in ["Identifier", "Configuration / MSP", "Serial Rx", "Peripherals"]:
		g.add_child(UITheme.label(hd, 20, UITheme.ACCENT))
	# USB
	g.add_child(UITheme.label("USB VCP", 20))
	var usb := CheckBox.new()
	usb.button_pressed = true
	usb.disabled = true
	g.add_child(usb)
	g.add_child(Control.new())
	g.add_child(UITheme.label("-", 20, UITheme.MUTED))
	# UART1: VTX
	g.add_child(UITheme.label("UART1", 20))
	g.add_child(Control.new())
	g.add_child(Control.new())
	_vtx_cb = CheckBox.new()
	_vtx_cb.text = "VTX (SmartAudio / video transmitter)"
	_vtx_cb.add_theme_font_size_override("font_size", 20)
	_vtx_cb.toggled.connect(func(on: bool):
		if not _suspend:
			Game.cfg["vtx_enabled"] = on
			_update_port_note())
	g.add_child(_vtx_cb)
	# UART2: RX
	g.add_child(UITheme.label("UART2", 20))
	g.add_child(Control.new())
	_rx_cb = CheckBox.new()
	_rx_cb.text = "Receiver"
	_rx_cb.add_theme_font_size_override("font_size", 20)
	_rx_cb.toggled.connect(func(on: bool):
		if not _suspend:
			Game.cfg["rx_enabled"] = on
			_update_port_note())
	g.add_child(_rx_cb)
	g.add_child(UITheme.label("-", 20, UITheme.MUTED))
	# UART3
	g.add_child(UITheme.label("UART3", 20, UITheme.MUTED))
	for i in 3:
		var cb := CheckBox.new()
		cb.disabled = true
		g.add_child(cb if i < 2 else UITheme.label("(unused)", 18, UITheme.MUTED))
	p[1].add_child(UITheme.label("VTX output power", 20))
	var pw := OptionButton.new()
	for t in ["25 mW  (short range)", "200 mW  (medium)", "600 mW  (long range)"]:
		pw.add_item(t)
	pw.custom_minimum_size = Vector2(300, 46)
	pw.item_selected.connect(func(i: int):
		Game.cfg["vtx_power"] = i)
	pw.set_meta("is_power", true)
	_fw_labels["vtx_power"] = pw
	p[1].add_child(pw)
	_port_note = UITheme.label("", 20, UITheme.TEXT)
	_port_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p[1].add_child(_port_note)
	return root


func _update_port_note() -> void:
	var t := ""
	if not Game.cfg["rx_enabled"]:
		t += "Receiver UART is OFF: the flight controller gets no stick commands, so the quad will refuse to arm.\n"
	if not Game.cfg["vtx_enabled"]:
		t += "VTX UART is OFF: the video transmitter is not configured - you will fly blind (pure static).\n"
	if t == "":
		t = "Both UARTs enabled. Higher VTX power extends the distance before the analog video breaks up."
	_port_note.text = t
	_port_note.add_theme_color_override("font_color", UITheme.TEXT if Game.cfg["rx_enabled"] and Game.cfg["vtx_enabled"] else UITheme.BAD)


# --- PID ------------------------------------------------------------------------------------------
func _make_pid_tab() -> Control:
	var root := _tab_root("PID")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	root.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	v.add_child(top)

	var pp := _panel("PID gains  (P  I  D)")
	top.add_child(pp[0])
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	pp[1].add_child(g)
	g.add_child(Control.new())
	for c in ["P", "I", "D"]:
		g.add_child(UITheme.label(c, 20, UITheme.ACCENT))
	for axis in ["roll", "pitch", "yaw"]:
		g.add_child(UITheme.label(axis.capitalize(), 20))
		for term in ["p", "i", "d"]:
			var ax: String = axis
			var tm: String = term
			g.add_child(_slider_key("pid_%s_%s" % [axis, term], 0, 200, 1, Game.cfg["pid"][axis][term], "%d", func(x: float):
				Game.cfg["pid"][ax][tm] = int(x)
				_tune_axis = ax
				_update_tune(), 190))

	var rp := _panel("Rates  (center sens / max rate / expo)")
	top.add_child(rp[0])
	var rg := GridContainer.new()
	rg.columns = 4
	rg.add_theme_constant_override("h_separation", 14)
	rg.add_theme_constant_override("v_separation", 8)
	rp[1].add_child(rg)
	rg.add_child(Control.new())
	for c in ["Center", "Max", "Expo"]:
		rg.add_child(UITheme.label(c, 20, UITheme.ACCENT))
	for axis in ["roll", "pitch", "yaw"]:
		rg.add_child(UITheme.label(axis.capitalize(), 20))
		var ax: String = axis
		rg.add_child(_slider_key("rate_%s_center" % axis, 20, 300, 5, Game.cfg["rates"][axis]["center"], "%d", func(x: float):
			Game.cfg["rates"][ax]["center"] = x
			_update_charts(), 190))
		rg.add_child(_slider_key("rate_%s_max" % axis, 200, 1000, 10, Game.cfg["rates"][axis]["max"], "%d", func(x: float):
			Game.cfg["rates"][ax]["max"] = x
			_update_charts(), 190))
		rg.add_child(_slider_key("rate_%s_expo" % axis, 0, 1, 0.01, Game.cfg["rates"][axis]["expo"], "%.2f", func(x: float):
			Game.cfg["rates"][ax]["expo"] = x
			_update_charts(), 190))

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	_rate_chart = RateChart.new()
	_rate_chart.custom_minimum_size = Vector2(700, 240)
	_rate_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rate_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_rate_chart)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(sv)
	_step_chart = StepChart.new()
	_step_chart.custom_minimum_size = Vector2(700, 200)
	_step_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(_step_chart)
	_tune_label = UITheme.label("", 22, UITheme.GOOD)
	sv.add_child(_tune_label)
	return root


func _update_charts() -> void:
	_rate_chart.rates = Game.cfg["rates"]
	_rate_chart.queue_redraw()


func _update_tune() -> void:
	var s := Game.stats()
	if not s["complete"]:
		return
	var r := FlightMath.step_response(s, Game.cfg, _tune_axis)
	_step_chart.samples = r["samples"]
	_step_chart.rating = r["rating"]
	_step_chart.queue_redraw()
	_tune_label.text = "%s axis:  %s" % [_tune_axis.capitalize(), r["status"]]
	_tune_label.add_theme_color_override("font_color", [UITheme.BAD, Color(1.0, 0.7, 0.2), Color(1.0, 0.85, 0.3), UITheme.GOOD][r["rating"]])


# --- MOTOR -----------------------------------------------------------------------------------------
func _make_motor_tab() -> Control:
	var root := _tab_root("Motor")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	root.add_child(h)
	var left := _panel("Motor direction check")
	h.add_child(left[0])
	_motor_diagram = MotorDiagram.new()
	_motor_diagram.custom_minimum_size = Vector2(560, 480)
	_motor_diagram.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left[1].add_child(_motor_diagram)
	var hint := UITheme.label("Hold  1 / 2 / 3 / 4  (or the on-screen buttons) to spin a motor.\nCheck the arrow matches the motor's rotation and the wiring order.", 17, UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left[1].add_child(hint)

	var right := _panel("Motors  (1000 = stopped, 2000 = full)")
	h.add_child(right[0])
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right[1].add_child(cols)
	for i in 4:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		var t := UITheme.label("Motor %d" % (i + 1), 22, Color.WHITE)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
		var sub := UITheme.label("ESC%d • %s" % [i + 1, Parts.MOTOR_SPIN[i]], 17, UITheme.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(row)
		var bar := ProgressBar.new()
		bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		bar.min_value = 1000
		bar.max_value = 2000
		bar.value = 1000
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(46, 300)
		bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		var sl := VSlider.new()
		sl.min_value = 1000
		sl.max_value = 2000
		sl.step = 5
		sl.value = 1300
		sl.focus_mode = Control.FOCUS_NONE
		sl.custom_minimum_size = Vector2(30, 300)
		sl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(sl)
		var vl := UITheme.label("1000", 24, UITheme.ACCENT)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(vl)
		var hold := Button.new()
		hold.text = "Hold to spin [%s]" % (i + 1)
		hold.focus_mode = Control.FOCUS_NONE
		hold.custom_minimum_size = Vector2(0, 46)
		var idx := i
		hold.button_down.connect(func(): _motor_hold[idx] = true)
		hold.button_up.connect(func(): _motor_hold[idx] = false)
		col.add_child(hold)
		_motor_bars.append(bar)
		_motor_sliders.append(sl)
		_motor_vals.append(vl)
	return root


func _process(dt: float) -> void:
	if not active:
		return
	# gyro readouts
	if _tabs.current_tab == 1:
		_gyro_labels["Roll"].text = "Roll    %+6.1f°" % _gyro.roll
		_gyro_labels["Pitch"].text = "Pitch  %+6.1f°" % _gyro.pitch
		_gyro_labels["Yaw"].text = "Yaw     %5.1f°" % _gyro.heading()
		_gyro_labels["rates"].text = "Gyro rates (deg/s):  roll %+.0f   pitch %+.0f   yaw %+.0f" % [_gyro.rates.x, _gyro.rates.y, _gyro.rates.z]
	# motors
	var any := 0.0
	var key_spin := false
	for i in 4:
		var held: bool = _motor_hold[i] or Input.is_action_pressed("motor_test_%d" % (i + 1))
		var target: float = _motor_sliders[i].value if held else 1000.0
		_motor_out[i] = lerpf(_motor_out[i], target, 0.35)
		_motor_bars[i].value = _motor_out[i]
		_motor_vals[i].text = "%d" % int(round(_motor_out[i]))
		_motor_diagram.outputs[i] = clampf((_motor_out[i] - 1000.0) / 1000.0, 0.0, 1.0)
		any = maxf(any, _motor_diagram.outputs[i])
		key_spin = key_spin or held
	Audio.motor_level = any * 0.5 if _tabs.current_tab == 4 else 0.0
	Audio.motor_pitch = any * 0.6


# --- state sync -----------------------------------------------------------------------------------------
func _pull_cfg() -> void:
	_suspend = true
	var c: Dictionary = Game.cfg
	_set_slider("cam_angle", c["cam_angle"])
	_set_slider("gyro_lpf", c["gyro_lpf"])
	for axis in ["roll", "pitch", "yaw"]:
		for term in ["p", "i", "d"]:
			_set_slider("pid_%s_%s" % [axis, term], c["pid"][axis][term])
		_set_slider("rate_%s_center" % axis, c["rates"][axis]["center"])
		_set_slider("rate_%s_max" % axis, c["rates"][axis]["max"])
		_set_slider("rate_%s_expo" % axis, c["rates"][axis]["expo"])
	_vtx_cb.button_pressed = c["vtx_enabled"]
	_rx_cb.button_pressed = c["rx_enabled"]
	(_fw_labels["vtx_power"] as OptionButton).select(c["vtx_power"])
	(_fw_labels["angle_opt"] as OptionButton).select(1 if c.get("angle_mode", false) else 0)
	_suspend = false
	_update_port_note()
	_update_charts()
	_update_tune()
	_refresh_firmware()


func set_active(on: bool) -> void:
	active = on
	_ui.visible = on
	if on:
		_pull_cfg()
		_gyro.rebuild()
		_mission_opt.select(maxi(MISSIONS.find(Game.mission), 0))
		_update_mission_info()
		Audio.motor_level = 0.0
	else:
		Audio.motor_level = 0.0
		for i in 4:
			_motor_hold[i] = false
		Game.save_drone()


func _update_mission_info() -> void:
	_mission_info.text = MISSION_BLURB[Game.mission]


func save_and_fly() -> void:
	var r := Game.ready_to_fly()
	if not r["ok"]:
		ws.say(r["reason"])
		Audio.play("error")
		return
	Game.save_drone()
	var warn := ""
	if not Game.cfg["rx_enabled"]:
		warn = "Warning: receiver UART is off - you won't be able to arm!"
	elif not Game.cfg["vtx_enabled"]:
		warn = "Warning: VTX UART is off - video will be static."
	if warn != "":
		ws.say(warn, false, 2.5)
	Audio.play("arm")
	Game.goto("fly")
