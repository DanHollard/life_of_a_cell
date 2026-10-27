extends Node2D

const DAMAGE := 2.5
const REPAIR_COST := 3          # lipids per repair
const REPAIR_AMOUNT := 15.0
const REGEN := 0.3              # health regained per second once the water is clean
const TOXIN_SPEED := 22.0
const MAX_TOXINS := 12
const IMPACT_DIST := 22.0

var membrane
var nucleus
var toxins: Array = []
var wounds: Array = []
var effects: Array = []
var spawn_timer := 0.0
var beat_timer := 0.0
var toxins_popped := 0
var t := 0.0
var bar_label := Label.new()
var bar := ProgressBar.new()
var repair_button := Button.new()
var panel: PanelContainer
var death_layer: CanvasLayer
var stats_label := Label.new()

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")
	nucleus = get_parent().get_node_or_null("Nucleus")

	# the sound system keeps working while the game is paused on the death screen
	Sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	Game.died.connect(show_death)

	var hud := CanvasLayer.new()
	add_child(hud)
	panel = PanelContainer.new()
	hud.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	bar_label.custom_minimum_size = Vector2(170, 0)
	bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(bar_label)
	bar.custom_minimum_size = Vector2(200, 18)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	repair_button.pressed.connect(repair)
	row.add_child(repair_button)
	var screen = get_viewport_rect().size
	panel.position = Vector2(screen.x * 0.5 - 290.0, screen.y - 46.0)

	build_death_screen()

func build_death_screen() -> void:
	death_layer = CanvasLayer.new()
	death_layer.layer = 30
	death_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	death_layer.visible = false
	add_child(death_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.0, 0.02, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	death_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	death_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box_panel := PanelContainer.new()
	box_panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box_panel.add_child(box)

	var title := Label.new()
	title.text = "Your cell has lysed"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "The membrane gave way under toxin damage."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats_label)

	var again := Button.new()
	again.text = "Try again"
	again.pressed.connect(restart)
	box.add_child(again)

func fmt_time(seconds: float) -> String:
	var s = int(seconds)
	return "%d:%02d" % [floori(float(s) / 60.0), s % 60]

func show_death() -> void:
	stats_label.text = "Survived: %s     (best this session: %s)\nGenes expressed: %d\nChannels built: %d\nMitochondria: %d\nToxins destroyed: %d" % [
		fmt_time(Game.run_time), fmt_time(Game.best_time), Game.unlocked.size(),
		Game.channel_list.size(), Game.mitochondria, toxins_popped]
	death_layer.visible = true
	Sfx.play("close", 0.5)
	Sfx.play("overflow", 0.6)
	get_tree().paused = true

func restart() -> void:
	Game.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()

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

func repair() -> void:
	if Game.stock.lipid < REPAIR_COST or Game.integrity >= 100.0:
		return
	Game.stock.lipid -= REPAIR_COST
	Game.integrity = minf(100.0, Game.integrity + REPAIR_AMOUNT)
	Game.changed.emit()
	Sfx.play("build", 1.4)

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if overlay_open():
		return
	if panel.get_global_rect().has_point(event.position):
		return
	var mouse = get_global_mouse_position()
	var best = -1
	var best_d = Game.engulf_radius() + 6.0
	for i in toxins.size():
		var d = toxins[i].pos.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		effects.append({"pos": toxins[best].pos, "t": 0.0})
		toxins.remove_at(best)
		toxins_popped += 1
		Sfx.play("pop", 0.6)
		get_viewport().set_input_as_handled()

func spawn_toxin(q: Dictionary) -> void:
	if toxins.size() >= MAX_TOXINS:
		return
	var screen = get_viewport_rect().size
	for i in 40:
		var p = Vector2(randf_range(10.0, screen.x - 10.0), randf_range(112.0, screen.y - 10.0))
		var d = border_dist(p, q)
		if d > 38.0 and d < 64.0:
			toxins.append({"pos": p, "phase": randf() * TAU, "spin": 0.0})
			return

func hit(tox: Dictionary, q: Dictionary, n: Vector2) -> void:
	var dmg = DAMAGE * (1.0 - Game.tox_resist)
	var on_membrane = tox.pos - n * border_dist(tox.pos, q)
	wounds.append({"pos": on_membrane, "n": n})
	effects.append({"pos": tox.pos, "t": 0.0})
	Sfx.play("overflow", 1.4, 0.08)
	Game.damage(dmg)

func _process(delta: float) -> void:
	t += delta
	if membrane == null:
		return
	var q = membrane.params()

	# toxins appear in proportion to how toxic the water is
	var rate = 0.0
	if Game.toxin_level > 0.05:
		rate = Game.toxin_level * 0.8
	if rate > 0.0:
		spawn_timer += delta
		while spawn_timer >= 1.0 / rate:
			spawn_timer -= 1.0 / rate
			spawn_toxin(q)
	else:
		spawn_timer = 0.0

	# toxins drift towards the membrane
	var kept: Array = []
	for tox in toxins:
		var n = border_normal(tox.pos, q)
		var side = n.orthogonal() * sin(t * 2.0 + tox.phase) * 6.0
		tox.pos += (-n * TOXIN_SPEED + side) * delta
		tox.spin += delta * 2.0
		if border_dist(tox.pos, q) <= IMPACT_DIST:
			hit(tox, q, n)
		else:
			kept.append(tox)
	toxins = kept

	# the membrane heals slowly once the water is clean
	if Game.toxin_level < 0.2 and Game.integrity < 100.0:
		Game.integrity = minf(100.0, Game.integrity + REGEN * delta)
	var allowed = int(ceil((100.0 - Game.integrity) / DAMAGE))
	while wounds.size() > allowed:
		wounds.pop_front()

	var live_fx: Array = []
	for fx in effects:
		fx.t += delta
		if fx.t < 0.4:
			live_fx.append(fx)
	effects = live_fx

	# a heartbeat when you're close to death
	if Game.integrity < 30.0 and Game.integrity > 0.0:
		beat_timer += delta
		if beat_timer >= 0.9:
			beat_timer = 0.0
			Sfx.play("store", 0.5)
	else:
		beat_timer = 0.0

	# the health bar
	bar.value = Game.integrity
	var text = "Health %d%%" % int(round(Game.integrity))
	if Game.integrity < 60.0:
		text += "  (leaking)"
	bar_label.text = text
	var c = Color(0.5, 1.0, 0.6)
	if Game.integrity < 60.0:
		c = Color(1.0, 0.8, 0.3)
	if Game.integrity < 30.0:
		c = Color(1.0, 0.4, 0.4)
	bar.modulate = c
	repair_button.text = "Repair (%d lipids)" % REPAIR_COST
	repair_button.disabled = Game.stock.lipid < REPAIR_COST or Game.integrity >= 100.0
	queue_redraw()

func draw_toxin(tox: Dictionary) -> void:
	var c: Vector2 = tox.pos
	draw_circle(c, 13.0, Color(0.6, 0.15, 0.7, 0.18))
	for i in 8:
		var a = tox.spin + i * TAU / 8.0
		var dir = Vector2(cos(a), sin(a))
		draw_line(c + dir * 5.0, c + dir * 11.0, Color(0.75, 0.3, 0.85), 2.0)
	draw_circle(c, 6.5, Color(0.5, 0.12, 0.6))
	draw_circle(c, 3.0, Color(0.9, 0.5, 1.0))

# Red creeps in from the screen edges when health is low.
func draw_vignette() -> void:
	if Game.integrity >= 40.0:
		return
	var screen = get_viewport_rect().size
	var strength = (1.0 - Game.integrity / 40.0) * (0.6 + 0.4 * sin(t * 5.0))
	var col = Color(0.9, 0.1, 0.1, 0.12 * strength)
	for i in 5:
		var th = 14.0 * (i + 1)
		draw_rect(Rect2(0.0, 0.0, screen.x, th), col)
		draw_rect(Rect2(0.0, screen.y - th, screen.x, th), col)
		draw_rect(Rect2(0.0, 0.0, th, screen.y), col)
		draw_rect(Rect2(screen.x - th, 0.0, th, screen.y), col)

func _draw() -> void:
	for w in wounds:
		var pulse = 0.5 + 0.5 * sin(t * 5.0 + w.pos.x)
		draw_circle(w.pos, 11.0, Color(0.9, 0.2, 0.15, 0.25 + 0.15 * pulse))
		draw_circle(w.pos, 6.0, Color(1.0, 0.35, 0.25, 0.55 + 0.25 * pulse))
		draw_circle(w.pos, 2.5, Color(0.2, 0.02, 0.02, 0.9))
	for tox in toxins:
		draw_toxin(tox)
	for fx in effects:
		var k = fx.t / 0.4
		draw_arc(fx.pos, 6.0 + 22.0 * k, 0.0, TAU, 24, Color(0.8, 0.3, 0.9, 1.0 - k), 2.0, true)
	draw_vignette()
