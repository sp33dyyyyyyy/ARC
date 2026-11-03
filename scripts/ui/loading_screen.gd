class_name LoadingScreen
extends Control
## Full-screen loading card with a progress bar and rotating gameplay tips.

const TIPS := [
	"Hold the part and press R / R1 until its white arrow lines up with the yellow marker.",
	"Glowing gold screws mean a part is loose: click (or hold) the part to drive them in.",
	"A drone has to pass DIAGNOSTICS on the test station before it can be deployed.",
	"Beginner flight mode holds altitude: throttle centre = hover.",
	"Batteries keep their charge between flights - dock them on the charger.",
	"Contested missions: if the drone goes down far from the launch point, it is lost.",
	"The drop reticle turns red when a released pod would hit the target.",
	"Keep a recon target centred in view to fill its scan ring.",
	"Digital VTX + HD camera: a crisp picture, longer range and faster scanning.",
	"Damaged parts go to the salvage bin: repair them or recycle them for credits.",
	"Customer contracts pay well for certified drones that meet their spec.",
	"Prop guards and armour plates turn bad crashes into minor bumps.",
	"A long-range receiver keeps control far past the 2.4 GHz fail-safe distance.",
	"Press F1 in the garage (or open HOW TO PLAY from the menu) for the full guide.",
	"Graphics trouble? Options > Graphics > Safe graphics turns off the heavy effects.",
]

var title := "LOADING"
var subtitle := ""
var _bar: ProgressBar
var _label: Label
var _tip: Label
var _t := 0.0
var _tip_i := 0


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UITheme.BG.darkened(0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripes := Control.new()
	stripes.set_anchors_preset(Control.PRESET_FULL_RECT)
	stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripes.draw.connect(func():
		for i in 26:
			var x := -400.0 + i * 90.0
			stripes.draw_line(Vector2(x, 1080), Vector2(x + 500, 0), Color(UITheme.ACCENT, 0.035), 28.0)
		stripes.draw_rect(Rect2(0, 1074, 1920, 6), Color(UITheme.ACCENT, 0.7)))
	add_child(stripes)
	var v := VBoxContainer.new()
	v.position = Vector2(160, 380)
	v.custom_minimum_size = Vector2(1600, 0)
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	v.add_child(UITheme.label("FRONTLINE FPV", 26, UITheme.ACCENT))
	v.add_child(UITheme.label(title, 64, Color.WHITE))
	if subtitle != "":
		v.add_child(UITheme.label(subtitle, 26, UITheme.MUTED))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(1600, 14)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	v.add_child(_bar)
	_label = UITheme.label("", 20, UITheme.MUTED)
	v.add_child(_label)
	var tp := PanelContainer.new()
	tp.position = Vector2(160, 860)
	tp.custom_minimum_size = Vector2(1600, 0)
	add_child(tp)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	tp.add_child(th)
	th.add_child(UITheme.label("TIP", 22, UITheme.ACCENT))
	_tip_i = randi() % TIPS.size()
	_tip = UITheme.label(TIPS[_tip_i], 22)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(1480, 0)
	th.add_child(_tip)


func set_progress(f: float, text: String) -> void:
	if _bar:
		_bar.value = clampf(f, 0.0, 1.0)
		_label.text = text


func _process(dt: float) -> void:
	_t += dt
	if _t > 5.0 and _tip:
		_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = TIPS[_tip_i]


func finish() -> void:
	set_progress(1.0, "Ready")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)
