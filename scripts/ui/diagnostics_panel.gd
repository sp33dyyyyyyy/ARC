class_name DiagnosticsPanel
extends Control
## Virtual diagnostics for a roster drone: an animated check sequence (power, FC, link,
## video, motor spin test, structure, battery) followed by a performance report.
## Passing on the physical test station certifies the drone for deployment.

signal closed
signal motor_spin(level: float)

var drone_id := ""
var can_certify := true
var _log: VBoxContainer
var _report: Label
var _bar: ProgressBar
var _running := false
var _spin := 0.0
var _btn_run: Button


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var p := PanelContainer.new()
	p.position = Vector2(300, 90)
	p.size = Vector2(1320, 900)
	p.add_theme_stylebox_override("panel", UITheme.flat(Color(0.03, 0.06, 0.045, 0.97), 10, Color(0.3, 1.0, 0.5, 0.5), 2, 22))
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var d := Career.get_drone(drone_id)
	v.add_child(UITheme.label("DIAGNOSTICS  -  %s" % d.get("name", "?"), 30, Color(0.5, 1.0, 0.6)))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(1260, 18)
	_bar.show_percentage = false
	v.add_child(_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_log = VBoxContainer.new()
	_log.custom_minimum_size = Vector2(520, 0)
	h.add_child(_log)
	_report = UITheme.label("", 19, Color(0.8, 1.0, 0.85))
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report.custom_minimum_size = Vector2(700, 0)
	h.add_child(_report)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	v.add_child(bh)
	_btn_run = UITheme.accent_button("RUN DIAGNOSTICS", run, Vector2(300, 52))
	bh.add_child(_btn_run)
	var spin := UITheme.button("Hold: motor spin test", Callable(), Vector2(300, 52))
	spin.button_down.connect(func(): _spin = 0.45)
	spin.button_up.connect(func(): _spin = 0.0)
	bh.add_child(spin)
	bh.add_child(UITheme.button("Close", func():
		Audio.motor_level = 0.0
		closed.emit(), Vector2(160, 52)))
	_report.text = Report.text(d)
	Pad.focus_first(self, true)


func _process(dt: float) -> void:
	if _spin > 0.0 or _running:
		Audio.motor_level = maxf(_spin, Audio.motor_level * 0.95)
		Audio.motor_pitch = maxf(_spin, 0.2)
		motor_spin.emit(maxf(_spin, 0.2) * dt * 60.0)
	elif Audio.motor_level > 0.0:
		Audio.motor_level = 0.0


func _exit_tree() -> void:
	Audio.motor_level = 0.0


func run() -> void:
	if _running:
		return
	_running = true
	_btn_run.disabled = true
	for c in _log.get_children():
		c.queue_free()
	var d := Career.get_drone(drone_id)
	var checks := Report.checks(d)
	var all_ok := true
	for i in checks.size():
		var c: Dictionary = checks[i]
		var l := UITheme.label("…  %s" % c["name"], 20, UITheme.MUTED)
		_log.add_child(l)
		if c.get("spin", false):
			_spin = 0.55
		await get_tree().create_timer(0.45).timeout
		if not is_inside_tree():
			return
		_spin = 0.0
		var ok: bool = c["ok"]
		var warn: bool = c.get("warn", false)
		l.text = "%s  %s%s" % ["OK  " if ok and not warn else ("WARN" if ok else "FAIL"), c["name"], "" if c.get("note", "") == "" else "  -  " + c["note"]]
		l.add_theme_color_override("font_color", UITheme.GOOD if ok and not warn else (UITheme.ACCENT if ok else UITheme.BAD))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(520, 0)
		Audio.play("beep" if ok else "error", 1.0 + i * 0.03)
		_bar.value = 100.0 * (i + 1) / checks.size()
		all_ok = all_ok and ok
	_running = false
	_btn_run.disabled = false
	if all_ok and can_certify:
		d["certified"] = true
		Career.mark_dirty()
		Career.save()
		Audio.play("success")
		Pad.rumble(0.3, 0.2, 0.3)
		_report.text = "CERTIFIED FOR DEPLOYMENT\n\n" + Report.text(d)
	elif all_ok:
		_report.text = "All checks passed (connect it to the test station to certify).\n\n" + Report.text(d)
	else:
		d["certified"] = false
		Career.mark_dirty()
		_report.text = "NOT CERTIFIED - fix the failed checks at the workbench.\n\n" + Report.text(d)


## Shared check list / report text (also used by the Workshop OS DIAGNOSTICS app).
class Report:
	static func checks(d: Dictionary) -> Array:
		var st := Career.drone_stats(d)
		var out: Array = []
		var complete: bool = st.get("complete", false)
		out.append({"name": "Airframe & component inventory", "ok": complete, "note": "" if complete else "missing " + st.get("missing_text", "")})
		if not complete:
			return out
		var wires_ok := Parts.missing_wires(d.get("wires", [])).is_empty()
		out.append({"name": "Power-on & wiring continuity", "ok": wires_ok, "note": "" if wires_ok else "unwired: " + ", ".join(Parts.missing_wires(d.get("wires", [])))})
		out.append({"name": "Flight controller & gyro", "ok": float(d["cond"].get("fc", 1.0)) > 0.3, "warn": float(d["cond"].get("fc", 1.0)) < 0.8})
		out.append({"name": "Control receiver link", "ok": d["cfg"].get("rx_enabled", true) and float(d["cond"].get("rx", 1.0)) > 0.3, "note": "range ~%d m" % int(st["rx_range"])})
		out.append({"name": "Video link (VTX / antenna / camera)", "ok": float(d["cond"].get("vtx", 1.0)) > 0.25 and float(d["cond"].get("cam", 1.0)) > 0.2, "warn": st["cam_noise"] > 0.15, "note": "%s, gain x%.2f" % ["digital" if st["digital"] else "analogue", st["video_gain"]]})
		var mh: Array = st["motor_health"]
		var worst := 1.0
		for x in mh:
			worst = minf(worst, x)
		out.append({"name": "Motor spin test M1-M4", "ok": worst > 0.6, "warn": worst < 0.9, "spin": true, "note": "weakest motor %d %%" % int(worst * 100.0)})
		out.append({"name": "Propellers", "ok": st["broken_props"] == 0, "note": "" if st["broken_props"] == 0 else "%d broken" % st["broken_props"]})
		out.append({"name": "Structural check (frame)", "ok": float(d["cond"].get("frame", 1.0)) > 0.25, "warn": float(d["cond"].get("frame", 1.0)) < 0.8})
		out.append({"name": "Thrust-to-weight", "ok": st["twr"] > 1.6, "warn": st["twr"] < 3.0, "note": "%.1f : 1" % st["twr"]})
		out.append({"name": "Battery pack", "ok": d.get("battery_in", true), "warn": float(d.get("charge", 1.0)) < 0.5, "note": "%d %% charged%s" % [int(float(d.get("charge", 1.0)) * 100.0), "" if d.get("battery_in", true) else ", NOT FITTED"]})
		return out

	static func text(d: Dictionary) -> String:
		var st := Career.drone_stats(d)
		if not st.has("twr"):
			return "No frame installed."
		var t: Array = []
		t.append("%s" % st["frame_name"])
		t.append("Motors %s   Props %s" % [st["motor_name"], st["prop_name"]])
		t.append("")
		t.append("All-up weight     %d g" % int(st["mass_g"]))
		t.append("Thrust-to-weight  %.1f : 1" % st["twr"])
		t.append("Hover throttle    %d %%" % int(st["hover_throttle"] * 100.0))
		t.append("Hover current     %.1f A" % st["hover_amps"])
		t.append("Endurance (hover) %.1f min" % st["endurance_min"])
		t.append("Top speed (est.)  %d km/h" % int(st["top_kmh"]))
		t.append("Agility           %d / 100" % int(st["agility"]))
		t.append("Durability        %d / 100" % int(st["durability_pct"]))
		t.append("Control range     %d m" % int(st["rx_range"]))
		t.append("Video             %s, gain x%.2f, camera tilt %d°" % ["digital" if st["digital"] else "analogue", st["video_gain"], int(st["cam_tilt"])])
		if st["payload_id"] != "":
			var p := Parts.part(st["payload_id"])
			t.append("Module            %s%s" % [p["name"], "" if p.get("kind", "") == "scan" else " (%d x power %d)" % [p["charges"], int(p["power"])]])
		t.append("Parts value       %d cr" % st["cost"])
		var w := Parts.build_warnings(st)
		if not w.is_empty():
			t.append("")
			for x in w:
				t.append("! " + x)
		return "\n".join(t)
