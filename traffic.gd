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
var in_timer: float = 0.0
var out_timer: float = 0.0
var label := Label.new()
var button := Button.new()

func _ready() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	hud.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	button.pressed.connect(Game.build_channel)
	row.add_child(button)

func _process(delta: float) -> void:
	in_timer += delta
	out_timer += delta
	while in_timer >= 1.0 / Game.intake_rate():
		in_timer -= 1.0 / Game.intake_rate()
		spawn(true)
	while out_timer >= 1.0 / waste_rate:
		out_timer -= 1.0 / waste_rate
		spawn(false)

	var bounds = Rect2(Vector2.ZERO, get_viewport_rect().size).grow(20)
	var alive: Array = []
	for p in particles:
		p.pos += p.vel * delta
		p.age += delta
		if p.inbound and p.pos.distance_to(p.target) < 8.0:
			Game.add(p.type)
			continue
		if p.age < p.life and bounds.has_point(p.pos):
			alive.append(p)
	particles = alive

	label.text = "Carbs: %d   |   Lipids: %d   |   Amino acids: %d   |   Channels: %d   |   Intake: %.1f/s" % [
		Game.stock.carb, Game.stock.lipid, Game.stock.amino, Game.channels, Game.intake_rate()]
	button.text = "Build channel (%d amino acids)" % Game.channel_cost()
	button.disabled = Game.stock.amino < Game.channel_cost()
	queue_redraw()

func spawn(inbound: bool) -> void:
	var screen = get_viewport_rect().size
	var start: Vector2
	var target: Vector2
	var type = ""
	var color = out_color
	if inbound:
		start = random_edge_point(screen)
		target = random_inner_point(screen)
		type = Game.random_type()
		color = COLORS[type]
	else:
		start = random_inner_point(screen)
		target = random_edge_point(screen)
	var vel = (target - start).normalized() * speed * randf_range(0.7, 1.3)
	particles.append({
		"pos": start, "vel": vel, "target": target,
		"radius": randf_range(3.0, 6.0), "color": color,
		"inbound": inbound, "type": type,
		"age": 0.0, "life": 60.0,
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
