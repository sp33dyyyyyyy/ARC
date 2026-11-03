class_name UITheme
extends RefCounted
## Dark, orange-accent UI theme built in code, plus small widget helpers.

const BG := Color(0.065, 0.075, 0.085)
const PANEL := Color(0.105, 0.12, 0.135)
const PANEL_LIGHT := Color(0.16, 0.18, 0.2)
const ACCENT := Color(1.0, 0.64, 0.14)
const ACCENT2 := Color(0.32, 0.78, 0.74)
const TEXT := Color(0.93, 0.94, 0.95)
const MUTED := Color(0.6, 0.65, 0.68)
const GOOD := Color(0.4, 0.9, 0.5)
const BAD := Color(1.0, 0.34, 0.28)

static var _theme: Theme = null
static var _font: Font = null
static var _font_bold: Font = null


## A clean system UI font (Bahnschrift / Segoe UI on Windows), falling back to Godot's default.
static func font(bold: bool = false) -> Font:
	if bold and _font_bold:
		return _font_bold
	if not bold and _font:
		return _font
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Noto Sans", "Open Sans", "DejaVu Sans", "Liberation Sans"])
	f.font_weight = 650 if bold else 420
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.allow_system_fallback = true
	if bold:
		_font_bold = f
	else:
		_font = f
	return f


static func flat(color: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func _circle_tex(d: int, color: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(c.x - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	t.default_font = font()
	ThemeDB.fallback_font = font()
	# Buttons get an accent underline on hover / focus
	# Buttons
	t.set_stylebox("normal", "Button", flat(PANEL_LIGHT, 7, Color(1, 1, 1, 0.07), 1, 14))
	var hov := flat(Color(0.21, 0.24, 0.27), 7, Color(ACCENT, 0.7), 1, 14)
	hov.border_width_bottom = 3
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", flat(Color(0.3, 0.21, 0.09), 7, ACCENT, 2, 14))
	t.set_stylebox("disabled", "Button", flat(Color(0.1, 0.11, 0.12), 7, Color(1, 1, 1, 0.03), 1, 14))
	var foc := flat(Color(1, 1, 1, 0.03), 7, ACCENT, 2, 14)
	foc.border_width_bottom = 4
	t.set_stylebox("focus", "Button", foc)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.42, 0.46))
	t.set_stylebox("normal", "OptionButton", flat(PANEL_LIGHT, 6, Color(1, 1, 1, 0.08), 1, 12))
	t.set_stylebox("hover", "OptionButton", flat(Color(0.23, 0.25, 0.31), 6, ACCENT, 1, 12))
	t.set_stylebox("pressed", "OptionButton", flat(Color(0.3, 0.2, 0.08), 6, ACCENT, 2, 12))
	t.set_stylebox("focus", "OptionButton", flat(Color(0, 0, 0, 0), 6, ACCENT, 2, 12))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_stylebox("panel", "PopupMenu", flat(PANEL, 6, ACCENT, 1, 6))
	t.set_stylebox("hover", "PopupMenu", flat(Color(0.3, 0.2, 0.08), 4, Color(0, 0, 0, 0), 0, 6))
	# Panels: soft drop shadow, thin light rim
	var pnl := flat(Color(PANEL, 0.97), 10, Color(1, 1, 1, 0.08), 1, 16)
	pnl.shadow_color = Color(0, 0, 0, 0.45)
	pnl.shadow_size = 10
	pnl.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "PanelContainer", pnl)
	t.set_stylebox("panel", "Panel", pnl)
	# Scrollbars
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, flat(Color(0, 0, 0, 0.25), 5, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber", sb, flat(Color(1, 1, 1, 0.18), 5, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_highlight", sb, flat(Color(ACCENT, 0.7), 5, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_pressed", sb, flat(ACCENT, 5, Color(0, 0, 0, 0), 0, 3))
	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", flat(Color(0.05, 0.055, 0.06, 0.97), 6, Color(ACCENT, 0.6), 1, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# Check buttons / boxes
	for cb in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cb, flat(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0, 8))
		t.set_stylebox("hover", cb, flat(Color(1, 1, 1, 0.05), 6, Color(0, 0, 0, 0), 0, 8))
		t.set_stylebox("pressed", cb, flat(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0, 8))
		t.set_stylebox("focus", cb, flat(Color(0, 0, 0, 0), 6, ACCENT, 2, 8))
		t.set_color("font_hover_color", cb, Color.WHITE)
		t.set_color("font_pressed_color", cb, ACCENT)
	t.set_stylebox("focus", "LineEdit", flat(Color(0, 0, 0, 0), 5, ACCENT, 2, 8))
	t.set_stylebox("focus", "HSlider", flat(Color(0, 0, 0, 0), 4, ACCENT, 1, 2))
	t.set_stylebox("focus", "TabBar", flat(Color(0, 0, 0, 0), 4, ACCENT, 2, 2))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	# Tabs
	t.set_stylebox("tab_selected", "TabContainer", flat(PANEL_LIGHT, 6, ACCENT, 2, 18))
	t.set_stylebox("tab_unselected", "TabContainer", flat(Color(0.1, 0.11, 0.14), 6, Color(1, 1, 1, 0.05), 1, 18))
	t.set_stylebox("tab_hovered", "TabContainer", flat(Color(0.2, 0.21, 0.26), 6, Color(1, 1, 1, 0.2), 1, 18))
	t.set_stylebox("panel", "TabContainer", flat(Color(0.1, 0.105, 0.135), 8, Color(1, 1, 1, 0.07), 1, 14))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	# Sliders
	var grab := _circle_tex(22, ACCENT)
	var grab_h := _circle_tex(22, Color(1.0, 0.8, 0.4))
	for kind in ["HSlider", "VSlider"]:
		t.set_icon("grabber", kind, grab)
		t.set_icon("grabber_highlight", kind, grab_h)
		t.set_icon("grabber_disabled", kind, grab)
	var track := flat(Color(0.2, 0.21, 0.26), 4, Color(0, 0, 0, 0), 0, 2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := flat(ACCENT.darkened(0.2), 4, Color(0, 0, 0, 0), 0, 2)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var vtrack := flat(Color(0.2, 0.21, 0.26), 4, Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("slider", "VSlider", vtrack)
	var vfill := flat(ACCENT.darkened(0.2), 4, Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("grabber_area", "VSlider", vfill)
	t.set_stylebox("grabber_area_highlight", "VSlider", vfill)
	# Progress bars
	t.set_stylebox("background", "ProgressBar", flat(Color(0.05, 0.055, 0.07), 4, Color(1, 1, 1, 0.1), 1, 2))
	t.set_stylebox("fill", "ProgressBar", flat(GOOD, 3, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("normal", "LineEdit", flat(Color(0.06, 0.065, 0.085), 5, Color(1, 1, 1, 0.1), 1, 8))
	_theme = t
	return t


## A full-rect, mouse-transparent Control carrying the theme.
static func root_control() -> Control:
	var c := Control.new()
	c.theme = get_theme()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable = Callable(), min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	if callback.is_valid():
		b.pressed.connect(callback)
	b.pressed.connect(func(): Audio.play("click"))
	return b


static func accent_button(text: String, callback: Callable = Callable(), min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := button(text, callback, min_size)
	b.add_theme_stylebox_override("normal", flat(ACCENT.darkened(0.15), 6, ACCENT, 1, 16))
	b.add_theme_stylebox_override("hover", flat(ACCENT, 6, Color.WHITE, 1, 16))
	b.add_theme_stylebox_override("pressed", flat(ACCENT.darkened(0.35), 6, ACCENT, 2, 16))
	b.add_theme_color_override("font_color", Color(0.1, 0.07, 0.02))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.02))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.42, 0.46))
	return b


static func slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 28)
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


## Section header label (bold, accent) with a thin rule underneath.
static func header(text: String, size: int = 24) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var l := label(text.to_upper(), size, ACCENT)
	l.add_theme_font_override("font", font(true))
	v.add_child(l)
	var r := ColorRect.new()
	r.color = Color(ACCENT, 0.35)
	r.custom_minimum_size = Vector2(0, 2)
	v.add_child(r)
	return v


## Big bold title label.
static func title(text: String, size: int = 64, color: Color = Color.WHITE) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", font(true))
	return l


## BBCode for a key-cap glyph, e.g. key_cap("E") -> boxed "E".
static func key_cap(text: String) -> String:
	return "[bgcolor=#ffffff26][color=#ffd27a] %s [/color][/bgcolor]" % text
