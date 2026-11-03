class_name ContextMenu
extends Control
## Small modal list of actions (or an info card) used by garage equipment.
## Fully navigable with D-pad / left stick + Cross, or the mouse.

signal closed

var title := ""
var body := ""
var options: Array = []      # [[label, callable], ...]


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(620, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := UITheme.label(title, 28, UITheme.ACCENT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(580, 0)
	v.add_child(t)
	if body != "":
		var b := UITheme.label(body, 19)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(580, 0)
		v.add_child(b)
	for o in options:
		var cb: Callable = o[1]
		var btn := UITheme.button(o[0], func():
			closed.emit()
			cb.call(), Vector2(580, 46))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(btn)
	v.add_child(UITheme.button("Close  (Esc / Circle)", func(): closed.emit(), Vector2(580, 42)))
	Pad.focus_first(self, true)
