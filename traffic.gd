extends Node2D

@export var margin: float = 60.0
@export var speed: float = 50.0
@export var waste_rate: float = 1.0
@export var drift_rate: float = 1.5     # floating molecules appearing per second
@export var max_drifters: int = 22
@export var drift_life: float = 14.0
@export var out_color: Color = Color(0.9, 0.5, 0.4)

const COLORS = {
	"carb": Color(0.5, 0.8, 1.0),
	"lipid": Color(0.95, 0.75, 0.3),
	"amino": Color(0.7, 0.5, 0.9),
}
const ATP_COLOR := Color(1.0, 0.95, 0.5)
const GRANULE_COLOR := Color(0.88, 0.96, 1.0)
const DRIFT_SPEED := 22.0
const KEEP_OUT := 26.0     # drifters bounce off the membrane at this distance
const AUTO_DIST := 42.0    # phagocytosis range
const TOP_LIMIT := 110.0   # keeps drifters below the HUD

var particles: Array = []
var waiting: Array = []    # glucose drops queued at the enzyme station
var effects: Array = []
var leak_timers = {"carb": 0.0, "lipid": 0.0, "amino": 0.0}
var out_timer := 0.0
var drift_timer := 0.0
var proc_timer := 0.0
var next_id := 0
var hover_id := -1
var engulf_count := 0
var t := 0.0
var label := Label.new()
var hint := Label.new()
var buttons := {}
var mito_button := Button.new()
var hud_panel: PanelContainer
var membrane
var nucleus
var stockpile
var organelles

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")
	nucleus = get_parent().get_node_or_null("Nucleus")
	stockpile = get_parent().get_node_or_null("Stockpile")
	organelles = get_parent().get_node_or_null("Organelles")
	Game.converted.connect(_on_converted)

	var hud := CanvasLayer.new()
	add_child(hud)
	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(12, 12)
	hud.add_child(hud_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	hud_panel.add_child(col)
	col.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for type in Game.TYPES:
		var b := Button.new()
		b.pressed.connect(Game.build_channel.bind(type))
		row.add_child(b)
		buttons[type] = b
	mito_button.pressed.connect(Game.build_mitochondrion)
	row.add_child(mito_button)
	hint.text = "Click the glowing molecules outside the cell to engulf them"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.7)
	col.add_child(hint)

func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append(str(cost[k]) + " " + str(k))
	return ", ".join(parts)

func overlay_open() -> bool:
	return nucleus != null and nucleus.layer != null and nucleus.layer.visible

# Distance from the membrane's centre line: negative inside the cell, positive outside.
func border_dist(pos: Vector2, q: Dictionary) -> float:
	var c = Vector2((q.x0 + q.x1) * 0.5, (q.y0 + q.y1) * 0.5)
	var half = Vector2((q.x1 - q.x0) * 0.5, (q.y1 - q.y0) * 0.5) - Vector2(q.r, q.r)
	var d = (pos - c).abs() - half
	var outside = Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	var inside = minf(maxf(d.x, d.y), 0.0)
	return outside + inside - q.r

func border_normal(pos: Vector2, q: Dictionary) -> Vector2:
	var e = 2.0
	var g = Vector2(
		border_dist(pos + Vector2(e, 0), q) - border_dist(pos - Vector2(e, 0), q),
		border_dist(pos + Vector2(0, e), q) - border_dist(pos - Vector2(0, e), q))
	if g.length() < 0.001:
		return Vector2.UP
	return g.normalized()

# Where a molecule of this type should head once it is inside the cell.
func inner_target(type: String) -> Vector2:
	if type == "carb" and stockpile != null:
		return stockpile.station_pos()
	return random_inner_point(get_viewport_rect().size)

# Where the i-th drop in the queue waits, in a ring round the enzyme station.
func queue_slot(i: int) -> Vector2:
	var a = i * TAU / float(Game.QUEUE_MAX)
	var r = 30.0 + (Game.enzymes - 1) * 14.0
	return stockpile.station_pos() + Vector2(cos(a), sin(a)) * r

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if overlay_open():
		return
	if hud_panel.get_global_rect().has_point(event.position):
		return
	var mouse = get_global_mouse_position()
	var best = null
	var best_d = Game.engulf_radius()
	for p in particles:
		if p.drifter:
			var d = p.pos.distance_to(mouse)
			if d < best_d:
				best_d = d
				best = p
	if best != null:
		engulf(best)

func engulf(p: Dictionary) -> void:
	p.drifter = false
	p.inbound = true
	p.speed = speed * 3.0
	p.age = 0.0
	p.life = 60.0
	p.waypoints = [inner_target(p.type)]
	p.arrive = ""
	if p.type == "carb" and stockpile != null:
		p.arrive = "station"
	effects.append({"pos": p.pos, "t": 0.0, "color": Color(1, 1, 1)})
	engulf_count += 1

# A mitochondrion just converted a carb: show carb -> mitochondrion -> ATP -> nucleus.
func _on_converted() -> void:
	if stockpile == null or organelles == null or Game.mitochondria <= 0:
		return
	var n = randi() % Game.mitochondria
	var mpos: Vector2 = organelles.mito_global(n)
	var spos: Vector2 = stockpile.global_position
	add_particle(spos, [mpos], false, "", 0.0, 2.5, COLORS["carb"])
	if nucleus != null:
		var npos: Vector2 = nucleus.global_position
		var dirn = (npos - mpos).normalized()
		var wait = spos.distance_to(mpos) / (speed * 2.5)
		add_particle(mpos, [npos - dirn * 66.0], false, "", wait, 2.0, ATP_COLOR)

# Called when a particle reaches its last waypoint. Returns true if it stays in the world.
func finish_particle(p: Dictionary) -> bool:
	if p.arrive == "station":
		if waiting.size() >= Game.QUEUE_MAX:
			effects.append({"pos": p.pos, "t": 0.0, "color": Color(1.0, 0.35, 0.3)})
			return false
		p.queued = true
		p.life = 9999.0
		waiting.append(p)
		return true
	if p.arrive == "store":
		if not Game.add("carb"):
			effects.append({"pos": p.pos, "t": 0.0, "color": Color(1.0, 0.35, 0.3)})
		return false
	if p.inbound:
		if not Game.add(p.type):
			effects.append({"pos": p.pos, "t": 0.0, "color": Color(1.0, 0.35, 0.3)})
	return false

# The enzyme turns one queued glucose drop into a glycogen granule.
func process_one() -> void:
	var p = waiting.pop_front()
	p.queued = false
	p.arrive = "store"
	p.color = GRANULE_COLOR
	p.radius = 6.5
	p.speed = speed * 2.0
	p.life = 60.0
	p.age = 0.0
	p.waypoints = [stockpile.global_position]
	effects.append({"pos": p.pos, "t": 0.0, "color": Color(1.0, 0.85, 0.5)})

func _process(delta: float) -> void:
	t += delta
	var screen = get_viewport_rect().size
	var q = null
	if membrane != null:
		q = membrane.params()

	# molecules leaking through the plain membrane
	for type in Game.TYPES:
		leak_timers[type] += delta
		var leak_interval = 1.0 / (Game.BASE_LEAK * Game.intake_mult * Game.weights[type])
		while leak_timers[type] >= leak_interval:
			leak_timers[type] -= leak_interval
			spawn_leak(type)

	# molecules coming through each channel
	for ch in Game.channel_list:
		ch.timer += delta
		var ch_interval = 1.0 / (Game.PER_CHANNEL * Game.intake_mult * Game.weights[ch.type])
		while ch.timer >= ch_interval:
			ch.timer -= ch_interval
			spawn_from_channel(ch)

	out_timer += delta
	while out_timer >= 1.0 / waste_rate:
		out_timer -= 1.0 / waste_rate
		spawn_waste()

	# floating molecules you can click
	drift_timer += delta
	while drift_timer >= 1.0 / drift_rate:
		drift_timer -= 1.0 / drift_rate
		spawn_drifter(screen, q)

	# the enzymes work through the queue
	for i in waiting.size():
		waiting[i].slot = i
	Game.station_queue = waiting.size()
	if waiting.size() > 0 and stockpile != null:
		proc_timer += delta
		var proc_interval = 1.0 / (Game.ENZYME_RATE * Game.enzymes)
		while proc_timer >= proc_interval and waiting.size() > 0:
			proc_timer -= proc_interval
			process_one()
	else:
		proc_timer = 0.0

	# move everything
	var mouse = get_global_mouse_position()
	hover_id = -1
	var hover_d = Game.engulf_radius()
	var bounds = Rect2(Vector2.ZERO, screen).grow(20)
	var alive: Array = []
	for p in particles:
		if p.delay > 0.0:
			p.delay -= delta
			alive.append(p)
			continue
		p.age += delta
		if p.drifter:
			if p.age >= p.life:
				continue
			update_drifter(p, delta, q, screen)
			if Game.auto_engulf and q != null and border_dist(p.pos, q) < AUTO_DIST:
				engulf(p)
			else:
				var d = p.pos.distance_to(mouse)
				if d < hover_d:
					hover_d = d
					hover_id = p.id
			alive.append(p)
			continue

		if p.queued:
			if stockpile != null:
				p.pos = p.pos.lerp(queue_slot(p.slot), minf(1.0, 8.0 * delta))
			alive.append(p)
			continue

		var goal: Vector2 = p.waypoints[0]
		var to_goal: Vector2 = goal - p.pos
		if to_goal.length() < 8.0:
			p.waypoints.pop_front()
			if p.waypoints.is_empty():
				if finish_particle(p):
					alive.append(p)
				continue
			goal = p.waypoints[0]
			to_goal = goal - p.pos
		p.pos += to_goal.normalized() * p.speed * delta
		if p.age < p.life and bounds.has_point(p.pos):
			alive.append(p)
	particles = alive
	if overlay_open():
		hover_id = -1

	var live_fx: Array = []
	for fx in effects:
		fx.t += delta
		if fx.t < 0.35:
			live_fx.append(fx)
	effects = live_fx

	# HUD
	label.text = "Carbs: %d   |   Lipids: %d   |   Amino acids: %d   |   ATP: %d   |   Intake: %.1f/s" % [
		Game.stock.carb, Game.stock.lipid, Game.stock.amino, Game.stock.atp, Game.intake_rate()]
	for type in Game.TYPES:
		var cost = Game.channel_cost(type)
		buttons[type].text = "%s channel [%d]  (%d amino)" % [Game.NAMES[type], Game.channel_count[type], cost]
		buttons[type].disabled = Game.stock.amino < cost

	mito_button.visible = Game.mitochondria > 0
	var mc = Game.mito_cost()
	mito_button.text = "Mitochondrion [%d]  (%s)" % [Game.mitochondria, cost_text(mc)]
	mito_button.disabled = not Game.can_afford(mc)
	hint.visible = engulf_count < 5
	queue_redraw()

func update_drifter(p: Dictionary, delta: float, q, screen: Vector2) -> void:
	p.dir = p.dir.rotated(randf_range(-1.0, 1.0) * 2.5 * delta)
	var next: Vector2 = p.pos + p.dir * p.speed * delta
	if q != null and border_dist(next, q) < KEEP_OUT:
		var n = border_normal(p.pos, q)
		if p.dir.dot(n) < 0.0:
			p.dir = p.dir.bounce(n)
			next = p.pos
	if next.x < 8.0 or next.x > screen.x - 8.0:
		p.dir = Vector2(-p.dir.x, p.dir.y)
		next = p.pos
	if next.y < TOP_LIMIT or next.y > screen.y - 8.0:
		p.dir = Vector2(p.dir.x, -p.dir.y)
		next = p.pos
	p.pos = next

func spawn_drifter(screen: Vector2, q) -> void:
	var count := 0
	for p in particles:
		if p.drifter:
			count += 1
	if count >= max_drifters:
		return
	var pos := Vector2.ZERO
	var ok := false
	for i in 30:
		pos = Vector2(randf_range(10.0, screen.x - 10.0), randf_range(TOP_LIMIT, screen.y - 10.0))
		if q == null or border_dist(pos, q) > 34.0:
			ok = true
			break
	if not ok:
		return
	var type = Game.random_type()
	particles.append({
		"id": next_id, "pos": pos, "waypoints": [],
		"speed": DRIFT_SPEED * randf_range(0.7, 1.3),
		"radius": randf_range(4.0, 6.0), "color": COLORS[type],
		"inbound": false, "drifter": true, "dir": Vector2.from_angle(randf() * TAU),
		"type": type, "age": 0.0, "life": drift_life, "delay": 0.0,
		"arrive": "", "queued": false, "slot": 0,
	})
	next_id += 1

func spawn_leak(type: String) -> void:
	var screen = get_viewport_rect().size
	add_particle(random_edge_point(screen), [inner_target(type)], true, type)

func spawn_from_channel(ch: Dictionary) -> void:
	if ch.type == "carb":
		return   # sugar channels are handled by the Routes node
	if membrane == null:
		spawn_leak(ch.type)
		return
	var bp = membrane.border_point(ch.frac)
	var pos: Vector2 = bp[0]
	var normal: Vector2 = bp[1]
	add_particle(pos + normal * 32.0, [pos - normal * 28.0, inner_target(ch.type)], true, ch.type)

func spawn_waste() -> void:
	var screen = get_viewport_rect().size
	add_particle(random_inner_point(screen), [random_edge_point(screen)], false, "")

func add_particle(start: Vector2, waypoints: Array, inbound: bool, type: String,
		delay: float = 0.0, speed_mult: float = 1.0, tint = null) -> void:
	var color = out_color
	if tint != null:
		color = tint
	elif inbound:
		color = COLORS[type]
	var arrive = ""
	if inbound and type == "carb" and stockpile != null:
		arrive = "station"
	particles.append({
		"id": next_id, "pos": start, "waypoints": waypoints,
		"speed": speed * speed_mult * randf_range(0.7, 1.3),
		"radius": randf_range(3.0, 6.0), "color": color,
		"inbound": inbound, "drifter": false, "dir": Vector2.ZERO,
		"type": type, "age": 0.0, "life": 60.0, "delay": delay,
		"arrive": arrive, "queued": false, "slot": 0,
	})
	next_id += 1

# A point in the water just outside the cell, where molecules and waste come and go.
func random_edge_point(screen: Vector2) -> Vector2:
	if membrane != null:
		var bp = membrane.border_point(randf())
		return bp[0] + bp[1] * randf_range(70.0, 150.0)
	match randi() % 4:
		0: return Vector2(randf() * screen.x, 0)
		1: return Vector2(randf() * screen.x, screen.y)
		2: return Vector2(0, randf() * screen.y)
		_: return Vector2(screen.x, randf() * screen.y)

# A point well inside the cell.
func random_inner_point(screen: Vector2) -> Vector2:
	if membrane != null:
		var q = membrane.params()
		for i in 30:
			var p = Vector2(randf_range(q.x0, q.x1), randf_range(q.y0, q.y1))
			if border_dist(p, q) < -60.0:
				return p
	return Vector2(
		randf_range(margin * 2.0, screen.x - margin * 2.0),
		randf_range(margin * 2.0, screen.y - margin * 2.0))

func _draw() -> void:
	for p in particles:
		if p.delay > 0.0:
			continue
		if p.drifter:
			var fade = minf(p.age / 0.6, 1.0) * clampf((p.life - p.age) / 1.5, 0.0, 1.0)
			var c: Color = p.color
			c.a = fade
			draw_circle(p.pos, p.radius, c)
			var ring = 5.0 + 1.5 * sin(t * 4.0 + p.id)
			draw_arc(p.pos, p.radius + ring, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.5 * fade), 1.5, true)
			if p.id == hover_id:
				draw_arc(p.pos, p.radius + 10.0, 0.0, TAU, 24, Color(1, 1, 1, fade), 2.0, true)
		else:
			draw_circle(p.pos, p.radius, p.color)
	for fx in effects:
		var k = fx.t / 0.35
		var col: Color = fx.color
		col.a = 1.0 - k
		draw_arc(fx.pos, 6.0 + 26.0 * k, 0.0, TAU, 28, col, 2.0, true)
