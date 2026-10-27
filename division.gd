extends Node2D

var nucleus
var panel: PanelContainer
var info := Label.new()
var button := Button.new()
var progress := ProgressBar.new()
var win_layer: CanvasLayer
var flash_rect: ColorRect
var win_stats := Label.new()
var win_list := VBoxContainer.new()
var t := 0.0

func _ready() -> void:
	nucleus = get_parent().get_node_or_null("Nucleus")
	Game.divided.connect(show_win)

	var hud := CanvasLayer.new()
	add_child(hud)
	panel = PanelContainer.new()
	hud.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	info.add_theme_font_size_override("font_size", 12)
	info.custom_minimum_size = Vector2(250, 0)
	col.add_child(info)
	progress.custom_minimum_size = Vector2(250, 20)
	progress.show_percentage = false
	progress.min_value = 0.0
	progress.max_value = 1.0
	col.add_child(progress)
	button.text = "Begin division"
	button.tooltip_text = "Costs 5 carbs, 15 lipids, 15 amino acids and 20 ATP. Copying the genome takes 20 seconds, and toxins hit 50% harder while you do."
	button.pressed.connect(Game.begin_division)
	col.add_child(button)
	var screen = get_viewport_rect().size
	panel.position = Vector2(12, screen.y - 78)

	build_win_screen()

func build_win_screen() -> void:
	win_layer = CanvasLayer.new()
	win_layer.layer = 30
	win_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	win_layer.visible = false
	add_child(win_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.08, 0.06, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	win_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	win_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box_panel := PanelContainer.new()
	box_panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box_panel.add_child(box)

	var title := Label.new()
	title.text = "Division complete!"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Two cells where there was one."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	win_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(win_stats)

	var prompt := Label.new()
	prompt.text = "Choose a gene to pass on to your daughter cell:"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt)

	win_list.add_theme_constant_override("separation", 6)
	box.add_child(win_list)

	var fresh := Button.new()
	fresh.text = "Start fresh (inherit nothing new)"
	fresh.pressed.connect(next_generation)
	box.add_child(fresh)

	# a white flash when the cell divides
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_layer.add_child(flash_rect)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func fmt_time(seconds: float) -> String:
	var s = int(seconds)
	return "%d:%02d" % [floori(float(s) / 60.0), s % 60]

func show_win() -> void:
	win_stats.text = "Generation %d     Time: %s     (best this session: %s)\nGenes expressed: %d     Channels: %d     Mitochondria: %d" % [
		Game.generation, fmt_time(Game.run_time), fmt_time(Game.best_time),
		Game.unlocked.size(), Game.channel_list.size(), Game.mitochondria]

	for child in win_list.get_children():
		child.queue_free()
	for id in Game.unlocked.keys():
		var b := Button.new()
		b.text = "%s  -  %s" % [Game.GENES[id].name, Game.GENES[id].effect]
		b.pressed.connect(choose.bind(id))
		win_list.add_child(b)

	win_layer.visible = true
	flash_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.9)
	Sfx.play("gene")
	Sfx.play("build", 1.2)
	get_tree().paused = true

func choose(id: String) -> void:
	Game.inherit(id)
	next_generation()

func next_generation() -> void:
	Game.generation += 1
	Game.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _process(delta: float) -> void:
	t += delta

	var missing := PackedStringArray()
	for k in Game.DIVIDE_COST:
		var lack = Game.DIVIDE_COST[k] - Game.stock[k]
		if lack > 0:
			missing.append("%d %s" % [lack, k])

	if Game.replicating:
		info.text = "Gen %d: copying genome... %d%% (vulnerable!)" % [Game.generation, int(Game.replicate_progress * 100.0)]
	elif missing.is_empty():
		info.text = "Gen %d: ready to divide!" % Game.generation
	else:
		info.text = "Gen %d: missing %s" % [Game.generation, ", ".join(missing)]

	button.visible = not Game.replicating
	button.disabled = not Game.can_divide()
	progress.visible = Game.replicating
	progress.value = Game.replicate_progress
	queue_redraw()

func _draw() -> void:
	if Game.replicating and nucleus != null:
		var c: Vector2 = nucleus.global_position
		var pulse = 0.5 + 0.5 * sin(t * 6.0)
		draw_arc(c, 84.0, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 5.0, true)
		draw_arc(c, 84.0, -PI / 2.0, -PI / 2.0 + TAU * Game.replicate_progress, 48, Color(0.5, 1.0, 0.7), 5.0, true)
		draw_arc(c, 92.0 + 3.0 * pulse, 0.0, TAU, 48, Color(0.5, 1.0, 0.7, 0.25), 2.0, true)
