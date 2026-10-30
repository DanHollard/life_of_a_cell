extends Node2D

const CELL := 24.0
const INSET := 34.0            # how far inside the membrane a track cell must be
const COST_PER_CELL := 0.5     # amino acids per cell of track
const UNROUTED_YIELD := 0.4    # share of molecules that arrive without a route
const TRACK_SPEED := 1.8       # molecules move this much faster along a track
const MAX_PATH := 80

var membrane
var nucleus
var stockpile
var organelles
var traffic

var q := {}
var screen := Vector2(1152, 648)
var t := 0.0
var obstacles: Array = []
var obstacle_timer := 0.0
var routes: Array = []
var occupied := {}             # cell -> id of the route using it
var next_id := 1
var drawing = null
var timers := {}
var prev_carb_channels := 0
var told_first := false
var toast_label := Label.new()
var toast_time := 0.0

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")
	nucleus = get_parent().get_node_or_null("Nucleus")
	stockpile = get_parent().get_node_or_null("Stockpile")
	organelles = get_parent().get_node_or_null("Organelles")
	traffic = get_parent().get_node_or_null("Traffic")

	var hud := CanvasLayer.new()
	add_child(hud)
	var sc = get_viewport_rect().size
	toast_label.position = Vector2(sc.x * 0.5 - 280.0, 118)
	toast_label.custom_minimum_size = Vector2(560, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_font_size_override("font_size", 15)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.modulate.a = 0.0
	hud.add_child(toast_label)

func toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	toast_time = 6.0

func overlay_open() -> bool:
	return nucleus != null and nucleus.layer != null and nucleus.layer.visible

# Distance from the membrane's centre line: negative inside the cell, positive outside.
func border_dist(pos: Vector2) -> float:
	var c = Vector2((q.x0 + q.x1) * 0.5, (q.y0 + q.y1) * 0.5)
	var half = Vector2((q.x1 - q.x0) * 0.5, (q.y1 - q.y0) * 0.5) - Vector2(q.r, q.r)
	var d = (pos - c).abs() - half
	var outside = Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	var inside = minf(maxf(d.x, d.y), 0.0)
	return outside + inside - q.r

# ---------- the grid ----------

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)

func usable(c: Vector2i) -> bool:
	var p = cell_center(c)
	if p.x < 0.0 or p.y < 0.0 or p.x > screen.x or p.y > screen.y:
		return false
	return border_dist(p) < -INSET

func blocked(c: Vector2i) -> bool:
	var p = cell_center(c)
	for o in obstacles:
		if p.distance_to(o[0]) < o[1]:
			return true
	return false

func station_reach() -> float:
	return 40.0 + (Game.enzymes - 1) * 17.0

func in_station(c: Vector2i) -> bool:
	if stockpile == null:
		return false
	return cell_center(c).distance_to(stockpile.station_pos()) <= station_reach()

func rebuild_obstacles() -> void:
	obstacles = []
	if nucleus != null:
		obstacles.append([nucleus.global_position, 92.0])
	if organelles != null:
		for n in Game.mitochondria:
			obstacles.append([organelles.mito_global(n), 40.0])
	if stockpile != null:
		var edge = stockpile.slot_spacing * sqrt(float(Game.carb_cap) + 0.5) + 10.0
		obstacles.append([stockpile.global_position, edge + 14.0])

func rebuild_occupied() -> void:
	occupied = {}
	for r in routes:
		for c in r.cells:
			if not occupied.has(c):
				occupied[c] = r.id

# ---------- routes ----------

func route_by_id(id: int):
	for r in routes:
		if r.id == id:
			return r
	return null

func route_of(idx: int):
	for r in routes:
		if r.idx == idx:
			return r
	return null

# The points a molecule follows from just inside a channel to the enzyme station.
func path_for(idx: int) -> Array:
	var r = route_of(idx)
	if r == null or stockpile == null:
		return []
	var pts: Array = []
	var cur = r
	var start_i = 0
	var guard = 0
	while cur != null and guard < 30:
		for i in range(start_i, cur.cells.size()):
			pts.append(cell_center(cur.cells[i]))
		if cur.join != -1:
			start_i = cur.join_i + 1
			cur = route_by_id(cur.join)
		else:
			cur = null
		guard += 1
	pts.append(stockpile.station_pos())
	return pts

func route_cost(cells: int) -> int:
	return maxi(1, ceili(float(cells) * COST_PER_CELL))

func remove_route(id: int) -> void:
	var doomed: Array = [id]
	var i = 0
	while i < doomed.size():
		for other in routes:
			if other.join == doomed[i] and not doomed.has(other.id):
				doomed.append(other.id)
		i += 1
	var refund = 0
	var kept: Array = []
	for r in routes:
		if doomed.has(r.id):
			refund += int(floor(r.cost * 0.5))
		else:
			kept.append(r)
	routes = kept
	rebuild_occupied()
	Game.stock.amino += refund
	Game.changed.emit()
	Sfx.play("close", 1.2)
	toast("Route removed. Refunded %d amino acids." % refund)

# ---------- drawing a route ----------

func start_drawing(idx: int, bp: Array) -> void:
	var pos: Vector2 = bp[0]
	var n: Vector2 = bp[1]
	var want = pos - n * 40.0
	var base = cell_of(want)
	var best = Vector2i.ZERO
	var best_d = INF
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var c = base + Vector2i(dx, dy)
			if not usable(c) or blocked(c) or occupied.has(c):
				continue
			var d = cell_center(c).distance_to(want)
			if d < best_d:
				best_d = d
				best = c
	if best_d == INF:
		toast("There is no room beside this channel for a route.")
		return
	drawing = {"idx": idx, "path": [best], "end": "none", "join": -1, "join_i": 0}
	Sfx.play("tick", 1.4)

func try_extend(c: Vector2i) -> bool:
	if drawing.end != "none":
		return false
	if drawing.path.size() >= MAX_PATH:
		return false
	if not usable(c) or blocked(c):
		return false
	if occupied.has(c):
		var r = route_by_id(occupied[c])
		if r == null:
			return false
		drawing.path.append(c)
		drawing.end = "join"
		drawing.join = r.id
		drawing.join_i = r.cells.find(c)
		return true
	drawing.path.append(c)
	if in_station(c):
		drawing.end = "station"
	return true

func update_drawing() -> void:
	var target = cell_of(get_global_mouse_position())
	var path: Array = drawing.path
	# dragging back over your own track undoes it
	var ti = path.find(target)
	if ti >= 0:
		path.resize(ti + 1)
		drawing.end = "none"
		drawing.join = -1
		if ti > 0 and in_station(path[ti]):
			drawing.end = "station"
		return
	var guard = 0
	while guard < 60:
		guard += 1
		var last: Vector2i = path[path.size() - 1]
		if last == target or drawing.end != "none":
			break
		var dx = target.x - last.x
		var dy = target.y - last.y
		var cands: Array = []
		if absi(dx) >= absi(dy):
			if dx != 0:
				cands.append(last + Vector2i(signi(dx), 0))
			if dy != 0:
				cands.append(last + Vector2i(0, signi(dy)))
		else:
			if dy != 0:
				cands.append(last + Vector2i(0, signi(dy)))
			if dx != 0:
				cands.append(last + Vector2i(signi(dx), 0))
		var moved = false
		for cand in cands:
			if path.has(cand):
				continue
			if try_extend(cand):
				moved = true
				break
		if not moved:
			break

func finish_drawing() -> void:
	var d = drawing
	drawing = null
	if d.end == "none":
		toast("A route has to end at the enzyme station, or join an existing route.")
		Sfx.play("close", 1.4)
		return
	var cost = route_cost(d.path.size())
	if Game.stock.amino < cost:
		toast("Not enough amino acids: that route needs %d." % cost)
		Sfx.play("overflow", 1.2)
		return
	Game.stock.amino -= cost
	Game.changed.emit()
	routes.append({"id": next_id, "idx": d.idx, "cells": d.path.duplicate(),
		"join": d.join, "join_i": d.join_i, "cost": cost})
	next_id += 1
	rebuild_occupied()
	Sfx.play("build", 1.2)
	toast("Route built: %d cells, %d amino acids. Molecules now travel along it." % [d.path.size(), cost])

# ---------- input ----------

func _input(event: InputEvent) -> void:
	if membrane == null or not (event is InputEventMouseButton and event.pressed):
		return
	if overlay_open() or drawing != null:
		return
	var mouse = get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		for i in Game.channel_list.size():
			var ch = Game.channel_list[i]
			if ch.type != "carb" or route_of(i) != null:
				continue
			var bp = membrane.border_point(ch.frac)
			if mouse.distance_to(bp[0]) <= 26.0:
				start_drawing(i, bp)
				get_viewport().set_input_as_handled()
				return
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		var c = cell_of(mouse)
		if occupied.has(c):
			remove_route(occupied[c])
			get_viewport().set_input_as_handled()

# ---------- carrying molecules ----------

func spawn_carb(idx: int, ch: Dictionary) -> void:
	if traffic == null or membrane == null or stockpile == null:
		return
	var bp = membrane.border_point(ch.frac)
	var pos: Vector2 = bp[0]
	var normal: Vector2 = bp[1]
	var start = pos + normal * 32.0
	var pore_in = pos - normal * 28.0
	var path = path_for(idx)
	if path.size() > 0:
		var wps: Array = [pore_in]
		wps.append_array(path)
		traffic.add_particle(start, wps, true, "carb", 0.0, TRACK_SPEED)
	elif randf() < UNROUTED_YIELD:
		traffic.add_particle(start, [pore_in, stockpile.station_pos()], true, "carb", 0.0, 0.5)
	else:
		var lost = pore_in.lerp(stockpile.station_pos(), randf_range(0.2, 0.5))
		traffic.add_particle(start, [pore_in, lost], false, "", 0.0, 0.5, Color(0.5, 0.8, 1.0))

func _process(delta: float) -> void:
	t += delta
	if membrane == null:
		return
	screen = get_viewport_rect().size
	q = membrane.params()

	obstacle_timer -= delta
	if obstacle_timer <= 0.0:
		obstacle_timer = 0.4
		rebuild_obstacles()

	# tell the player what to do when a sugar channel appears
	if Game.channel_count.carb > prev_carb_channels:
		if not told_first:
			told_first = true
			toast("Sugar channel built! Drag from its glowing pore to the enzyme station to lay a route (it costs amino acids). Unrouted channels lose most of their molecules.")
		else:
			toast("New sugar channel: lay a route to the station.")
	prev_carb_channels = Game.channel_count.carb

	# sugar channels send their molecules along their route (or lose them)
	for i in Game.channel_list.size():
		var ch = Game.channel_list[i]
		if ch.type != "carb":
			continue
		timers[i] = timers.get(i, 0.0) + delta
		var interval = 1.0 / (Game.PER_CHANNEL * Game.intake_mult * Game.weights.carb)
		while timers[i] >= interval:
			timers[i] -= interval
			spawn_carb(i, ch)

	if drawing != null:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			update_drawing()
		else:
			finish_drawing()

	if toast_time > 0.0:
		toast_time -= delta
		toast_label.modulate.a = clampf(toast_time / 1.5, 0.0, 1.0)
	queue_redraw()

# ---------- drawing ----------

func draw_grid() -> void:
	var cols = int(ceil(screen.x / CELL))
	var rows = int(ceil(screen.y / CELL))
	for x in cols:
		for y in rows:
			var c = Vector2i(x, y)
			if not usable(c) or occupied.has(c):
				continue
			var p = cell_center(c)
			if blocked(c):
				draw_rect(Rect2(p - Vector2(10, 10), Vector2(20, 20)), Color(1.0, 0.35, 0.3, 0.14))
			else:
				draw_circle(p, 1.6, Color(1, 1, 1, 0.2))
	if stockpile != null:
		draw_arc(stockpile.station_pos(), station_reach(), 0.0, TAU, 36, Color(0.5, 1.0, 0.7, 0.4), 2.0, true)

func draw_route(r: Dictionary) -> void:
	var pts := PackedVector2Array()
	for c in r.cells:
		pts.append(cell_center(c))
	if r.join == -1 and stockpile != null:
		pts.append(stockpile.station_pos())
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(0.5, 0.8, 1.0, 0.16), 9.0, true)
	draw_polyline(pts, Color(0.75, 0.92, 1.0, 0.55), 2.5, true)
	for i in range(pts.size() - 1):
		var ph = fmod(t * 1.4 + i * 0.37, 1.0)
		draw_circle(pts[i].lerp(pts[i + 1], ph), 2.4, Color(1, 1, 1, 0.8))
	draw_circle(pts[0], 4.0, Color(0.75, 0.92, 1.0, 0.8))

func draw_preview() -> void:
	var pts := PackedVector2Array()
	for c in drawing.path:
		pts.append(cell_center(c))
	if drawing.end == "station" and stockpile != null:
		pts.append(stockpile.station_pos())
	var col = Color(1.0, 0.9, 0.4, 0.9)
	if pts.size() >= 2:
		draw_polyline(pts, Color(1.0, 0.9, 0.4, 0.25), 9.0, true)
		draw_polyline(pts, col, 3.0, true)
	draw_circle(pts[0], 5.0, col)
	draw_circle(pts[pts.size() - 1], 6.0 + sin(t * 8.0), col)
	var cost = route_cost(drawing.path.size())
	var msg = "keep going to the enzyme station"
	if drawing.end == "station":
		msg = "release to build"
	elif drawing.end == "join":
		msg = "joins a route, release to build"
	var text = "%d cells, %d amino - %s" % [drawing.path.size(), cost, msg]
	var tc = Color(0.7, 1.0, 0.7)
	if Game.stock.amino < cost:
		tc = Color(1.0, 0.5, 0.45)
	draw_string(ThemeDB.fallback_font, get_global_mouse_position() + Vector2(16, -12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)

func _draw() -> void:
	if membrane == null:
		return
	if drawing != null:
		draw_grid()
	for r in routes:
		draw_route(r)
	for i in Game.channel_list.size():
		var ch = Game.channel_list[i]
		if ch.type == "carb" and route_of(i) == null and drawing == null:
			var bp = membrane.border_point(ch.frac)
			var pulse = 0.5 + 0.5 * sin(t * 4.0)
			draw_arc(bp[0], 22.0 + 3.0 * pulse, 0.0, TAU, 28, Color(0.6, 0.9, 1.0, 0.5 + 0.4 * pulse), 2.0, true)
			if routes.is_empty():
				draw_string(ThemeDB.fallback_font, bp[0] + bp[1] * 44.0 + Vector2(-48, 4), "Drag to the station", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.95, 1.0, 0.9))
	if drawing != null:
		draw_preview()
