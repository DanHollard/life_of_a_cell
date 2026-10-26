extends Node2D

@export var margin: float = 60.0
@export var speed: float = 50.0
@export var waste_rate: float = 1.0
@export var out_color: Color = Color(0.9, 0.5, 0.4)

const COLORS = {
	"carb": Color(0.5, 0.8, 1.0),
	"lipid": Color(0.95, 0.75, 0.3),
	"amino": Color(0.7, 0.5, 0.9),
}

var particles: Array = []
var leak_timers = {"carb": 0.0, "lipid": 0.0, "amino": 0.0}
var out_timer: float = 0.0
var label := Label.new()
var buttons := {}
var mito_button := Button.new()
var membrane

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")

	var hud := CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	hud.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
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

func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append(str(cost[k]) + " " + str(k))
	return ", ".join(parts)

func _process(delta: float) -> void:
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

	# move particles from waypoint to waypoint
	var bounds = Rect2(Vector2.ZERO, get_viewport_rect().size).grow(20)
	var alive: Array = []
	for p in particles:
		p.age += delta
		var goal: Vector2 = p.waypoints[0]
		var to_goal: Vector2 = goal - p.pos
		if to_goal.length() < 8.0:
			p.waypoints.pop_front()
			if p.waypoints.is_empty():
				if p.inbound:
					Game.add(p.type)
				continue
			goal = p.waypoints[0]
			to_goal = goal - p.pos
		p.pos += to_goal.normalized() * p.speed * delta
		if p.age < p.life and bounds.has_point(p.pos):
			alive.append(p)
	particles = alive

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
	queue_redraw()

func spawn_leak(type: String) -> void:
	var screen = get_viewport_rect().size
	add_particle(random_edge_point(screen), [random_inner_point(screen)], true, type)

func spawn_from_channel(ch: Dictionary) -> void:
	if membrane == null:
		spawn_leak(ch.type)
		return
	var screen = get_viewport_rect().size
	var bp = membrane.border_point(ch.frac)
	var pos: Vector2 = bp[0]
	var normal: Vector2 = bp[1]
	add_particle(pos + normal * 32.0, [pos - normal * 28.0, random_inner_point(screen)], true, ch.type)

func spawn_waste() -> void:
	var screen = get_viewport_rect().size
	add_particle(random_inner_point(screen), [random_edge_point(screen)], false, "")

func add_particle(start: Vector2, waypoints: Array, inbound: bool, type: String) -> void:
	var color = out_color
	if inbound:
		color = COLORS[type]
	particles.append({
		"pos": start, "waypoints": waypoints, "speed": speed * randf_range(0.7, 1.3),
		"radius": randf_range(3.0, 6.0), "color": color,
		"inbound": inbound, "type": type, "age": 0.0, "life": 60.0,
	})

func random_edge_point(screen: Vector2) -> Vector2:
	match randi() % 4:
		0: return Vector2(randf() * screen.x, 0)
		1: return Vector2(randf() * screen.x, screen.y)
		2: return Vector2(0, randf() * screen.y)
		_: return Vector2(screen.x, randf() * screen.y)

func random_inner_point(screen: Vector2) -> Vector2:
	return Vector2(
		randf_range(margin * 2.0, screen.x - margin * 2.0),
		randf_range(margin * 2.0, screen.y - margin * 2.0))

func _draw() -> void:
	for p in particles:
		draw_circle(p.pos, p.radius, p.color)
