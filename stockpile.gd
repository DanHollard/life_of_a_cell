extends Node2D

@export var offset := Vector2(-310, 40)         # where the stockpile sits, relative to the middle of the cell
@export var station_offset := Vector2(115, 0)   # where the enzyme station sits, relative to the stockpile
@export var slot_spacing: float = 5.0

var t := 0.0
var membrane

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")
	if membrane != null:
		var q = membrane.params()
		position = Vector2((q.x0 + q.x1) * 0.5, (q.y0 + q.y1) * 0.5) + offset

func station_pos() -> Vector2:
	return global_position + station_offset

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func slot_pos(i: int) -> Vector2:
	var a = i * 2.39996
	var r = slot_spacing * sqrt(float(i) + 0.5)
	return Vector2(cos(a), sin(a)) * r

func draw_highway(a: Vector2, b: Vector2, col: Color) -> void:
	var delta_v = b - a
	var length = delta_v.length()
	if length < 1.0:
		return
	var u = delta_v / length
	draw_line(a, b, Color(col.r, col.g, col.b, 0.15), 6.0)
	var d = fmod(t * 24.0, 16.0) - 16.0
	while d < length:
		var s = maxf(d, 0.0)
		var e = minf(d + 8.0, length)
		if e > s:
			draw_line(a + u * s, a + u * e, Color(col.r, col.g, col.b, 0.6), 2.0)
		d += 16.0

func draw_enzyme(c: Vector2, busy: bool) -> void:
	var pulse = 0.0
	if busy:
		pulse = 1.5 * sin(t * 10.0)
	draw_circle(c, 14.0 + pulse, Color(0.95, 0.7, 0.3))
	draw_circle(c, 9.0, Color(0.75, 0.5, 0.2))
	# the active site: a notch the glucose slots into
	var notch := PackedVector2Array([c + Vector2(15, -6), c + Vector2(3, 0), c + Vector2(15, 6)])
	draw_colored_polygon(notch, Color(0.08, 0.1, 0.14))

func _draw() -> void:
	# highways: each sugar channel to the enzyme station, then a belt on to the stockpile
	if membrane != null:
		for ch in Game.channel_list:
			if ch.type == "carb":
				var bp = membrane.border_point(ch.frac)
				var pore: Vector2 = bp[0] - bp[1] * 28.0
				draw_highway(to_local(pore), station_offset, Color(0.6, 0.85, 1.0))
	draw_highway(station_offset, Vector2.ZERO, Color(0.95, 0.8, 0.5))

	# the stockpile
	var cap = Game.carb_cap
	var full = Game.stock.carb >= cap
	var edge = slot_spacing * sqrt(float(cap) + 0.5) + 10.0
	var ring_color = Color(0.5, 0.8, 1.0, 0.35)
	if full:
		ring_color = Color(1.0, 0.45, 0.35, 0.6 + 0.3 * sin(t * 6.0))
	draw_circle(Vector2.ZERO, edge, Color(0.5, 0.8, 1.0, 0.07))
	draw_arc(Vector2.ZERO, edge, 0.0, TAU, 48, ring_color, 2.0, true)

	for i in cap:
		if i < Game.stock.carb:
			draw_circle(slot_pos(i), 3.2, Color(0.88, 0.96, 1.0))
		else:
			draw_circle(slot_pos(i), 1.5, Color(0.5, 0.8, 1.0, 0.25))

	var text = "Glycogen  %d / %d" % [Game.stock.carb, cap]
	draw_string(ThemeDB.fallback_font, Vector2(-70, edge + 18), text, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color(1, 1, 1, 0.8))

	# the enzyme station
	var n = Game.enzymes
	for i in n:
		var off = Vector2(0, (i - (n - 1) * 0.5) * 34.0)
		draw_enzyme(station_offset + off, Game.station_queue > 0)
	var label_pos = station_offset + Vector2(-70, (n - 1) * 17.0 + 40.0)
	var qtext = "Synthase x%d   queue %d/%d" % [n, Game.station_queue, Game.QUEUE_MAX]
	draw_string(ThemeDB.fallback_font, label_pos, qtext, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color(1, 1, 1, 0.8))
