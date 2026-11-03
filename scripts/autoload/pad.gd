extends Node
## Gamepad helpers: tracks whether the player is on a pad or keyboard/mouse, controller
## vibration, prompt glyphs and a virtual mouse cursor (left stick + Cross) for the
## pointer-driven workbench screens. Menus use normal focus navigation (D-pad / left stick).

signal device_changed(pad: bool)

var using_pad := false
## Screens that are driven by the pointer (workbench) switch this on.
var cursor_enabled := false
var _cursor_down := false
var _cursor_speed := 900.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# make every Godot UI control navigable with a DualSense: Cross = accept, Circle = back
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", a)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	InputMap.action_add_event("ui_cancel", b)


func _input(event: InputEvent) -> void:
	var was := using_pad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		using_pad = true
	elif event is InputEventKey or (event is InputEventMouseMotion and event.relative.length() > 2.0 and not event.has_meta("virtual")) or event is InputEventMouseButton and not event.has_meta("virtual"):
		using_pad = false
	if was != using_pad:
		device_changed.emit(using_pad)
	# virtual cursor click
	if cursor_enabled and event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		if event.pressed != _cursor_down:
			_cursor_down = event.pressed
			_click(event.pressed)
		get_viewport().set_input_as_handled()


func _click(pressed: bool) -> void:
	var vp := get_viewport()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = vp.get_mouse_position()
	mb.global_position = mb.position
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mb.set_meta("virtual", true)
	vp.gui_release_focus()
	Input.parse_input_event(mb)


func _process(dt: float) -> void:
	if not (cursor_enabled and using_pad and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE):
		return
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if v.length() < 0.15:
		return
	v = v * pow(v.length(), 0.8)
	var vp := get_viewport()
	var p := vp.get_mouse_position() + v * _cursor_speed * dt
	p = p.clamp(Vector2.ZERO, Vector2(1919, 1079))
	vp.warp_mouse(p)
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	mm.relative = v * _cursor_speed * dt
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _cursor_down else 0
	mm.set_meta("virtual", true)
	Input.parse_input_event(mm)


## Short controller vibration (respects the Options toggle).
func rumble(weak: float, strong: float, duration: float) -> void:
	if not Settings.rumble:
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Prompt text for an action on the current device, e.g. "E" or "Cross".
func glyph(action: String) -> String:
	var b: Dictionary = Settings.bindings.get(action, {})
	var slot := "pad" if using_pad else "kb"
	var t := Settings.binding_text(str(b.get(slot, "")))
	if t == "—":
		t = Settings.binding_text(str(b.get("kb" if using_pad else "pad", "")))
	return t.replace("Mouse Left", "LMB").replace("Mouse Right", "RMB").replace("Mouse ", "")


## Gives keyboard/pad focus to the first focusable control under `root` (when on a pad).
func focus_first(root: Node, force: bool = false) -> void:
	if not (using_pad or force):
		return
	for c in root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree() and not (ctl is Button and (ctl as Button).disabled):
			ctl.grab_focus()
			return
