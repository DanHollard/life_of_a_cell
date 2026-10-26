extends Node2D

@export var margin: float = 40.0
@export var margin_top: float = 130.0
@export var corner_radius: float = 120.0
@export var spacing: float = 13.0
@export var head_radius: float = 4.5
@export var tail_length: float = 12.0
@export var tail_gap: float = 2.0
@export var tail_width: float = 1.5
@export var hole_radius: float = 14.0
@export var head_color: Color = Color(0.95, 0.75, 0.3)
@export var tail_color: Color = Color(0.9, 0.9, 0.7)

const CHANNEL_COLORS = {
	"carb": Color(0.5, 0.8, 1.0),
	"lipid": Color(0.95, 0.75, 0.3),
	"amino": Color(0.7, 0.5, 0.9),
}

func _ready() -> void:
	Game.channels_changed.connect(queue_redraw)

func params() -> Dictionary:
	var screen = get_viewport_rect().size
	var x0 = margin
	var y0 = margin_top
	var x1 = screen.x - margin
	var y1 = screen.y - margin
	var r = corner_radius
	var sw = (x1 - x0) - 2.0 * r
	var sh = (y1 - y0) - 2.0 * r
	var arc = PI * r / 2.0
	var perimeter = 2.0 * sw + 2.0 * sh + 4.0 * arc
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "r": r, "sw": sw, "sh": sh, "arc": arc, "perimeter": perimeter}

# frac runs 0..1 clockwise round the membrane. Returns [position, outward normal].
func border_point(frac: float) -> Array:
	var q = params()
	return point_on_border(frac * q.perimeter, q.x0, q.y0, q.x1, q.y1, q.r, q.sw, q.sh, q.arc)

func _draw() -> void:
	var q = params()
	var d = head_radius + tail_length

	var holes: Array = []
	for ch in Game.channel_list:
		holes.append(border_point(ch.frac)[0])

	var n = int(round(q.perimeter / spacing))
	var step = q.perimeter / n

	for i in n:
		var p = point_on_border(i * step, q.x0, q.y0, q.x1, q.y1, q.r, q.sw, q.sh, q.arc)
		var pos: Vector2 = p[0]
		var normal: Vector2 = p[1]
		var skip := false
		for h in holes:
			if pos.distance_to(h) < hole_radius:
				skip = true
				break
		if skip:
			continue
		draw_lipid(pos + normal * d, -normal)
		draw_lipid(pos - normal * d, normal)

	for ch in Game.channel_list:
		var bp = border_point(ch.frac)
		draw_channel(bp[0], bp[1], CHANNEL_COLORS[ch.type])

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

func draw_lipid(head_pos: Vector2, tail_dir: Vector2) -> void:
	draw_circle(head_pos, head_radius, head_color)
	var side = tail_dir.orthogonal() * tail_gap
	var start = head_pos + tail_dir * head_radius
	var end = start + tail_dir * tail_length
	draw_line(start + side, end + side, tail_color, tail_width)
	draw_line(start - side, end - side, tail_color, tail_width)

# A transmembrane protein: two blocks with a dark pore between them.
func draw_channel(pos: Vector2, normal: Vector2, color: Color) -> void:
	var tangent = normal.orthogonal()
	var half_len = head_radius + tail_length + head_radius + 2.0
	var half_w = 11.0
	var pore = 3.0

	var left := PackedVector2Array([
		pos - tangent * half_w - normal * half_len,
		pos - tangent * pore - normal * half_len,
		pos - tangent * pore + normal * half_len,
		pos - tangent * half_w + normal * half_len,
	])
	var right := PackedVector2Array([
		pos + tangent * pore - normal * half_len,
		pos + tangent * half_w - normal * half_len,
		pos + tangent * half_w + normal * half_len,
		pos + tangent * pore + normal * half_len,
	])
	var gap := PackedVector2Array([
		pos - tangent * pore - normal * half_len,
		pos + tangent * pore - normal * half_len,
		pos + tangent * pore + normal * half_len,
		pos - tangent * pore + normal * half_len,
	])
	draw_colored_polygon(gap, Color(0.04, 0.07, 0.1))
	draw_colored_polygon(left, color)
	draw_colored_polygon(right, color)

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			draw_circle(pos + tangent * sx * 7.0 + normal * sy * half_len, 5.0, color)
