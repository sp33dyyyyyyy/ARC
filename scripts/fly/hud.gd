class_name Hud
extends Control
## Clean FPV HUD, drawn each frame from values pushed by FlyStage.

const GREEN := Color(0.55, 1.0, 0.65)
const AMBER := Color(1.0, 0.8, 0.25)
const RED := Color(1.0, 0.3, 0.25)
const WHITE := Color(1, 1, 1)

# values
var speed_kmh := 0.0
var altitude := 0.0
var volts := 16.8
var vcell := 4.2
var batt_frac := 1.0
var mah_used := 0.0
var soc := 1.0
var amps_total := 0.0
var has_current_sensor := true
var motor_amps := [0.1, 0.1, 0.1, 0.1]
var throttle := 0.0
var armed := false
var mode_text := "ACRO"
var mission_lines: Array = []
var warnings: Array = []
var link_text := ""
var countdown_text := ""
var show_hud := true
var overlay_title := ""      # big centered title (e.g. REPLAY)
var overlay_sub := ""
var markers: Array = []      # {p: Vector2, on: bool, dist, name, hp, obj, scan, dead, recon}
var guide: Dictionary = {}   # {p, on, dist, text}
var reticle: Dictionary = {} # {p, on, hot}
var pods_text := ""
var cam_text := ""
var heading := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _txt(pos: Vector2, text: String, size: int, color: Color = WHITE, align: int = 0) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos
	if align == 1:
		p.x -= w * 0.5
	elif align == 2:
		p.x -= w
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.85))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	var c := Vector2(960, 540)
	if overlay_title != "":
		_txt(Vector2(960, 150), overlay_title, 64, WHITE, 1)
		if overlay_sub != "":
			_txt(Vector2(960, 205), overlay_sub, 26, Color(0.9, 0.9, 0.95), 1)
	if countdown_text != "":
		_txt(Vector2(960, 420), countdown_text, 150, AMBER, 1)
	if not show_hud:
		_draw_warnings(c)
		return
	var osd: Dictionary = Settings.osd
	if osd.get("markers", true):
		_draw_markers()
	# crosshair
	var col := Color(1, 1, 1, 0.9)
	if osd.get("crosshair", true):
		draw_arc(c, 11.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0, true)
		draw_arc(c, 11.0, 0.0, TAU, 24, col, 2.0, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 16.0, c + d * 30.0, Color(0, 0, 0, 0.6), 5.0)
			draw_line(c + d * 16.0, c + d * 30.0, col, 2.5)
	# per-motor amps (positions mirror the quad layout; front = up)
	if osd.get("amps", true):
		var spots := [Vector2(330, 190), Vector2(330, -190), Vector2(-330, 190), Vector2(-330, -190)]   # M1 RR, M2 FR, M3 RL, M4 FL
		for i in 4:
			var a: float = motor_amps[i]
			var mc := GREEN if a < 20.0 else AMBER
			_txt(c + spots[i] + Vector2(0, 0), "M%d  %4.1f A" % [i + 1, a], 30, mc, 1)
	# speed / altitude
	if osd.get("speed", true):
		_txt(Vector2(960, 1000), "%d" % int(round(speed_kmh)), 64, WHITE, 1)
		_txt(Vector2(960, 1040), "km/h", 24, Color(0.85, 0.85, 0.9), 1)
	if osd.get("altitude", true):
		_txt(Vector2(1180, 1000), "%d" % int(round(altitude)), 64, WHITE, 0)
		_txt(Vector2(1180, 1040), "ALT  m", 24, Color(0.85, 0.85, 0.9), 0)
	if osd.get("compass", true):
		_draw_compass()
	if pods_text != "":
		_txt(Vector2(1500, 1000), pods_text, 28, AMBER, 1)
	if cam_text != "":
		_txt(Vector2(1860, 82), cam_text, 20, Color(0.9, 0.9, 0.95), 2)
	if not osd.get("battery", true):
		_status_and_mission()
		_draw_warnings(c)
		return
	# battery
	var bx := 60.0
	var by := 930.0
	var bw := 420.0
	var low := vcell < 3.45
	var bc := GREEN if vcell > 3.7 else (AMBER if vcell > 3.45 else RED)
	if low and fmod(_t, 0.8) < 0.4:
		bc = RED
	_txt(Vector2(bx, by - 14), "%5.2f V   (%.2f V/cell)" % [volts, vcell], 32, bc)
	draw_rect(Rect2(bx, by, bw, 26), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(bx + 2, by + 2, (bw - 4) * clampf(batt_frac, 0.0, 1.0), 22), bc, true)
	draw_rect(Rect2(bx, by, bw, 26), Color(1, 1, 1, 0.8), false, 2.0)
	for k in range(1, 4):
		draw_line(Vector2(bx + bw * k / 4.0, by), Vector2(bx + bw * k / 4.0, by + 26), Color(0, 0, 0, 0.6), 2.0)
	_txt(Vector2(bx, by + 62), "%d mAh used   %d%%" % [int(mah_used), int(round(soc * 100.0))], 24, Color(0.9, 0.9, 0.95))
	var cur_txt := "%5.1f A" % amps_total if has_current_sensor else "--.- A"
	if osd.get("amps", true):
		_txt(Vector2(bx, by + 100), "CURRENT  " + cur_txt, 34, GREEN if amps_total < 60.0 else AMBER)
	# throttle gauge
	var tx := 1830.0
	var ty := 700.0
	var th := 260.0
	draw_rect(Rect2(tx, ty, 16, th), Color(0, 0, 0, 0.55), true)
	draw_rect(Rect2(tx + 2, ty + th - 2 - (th - 4) * throttle, 12, (th - 4) * throttle), AMBER, true)
	draw_rect(Rect2(tx, ty, 16, th), Color(1, 1, 1, 0.8), false, 2.0)
	_txt(Vector2(tx + 8, ty + th + 32), "THR %d%%" % int(round(throttle * 100.0)), 22, WHITE, 1)
	_status_and_mission()
	_draw_warnings(c)


func _status_and_mission() -> void:
	# status
	_txt(Vector2(960, 48), "ARMED" if armed else "DISARMED", 30, GREEN if armed else AMBER, 1)
	_txt(Vector2(960, 82), mode_text, 22, Color(0.9, 0.9, 0.95), 1)
	if link_text != "":
		_txt(Vector2(1860, 48), link_text, 22, Color(0.9, 0.9, 0.95), 2)
	if not Settings.osd.get("mission", true):
		return
	var y := 48.0
	for l in mission_lines:
		_txt(Vector2(60, y), l, 30 if y == 48.0 else 24, WHITE if y == 48.0 else Color(0.9, 0.9, 0.95))
		y += 36.0 if y == 48.0 else 30.0


func _draw_compass() -> void:
	var cx := 960.0
	var y := 118.0
	draw_rect(Rect2(cx - 220, y - 4, 440, 2), Color(1, 1, 1, 0.5))
	for k in range(-6, 7):
		var deg := snappedf(heading, 15.0) + k * 15.0
		var off := (deg - heading) * 4.0
		if absf(off) > 220.0:
			continue
		var d := int(fposmod(deg, 360.0))
		var lbl: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, "")
		draw_line(Vector2(cx + off, y - 4), Vector2(cx + off, y - (14 if lbl != "" else 9)), Color(1, 1, 1, 0.8), 2.0)
		if lbl != "":
			_txt(Vector2(cx + off, y - 18), lbl, 20, AMBER if lbl == "N" else WHITE, 1)
	draw_line(Vector2(cx, y + 2), Vector2(cx, y - 18), GREEN, 2.0)
	if not guide.is_empty() and guide.get("bearing_ok", false):
		var off2 := clampf(wrapf(float(guide["bearing"]) - heading, -180.0, 180.0) * 4.0, -220.0, 220.0)
		draw_colored_polygon(PackedVector2Array([Vector2(cx + off2, y + 4), Vector2(cx + off2 - 7, y + 16), Vector2(cx + off2 + 7, y + 16)]), RED)


func _bracket(p: Vector2, r: float, col: Color) -> void:
	var l := r * 0.45
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var cpt := p + Vector2(sx * r, sy * r)
			draw_line(cpt, cpt - Vector2(sx * l, 0), col, 2.5)
			draw_line(cpt, cpt - Vector2(0, sy * l), col, 2.5)


func _draw_markers() -> void:
	for m in markers:
		var p: Vector2 = m["p"]
		var dist: float = m["dist"]
		var col: Color = RED if m["obj"] else AMBER
		if m["dead"]:
			col = Color(0.6, 0.6, 0.6, 0.6)
		elif m["recon"]:
			col = GREEN if m["scan"] >= 1.0 else Color(0.5, 0.85, 1.0)
		if not m["on"]:
			if m["obj"] and not m["dead"]:
				draw_circle(p, 8.0, Color(col, 0.85))
			continue
		var r := clampf(900.0 / maxf(dist, 1.0), 14.0, 70.0)
		_bracket(p, r, Color(0, 0, 0, 0.6))
		_bracket(p, r, col)
		var label := "%s  %dm" % [m["name"], int(dist)]
		_txt(p + Vector2(0, -r - 10), label, 18, col, 1)
		if not m["dead"] and m["hp"] < 1.0:
			draw_rect(Rect2(p.x - r, p.y + r + 6, 2.0 * r, 6), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(p.x - r, p.y + r + 6, 2.0 * r * m["hp"], 6), col)
		if m["recon"] and m["scan"] > 0.0 and m["scan"] < 1.0:
			draw_arc(p, r + 10.0, -PI * 0.5, -PI * 0.5 + TAU * m["scan"], 32, GREEN, 4.0)
	if not guide.is_empty():
		var gp: Vector2 = guide["p"]
		if guide["on"]:
			draw_arc(gp, 10.0, 0.0, TAU, 16, GREEN, 2.0)
			_txt(gp + Vector2(0, 30), "%s %dm" % [guide.get("text", ""), int(guide["dist"])], 18, GREEN, 1)
		else:
			var dir := (gp - Vector2(960, 540)).normalized()
			var ep := Vector2(960, 540) + dir * 380.0
			draw_colored_polygon(PackedVector2Array([ep + dir * 18.0, ep + dir.orthogonal() * 10.0, ep - dir.orthogonal() * 10.0]), GREEN)
	if not reticle.is_empty() and reticle.get("on", false):
		var rp: Vector2 = reticle["p"]
		var rc := RED if reticle.get("hot", false) else Color(1, 1, 1, 0.75)
		draw_arc(rp, 16.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0)
		draw_arc(rp, 16.0, 0.0, TAU, 24, rc, 2.0)
		draw_line(rp + Vector2(-26, 0), rp + Vector2(-18, 0), rc, 2.0)
		draw_line(rp + Vector2(18, 0), rp + Vector2(26, 0), rc, 2.0)
		draw_circle(rp, 2.5, rc)


func _draw_warnings(c: Vector2) -> void:
	var y := 760.0
	for w in warnings:
		var flash := fmod(_t, 0.7) < 0.45
		_txt(Vector2(960, y), w["text"], 38, w.get("color", RED) if (flash or not w.get("blink", false)) else Color(1, 1, 1, 0.4), 1)
		y += 48.0
