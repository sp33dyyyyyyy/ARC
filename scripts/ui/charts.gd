class_name RateChart
extends Control
## Plots the stick -> deg/s curve for roll / pitch / yaw.

var rates: Dictionary = {}
const COLORS := {"roll": Color(1.0, 0.45, 0.35), "pitch": Color(0.4, 0.85, 0.5), "yaw": Color(0.45, 0.65, 1.0)}


func _draw() -> void:
	var r := Rect2(Vector2(46, 14), size - Vector2(64, 44))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.07), true)
	draw_rect(r, Color(0.09, 0.1, 0.13), true)
	var font := ThemeDB.fallback_font
	var max_v := 400.0
	for a in rates:
		max_v = maxf(max_v, float(rates[a]["max"]))
	max_v = ceilf(max_v / 200.0) * 200.0
	for i in 5:
		var y := r.position.y + r.size.y * (1.0 - i / 4.0)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(4, y + 5), "%d" % (max_v * i / 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.MUTED)
	for i in 5:
		var x := r.position.x + r.size.x * i / 4.0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.05))
		draw_string(font, Vector2(x - 12, size.y - 8), "%d%%" % (i * 25), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.MUTED)
	for a in rates:
		var pts := PackedVector2Array()
		for k in 41:
			var s := k / 40.0
			var deg := rad_to_deg(FlightMath.rate_setpoint(s, rates[a]))
			pts.append(Vector2(r.position.x + r.size.x * s, r.position.y + r.size.y * (1.0 - deg / max_v)))
		draw_polyline(pts, COLORS[a], 2.5, true)
	draw_string(font, Vector2(r.position.x + 8, r.position.y + 18), "Rate curve (deg/s)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.TEXT)
	var lx := r.end.x - 190.0
	for a in ["roll", "pitch", "yaw"]:
		draw_string(font, Vector2(lx, r.position.y + 18), a, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COLORS[a])
		lx += 62.0
