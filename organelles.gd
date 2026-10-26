extends Node2D


var t := 0.0

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	for n in Game.mitochondria:
		var angle = n * 2.39996   # golden angle, so they spread out evenly
		var dist = minf(120.0 + 22.0 * sqrt(float(n)), 190.0)
		var center = Vector2(cos(angle), sin(angle)) * dist
		center += Vector2(sin(t * 0.7 + n * 1.7), cos(t * 0.6 + n * 2.3)) * 4.0
		var rot = angle + PI / 2.0 + sin(t * 0.4 + n) * 0.3
		draw_mitochondrion(center, rot)

func ellipse_points(center: Vector2, rx: float, ry: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var a = i * TAU / 28.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts

func draw_mitochondrion(center: Vector2, rot: float) -> void:
	draw_colored_polygon(ellipse_points(center, 30.0, 15.0, rot), Color(0.75, 0.25, 0.45))
	draw_colored_polygon(ellipse_points(center, 26.0, 11.5, rot), Color(0.9, 0.5, 0.65))
	var folds := PackedVector2Array()
	for i in 7:
		var x = -20.0 + i * (40.0 / 6.0)
		var y = 7.0
		if i % 2 == 1:
			y = -7.0
		folds.append(center + Vector2(x, y).rotated(rot))
	draw_polyline(folds, Color(0.65, 0.2, 0.4), 2.0, true)
