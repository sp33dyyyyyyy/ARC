class_name StepChart
extends Control
## Plots the simulated step response of one axis (bad tuning visibly rings).

var samples := PackedFloat32Array()
var status := ""
var rating := 3


func _draw() -> void:
	var r := Rect2(Vector2(46, 14), size - Vector2(64, 44))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.07), true)
	draw_rect(r, Color(0.09, 0.1, 0.13), true)
	var font := ThemeDB.fallback_font
	var lo := -0.5
	var hi := 2.0
	for v in [0.0, 0.5, 1.0, 1.5, 2.0]:
		var y: float = r.position.y + r.size.y * (1.0 - (v - lo) / (hi - lo))
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.16 if v == 1.0 else 0.06), 2.0 if v == 1.0 else 1.0)
		draw_string(font, Vector2(8, y + 5), "%.1f" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.MUTED)
	for i in 5:
		var x := r.position.x + r.size.x * i / 4.0
		draw_string(font, Vector2(x - 14, size.y - 8), "%d ms" % (i * 175), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.MUTED)
	var col: Color = [UITheme.BAD, Color(1.0, 0.7, 0.2), Color(1.0, 0.85, 0.3), UITheme.GOOD][clampi(rating, 0, 3)]
	if samples.size() > 2:
		var pts := PackedVector2Array()
		var n := 168
		for k in n:
			var idx := mini(int(float(k) / n * 168.0), samples.size() - 1)
			var v := clampf(samples[idx], lo, hi)
			pts.append(Vector2(r.position.x + r.size.x * k / (n - 1.0), r.position.y + r.size.y * (1.0 - (v - lo) / (hi - lo))))
		draw_polyline(pts, col, 2.5, true)
	draw_string(font, Vector2(r.position.x + 8, r.position.y + 18), "Roll step response (simulated)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.TEXT)
