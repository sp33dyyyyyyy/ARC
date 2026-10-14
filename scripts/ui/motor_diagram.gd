class_name MotorDiagram
extends Control
## Top-down schematic of the quad: four motors with spin-direction arrows that
## animate when a motor is commanded in the Motor tab.

var outputs := [0.0, 0.0, 0.0, 0.0]   # 0..1
var angles := [0.0, 0.0, 0.0, 0.0]


func _process(dt: float) -> void:
	for i in 4:
		var dir := 1.0 if Parts.MOTOR_SPIN[i] == "CW" else -1.0   # CW on screen = increasing angle (y down)
		angles[i] += dir * outputs[i] * 38.0 * dt
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := size * 0.5 + Vector2(0, 22)
	var arm := minf(size.x, size.y) * 0.265
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.07), true)
	draw_string(font, Vector2(12, 26), "Motor layout  (front = up, props in)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UITheme.MUTED)
	# arms and body
	for i in 4:
		var sg: Vector2 = Parts.MOTOR_SIGNS[i]
		var p := c + Vector2(sg.x, sg.y) * arm
		draw_line(c, p, Color(0.35, 0.37, 0.42), 10.0, true)
	draw_rect(Rect2(c - Vector2(34, 44), Vector2(68, 88)), Color(0.16, 0.17, 0.21), true)
	draw_rect(Rect2(c - Vector2(34, 44), Vector2(68, 88)), Color(1, 1, 1, 0.15), false, 2.0)
	var tri := PackedVector2Array([c + Vector2(0, -34), c + Vector2(-13, -8), c + Vector2(13, -8)])
	draw_colored_polygon(tri, UITheme.ACCENT)
	# motors
	for i in 4:
		var sg: Vector2 = Parts.MOTOR_SIGNS[i]
		var p := c + Vector2(sg.x, sg.y) * arm
		var r := 56.0
		var active: float = outputs[i]
		var col := Color(0.12, 0.13, 0.16).lerp(Color(0.25, 0.6, 0.3), clampf(active * 1.5, 0.0, 1.0))
		draw_circle(p, r, col)
		draw_arc(p, r, 0, TAU, 40, Color(1, 1, 1, 0.3), 2.0, true)
		# static direction arrow
		var cw: bool = Parts.MOTOR_SPIN[i] == "CW"
		var a0 := -PI * 0.15
		var sweep := PI * 1.45 * (1.0 if cw else -1.0)
		draw_arc(p, r + 9, a0, a0 + sweep, 28, UITheme.ACCENT, 3.0, true)
		var ae := a0 + sweep
		var tip := p + Vector2(cos(ae), sin(ae)) * (r + 9)
		var tdir := Vector2(-sin(ae), cos(ae)) * (1.0 if cw else -1.0)
		var nrm := Vector2(-tdir.y, tdir.x)
		draw_colored_polygon(PackedVector2Array([tip + tdir * 12, tip - tdir * 4 + nrm * 8, tip - tdir * 4 - nrm * 8]), UITheme.ACCENT)
		# spinning blades
		for b in 3:
			var ang: float = angles[i] + TAU * b / 3.0
			draw_line(p, p + Vector2(cos(ang), sin(ang)) * (r - 6), Color(1.0, 0.85, 0.1, 0.9), 7.0, true)
		draw_circle(p, 8, Color(0.1, 0.1, 0.1))
		draw_string(font, p + Vector2(-70, -r - 18 if sg.y < 0 else r + 40), "M%d  %s" % [i + 1, Parts.MOTOR_SPIN[i]], HORIZONTAL_ALIGNMENT_CENTER, 140, 20, UITheme.TEXT)
