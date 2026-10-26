extends Node2D

@export var radius: float = 70.0
@export var fill_color := Color(0.35, 0.3, 0.55, 0.9)
@export var envelope_color := Color(0.6, 0.55, 0.85)
@export var nucleolus_color := Color(0.2, 0.15, 0.35)
@export var chromatin_color := Color(0.8, 0.7, 1.0, 0.7)

const NODE_SIZE := Vector2(190, 80)
const SPACING := Vector2(250, 110)
const PAD := Vector2(20, 20)

var t := 0.0
var hover := false
var layer: CanvasLayer
var lines: Control
var buttons := {}
var stock_label := Label.new()

func _ready() -> void:
	build_tree()
	Game.changed.connect(refresh_tree)

func _process(delta: float) -> void:
	t += delta
	hover = not layer.visible and get_local_mouse_position().length() <= radius
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not layer.visible and get_local_mouse_position().length() <= radius:
			layer.visible = true
			refresh_tree()

	if event.is_action_pressed("ui_cancel") and layer.visible:
		layer.visible = false

func _draw() -> void:
	var r = radius * (1.0 + 0.015 * sin(t * 1.5))

	var env = envelope_color
	if hover:
		env = envelope_color.lightened(0.4)

	draw_circle(Vector2.ZERO, r, fill_color)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, env, 3.0, true)
	draw_arc(Vector2.ZERO, r - 6.0, 0.0, TAU, 64, env.darkened(0.2), 1.5, true)

	for i in 12:
		var a = i * TAU / 12.0
		var pore = Vector2(cos(a), sin(a)) * r
		draw_circle(pore, 2.5, Color(0.1, 0.08, 0.2))

	draw_circle(Vector2(-r * 0.2, -r * 0.15), r * 0.25, nucleolus_color)

	for k in 4:
		var pts := PackedVector2Array()
		for j in 21:
			var x = lerpf(-r * 0.55, r * 0.55, j / 20.0)
			var y = sin(x * 0.12 + k * 1.3 + t * 0.6) * r * 0.12 + (k - 1.5) * r * 0.22 + r * 0.12
			pts.append(Vector2(x, y))
		draw_polyline(pts, chromatin_color, 2.0, true)

	var label_alpha = 0.5
	if hover:
		label_alpha = 1.0
	var label_color = Color(1, 1, 1, label_alpha)
	draw_string(ThemeDB.fallback_font, Vector2(-60, r + 26), "Genome", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, label_color)

func node_pos(id: String) -> Vector2:
	return PAD + Game.GENES[id].pos * SPACING

func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append(str(cost[k]) + " " + str(k))
	return ", ".join(parts)

func close_tree() -> void:
	layer.visible = false

func build_tree() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	layer.visible = false
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Genome: express genes to evolve"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var area := Control.new()
	var extent := Vector2.ZERO
	for gene_id in Game.GENES:
		var gp: Vector2 = Game.GENES[gene_id].pos
		extent.x = maxf(extent.x, gp.x)
		extent.y = maxf(extent.y, gp.y)
	area.custom_minimum_size = PAD * 2 + extent * SPACING + NODE_SIZE
	box.add_child(area)

	lines = Control.new()
	lines.size = area.custom_minimum_size
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(lines)
	lines.draw.connect(draw_lines)

	for id in Game.GENES:
		var btn := Button.new()
		btn.position = node_pos(id)
		btn.custom_minimum_size = NODE_SIZE
		btn.size = NODE_SIZE
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(Game.unlock.bind(id))
		area.add_child(btn)
		buttons[id] = btn

	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stock_label)

	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(close_tree)
	box.add_child(close)

func draw_lines() -> void:
	for id in Game.GENES:
		for need in Game.GENES[id].needs:
			var a = node_pos(need) + Vector2(NODE_SIZE.x, NODE_SIZE.y / 2.0)
			var b = node_pos(id) + Vector2(0, NODE_SIZE.y / 2.0)
			var col = Color(0.4, 0.4, 0.5)
			if Game.unlocked.has(need):
				col = Color(0.6, 0.9, 0.6)
			lines.draw_line(a, b, col, 3.0, true)

func refresh_tree() -> void:
	if not layer.visible:
		return
	for id in Game.GENES:
		var g = Game.GENES[id]
		var btn: Button = buttons[id]
		var done = Game.unlocked.has(id)
		var available = Game.prereqs_met(id)

		var name_text = g.name
		if done:
			name_text = "✓ " + g.name
		var cost_line = cost_text(g.cost)
		if done:
			cost_line = "Expressed"
		btn.text = name_text + "\n" + g.effect + "\n" + cost_line

		btn.disabled = done or not available or not Game.can_afford(g.cost)

		if done:
			btn.modulate = Color(0.6, 1.0, 0.6)
		elif available:
			btn.modulate = Color(1, 1, 1)
		else:
			btn.modulate = Color(0.5, 0.5, 0.55)

	stock_label.text = "Carbs: " + str(Game.stock.carb) + "   |   Lipids: " + str(Game.stock.lipid) + "   |   Amino acids: " + str(Game.stock.amino)
	lines.queue_redraw()
