extends Node2D

@export var margin: float = 40.0
@export var margin_top: float = 90.0
@export var corner_radius: float = 120.0
@export var spacing: float = 13.0
@export var head_radius: float = 4.5
@export var tail_length: float = 12.0
@export var tail_gap: float = 2.0
@export var tail_width: float = 1.5
@export var head_color: Color = Color(0.95, 0.75, 0.3)
@export var tail_color: Color = Color(0.9, 0.9, 0.7)

func _draw():
	var screen = get_viewport_rect().size
	var x0 = margin
	var y0 = margin_top
	var x1 = screen.x - margin
	var y1 = screen.y - margin
	var r = corner_radius
	var d = head_radius + tail_length

	var straight_w = (x1 - x0) - 2.0 * r
	var straight_h = (y1 - y0) - 2.0 * r
	var arc = PI * r / 2.0
	var perimeter = 2.0 * straight_w + 2.0 * straight_h + 4.0 * arc

	var n = int(round(perimeter / spacing))
	var step = perimeter / n

	for i in n:
		var p = point_on_border(i * step, x0, y0, x1, y1, r, straight_w, straight_h, arc)
		var pos: Vector2 = p[0]
		var normal: Vector2 = p[1]
		draw_lipid(pos + normal * d, -normal)
		draw_lipid(pos - normal * d, normal)

func point_on_border(s, x0, y0, x1, y1, r, sw, sh, arc) -> Array:
	if s < sw:
		return [Vector2(x0 + r + s, y0), Vector2.UP]
	s -= sw
	if s < arc:
		var n = Vector2.from_angle(-PI / 2.0 + s / r)
		return [Vector2(x1 - r, y0 + r) + n * r, n]
	s -= arc
	if s < sh:
		return [Vector2(x1, y0 + r + s), Vector2.RIGHT]
	s -= sh
	if s < arc:
		var n = Vector2.from_angle(s / r)
		return [Vector2(x1 - r, y1 - r) + n * r, n]
	s -= arc
	if s < sw:
		return [Vector2(x1 - r - s, y1), Vector2.DOWN]
	s -= sw
	if s < arc:
		var n = Vector2.from_angle(PI / 2.0 + s / r)
		return [Vector2(x0 + r, y1 - r) + n * r, n]
	s -= arc
	if s < sh:
		return [Vector2(x0, y1 - r - s), Vector2.LEFT]
	s -= sh
	var n = Vector2.from_angle(PI + s / r)
	return [Vector2(x0 + r, y0 + r) + n * r, n]

func draw_lipid(head_pos: Vector2, tail_dir: Vector2):
	draw_circle(head_pos, head_radius, head_color)
	var side = tail_dir.orthogonal() * tail_gap
	var start = head_pos + tail_dir * head_radius
	var end = start + tail_dir * tail_length
	draw_line(start + side, end + side, tail_color, tail_width)
	draw_line(start - side, end - side, tail_color, tail_width)
