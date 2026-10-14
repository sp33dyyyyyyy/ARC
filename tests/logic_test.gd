extends Node
## Headless logic checks (no rendering needed):
##   godot --headless --path . res://tests/logic_test.tscn                 -> general checks + writes a rebinding
##   godot --headless --path . res://tests/logic_test.tscn -- read         -> verifies the rebinding survived a restart

var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + msg)
	if not cond:
		failures += 1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("read"):
		_read_phase()
	else:
		await _main_phase()
	print("FAILURES: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


func _main_phase() -> void:   # async (waits a frame for buffered input)
	print("== build rules ==")
	var placed := {"frame": "frame_5"}
	var m1 := Parts.slot_by_name("frame_5", "motor_1")        # M1 is CCW
	var p1 := Parts.slot_by_name("frame_5", "prop_1")
	check(Parts.check_place(placed, m1, "motor_2306_ccw") == "", "CCW motor accepted on the CCW slot")
	check(Parts.check_place(placed, m1, "motor_2306_cw") != "", "CW motor rejected on the CCW slot (spin direction enforced)")
	check(Parts.check_place(placed, p1, "prop_5143_ccw") != "", "prop rejected before its motor is installed")
	placed["motor_1"] = "motor_2306_ccw"
	check(Parts.check_place(placed, p1, "prop_5143_ccw") == "", "matching-spin prop accepted once the motor exists")
	check(Parts.check_place(placed, p1, "prop_5143_cw") != "", "CW prop rejected on a CCW motor")
	var m2 := Parts.slot_by_name("frame_5", "motor_2")
	check(Parts.check_place(placed, m2, "motor_2207_cw") != "", "mixed motor models rejected")
	check(Parts.check_place({}, Parts.slot_by_name("frame_5", "esc"), "esc_4in1") != "", "nothing installs before the frame")
	check(Parts.check_place({"frame": "frame_5"}, Parts.slot_by_name("frame_5", "fc"), "fc_f4") != "", "FC needs the ESC underneath first")
	check(Parts.placement_is_valid(DroneVisual.default_placement()), "default placement is valid")
	var bad := DroneVisual.default_placement()
	bad["prop_1"] = "prop_5143_cw"
	check(not Parts.placement_is_valid(bad), "a saved build with a wrong-spin prop is rejected")

	print("== wiring rules ==")
	check(Parts.check_connection("fc.M1", "esc.S1")["ok"], "M1 -> ESC1 accepted")
	check(not Parts.check_connection("fc.M1", "esc.S2")["ok"], "M1 -> ESC2 rejected")
	check(not Parts.check_connection("bat.RED", "esc.BATN")["ok"], "red lead on BAT- rejected")
	check(not Parts.check_connection("bat.RED", "esc.CBAT")["ok"], "red lead on the C BAT pad rejected")
	check(not Parts.check_connection("bat.RED", "fc.M1")["ok"], "power onto a signal pad rejected")
	check(Parts.check_connection("bat.RED", "esc.BATP")["ok"] and Parts.check_connection("bat.BLACK", "esc.BATN")["ok"], "battery leads accepted on BAT+/BAT-")
	check(Parts.check_connection("vtx.UART", "fc.UART")["ok"] and Parts.check_connection("cam.OUT", "fc.CAM")["ok"], "VTX->UART and camera->CAM accepted")
	check(not Parts.check_connection("vtx.UART", "fc.CAM")["ok"], "VTX on the camera pad rejected")

	print("== gamepad mapping ==")
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_Y
	ev.axis_value = -1.0       # left stick pushed up
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Input.get_action_strength("throttle_up") > 0.9 and Input.get_action_strength("throttle_down") < 0.01, "left stick up raises throttle")
	ev = InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_RIGHT_X
	ev.axis_value = 1.0
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Input.get_action_strength("roll_right") > 0.9, "right stick right rolls right")
	ev = InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_RIGHT_X
	ev.axis_value = 0.1        # inside the dead zone
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Input.get_action_strength("roll_right") < 0.01, "stick dead zone ignores small deflections")
	var pe := InputEventJoypadButton.new()
	pe.button_index = JOY_BUTTON_A
	pe.pressed = true
	Input.parse_input_event(pe)
	await get_tree().process_frame
	await get_tree().process_frame
	check(Input.is_action_pressed("arm"), "gamepad A arms")
	pe = InputEventJoypadButton.new()
	pe.button_index = JOY_BUTTON_A
	pe.pressed = false
	Input.parse_input_event(pe)

	print("== power model ==")
	var stats := Parts.compute_build(DroneVisual.default_placement(), {})
	check(stats["complete"] and stats["mass_g"] > 300.0, "default build complete, %.0f g" % stats["mass_g"])
	var heavy := DroneVisual.default_placement()
	heavy["battery"] = "bat_2200"
	check(Parts.compute_build(heavy, {})["mass_g"] > stats["mass_g"], "bigger battery makes the build heavier")

	print("== settings / save robustness ==")
	# corrupt settings.cfg -> defaults
	var f := FileAccess.open(Settings.SETTINGS_PATH, FileAccess.WRITE)
	f.store_string("this is [[[ not a config file")
	f.close()
	Settings.graphics_preset = 2
	Settings._reset_bindings()
	Settings.load_settings()
	check(Settings.bindings["throttle_up"]["kb"] == "key:%d" % KEY_W, "corrupt settings.cfg falls back to default bindings")
	# corrupt save.json -> defaults
	f = FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ broken json ")
	f.close()
	SaveData.load_data()
	check(SaveData.is_unlocked("frame_5") and not SaveData.is_unlocked("frame_7"), "corrupt save.json falls back to defaults")
	f = FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	SaveData.load_data()
	check(SaveData.data["unlocked"].size() == SaveData.DEFAULT_UNLOCKED.size(), "wrong-shaped save.json falls back to defaults")
	# save/restore of records
	SaveData.load_data()
	var res := SaveData.record_run("gate_race", 71.5, 400.0)
	check(res["new_best"] and SaveData.is_unlocked("prop_5040_cw"), "gate race completion saves the time and unlocks parts")
	SaveData.load_data()
	check(is_equal_approx(SaveData.best_time("gate_race"), 71.5) and SaveData.is_unlocked("frame_3"), "best time and unlocks persist in save.json")
	# rebinding for the persistence test
	Settings._reset_bindings()
	Settings.set_binding("throttle_up", "kb", "key:%d" % KEY_T)
	Settings.set_binding("throttle_up", "pad", "joyaxis:5:1")
	Settings.fov = 77.0
	Settings.graphics_preset = 0
	Settings.master_vol = 0.33
	Settings.save_settings()
	check(InputMap.has_action("throttle_up") and InputMap.action_has_event("throttle_up", Settings.binding_to_event("key:%d" % KEY_T)), "InputMap updated immediately after rebinding")
	# conflict handling: binding W to another action steals it from the original
	Settings.set_binding("throttle_down", "kb", "key:%d" % KEY_T)
	check(Settings.bindings["throttle_up"]["kb"] == "", "binding a key already in use unbinds the old action")
	Settings.set_binding("throttle_up", "kb", "key:%d" % KEY_T)
	print("(settings.cfg written; run again with `-- read` to verify persistence)")


func _read_phase() -> void:
	print("== persistence after restart ==")
	check(Settings.bindings["throttle_up"]["kb"] == "key:%d" % KEY_T, "keyboard rebinding persisted: " + Settings.binding_text(Settings.bindings["throttle_up"]["kb"]))
	check(Settings.bindings["throttle_up"]["pad"] == "joyaxis:5:1", "gamepad rebinding persisted: " + Settings.binding_text(Settings.bindings["throttle_up"]["pad"]))
	check(InputMap.action_has_event("throttle_up", Settings.binding_to_event("key:%d" % KEY_T)), "rebound key is live in the InputMap")
	check(not InputMap.action_has_event("throttle_up", Settings.binding_to_event("key:%d" % KEY_W)), "old default key no longer bound")
	check(is_equal_approx(Settings.fov, 77.0) and Settings.graphics_preset == 0 and is_equal_approx(Settings.master_vol, 0.33), "FOV / preset / volume persisted")
	check(is_equal_approx(SaveData.best_time("gate_race"), 71.5), "best time persisted in save.json")
	# clean up so the real game starts fresh
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.SETTINGS_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.SAVE_PATH))
