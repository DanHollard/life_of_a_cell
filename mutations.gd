extends Node2D

const FIRST_DRAFT := 90.0     # seconds into the run
const DRAFT_EVERY := 120.0    # seconds between drafts
const WILD_CHANCE := 0.25     # chance a draft contains an unstable mutation
const HGT_CHANCE := 0.08      # chance a draft contains the rare gene transfer
const TAG_ORDER := ["Glutton", "Armoured", "Engine", "Hoarder"]

const MUTS = {
	"leaky": {"name": "Leaky membrane", "tag": "Glutton",
		"up": "Intake +40%", "down": "Toxins hurt 30% more"},
	"cheap": {"name": "Cheap channels", "tag": "Glutton",
		"up": "Channels cost 35% less", "down": "Intake -10%"},
	"picky": {"name": "Picky receptors", "tag": "Glutton",
		"up": "Carbs arrive 1.8x as often", "down": "Lipids arrive 0.6x as often"},
	"shell": {"name": "Calcified shell", "tag": "Armoured",
		"up": "Toxin damage -50%", "down": "Intake -20%"},
	"thick": {"name": "Thick membrane", "tag": "Armoured",
		"up": "Toxin damage -35%", "down": "Channels cost 40% more"},
	"efflux": {"name": "Efflux pumps", "tag": "Armoured",
		"up": "Toxin damage -20%", "down": "Costs 0.2 ATP every second"},
	"overclock": {"name": "Overclocked mitochondria", "tag": "Engine",
		"up": "Mitochondria work 2x faster", "down": "Oxidative stress: toxins hurt 25% more"},
	"cristae": {"name": "Efficient cristae", "tag": "Engine",
		"up": "+1 ATP from every carb", "down": "Mitochondria 30% slower"},
	"supercharge": {"name": "Supercharged respiration", "tag": "Engine",
		"up": "Mitochondria 50% faster", "down": "Glycogen storage -8"},
	"bloat": {"name": "Glycogen bloat", "tag": "Hoarder",
		"up": "Glycogen storage +20", "down": "Intake -10%"},
	"packrat": {"name": "Packrat", "tag": "Hoarder",
		"up": "Glycogen storage +12", "down": "Costs 0.15 ATP every second"},
	"pantry": {"name": "Well-stocked pantry", "tag": "Hoarder",
		"up": "Instantly gain 15 lipids and 15 amino acids", "down": "Intake -15%"},
	"silent": {"name": "Silent mutation", "tag": "Neutral",
		"up": "Nothing happens.", "down": "Nothing at all."},
	"wild": {"name": "Unstable mutation", "tag": "Wild",
		"up": "Could be wonderful.", "down": "Could be terrible. You find out after."},
	"hgt": {"name": "Horizontal gene transfer", "tag": "Rare",
		"up": "You can now express BOTH flagellum and cilia. Intake +10%.", "down": "None. Lucky you."},
}

const WILD = {
	"frameshift": {"name": "Frameshift", "text": "Intake -30%"},
	"lucky": {"name": "Lucky duplication", "text": "Intake +50%"},
	"warp": {"name": "Membrane warp", "text": "Toxin damage -30% and +10 lipids"},
	"runaway": {"name": "Runaway growth", "text": "Storage +25, but toxins hurt 20% more"},
	"broken": {"name": "Broken sensor", "text": "Click reach -40%"},
	"accident": {"name": "Catalytic accident", "text": "+40 ATP right now"},
}

const BONUSES = {
	"Glutton": {"name": "Feeding frenzy", "text": "Intake +25%"},
	"Armoured": {"name": "Fortress", "text": "Toxin damage -25%"},
	"Engine": {"name": "Turbocharged", "text": "Mitochondria 50% faster"},
	"Hoarder": {"name": "Warehouse", "text": "Glycogen storage +15"},
}

var timer := FIRST_DRAFT
var nucleus
var hud_label := Label.new()
var toast_label := Label.new()
var toast_time := 0.0
var draft_layer: CanvasLayer
var cards_box := HBoxContainer.new()
var owned_label := Label.new()

func _ready() -> void:
	nucleus = get_parent().get_node_or_null("Nucleus")

	var hud := CanvasLayer.new()
	add_child(hud)
	var screen = get_viewport_rect().size
	hud_label.position = Vector2(14, screen.y - 126)
	hud_label.add_theme_font_size_override("font_size", 12)
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_label)

	toast_label.position = Vector2(screen.x * 0.5 - 260.0, 76)
	toast_label.custom_minimum_size = Vector2(520, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_font_size_override("font_size", 16)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.modulate.a = 0.0
	hud.add_child(toast_label)

	build_draft_screen()

func build_draft_screen() -> void:
	draft_layer = CanvasLayer.new()
	draft_layer.layer = 25
	draft_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	draft_layer.visible = false
	add_child(draft_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	draft_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	draft_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "A mutation arises"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Pick one. Every change costs something."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	cards_box.add_theme_constant_override("separation", 14)
	cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cards_box)

	owned_label.add_theme_font_size_override("font_size", 12)
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	owned_label.custom_minimum_size = Vector2(700, 0)
	box.add_child(owned_label)

	var skip := Button.new()
	skip.text = "Skip (absorb it for 10 amino acids)"
	skip.pressed.connect(skip_draft)
	box.add_child(skip)

func fmt_time(seconds: float) -> String:
	var s = int(seconds)
	return "%d:%02d" % [floori(float(s) / 60.0), s % 60]

func overlay_open() -> bool:
	return nucleus != null and nucleus.layer != null and nucleus.layer.visible

func tag_color(tag: String) -> Color:
	match tag:
		"Glutton": return Color(0.5, 0.85, 1.0)
		"Armoured": return Color(0.75, 0.8, 0.9)
		"Engine": return Color(1.0, 0.75, 0.4)
		"Hoarder": return Color(0.7, 0.95, 0.6)
		"Wild": return Color(0.9, 0.5, 1.0)
		"Rare": return Color(1.0, 0.9, 0.4)
	return Color(0.7, 0.7, 0.7)

func tag_counts() -> Dictionary:
	var counts = {}
	for tag in TAG_ORDER:
		counts[tag] = 0
	for id in Game.mutations:
		if MUTS.has(id) and counts.has(MUTS[id].tag):
			counts[MUTS[id].tag] += 1
	return counts

func tag_summary() -> String:
	var counts = tag_counts()
	var parts := PackedStringArray()
	for tag in TAG_ORDER:
		var mark = ""
		if Game.synergies.has(tag):
			mark = "*"
		parts.append("%s %d/3%s" % [tag, counts[tag], mark])
	return "   ".join(parts)

func owned_summary() -> String:
	if Game.mutations.is_empty():
		return "No mutations yet.     " + tag_summary()
	var names := PackedStringArray()
	for id in Game.mutations:
		if MUTS.has(id):
			names.append(MUTS[id].name)
		else:
			names.append(id)
	return "Your mutations: " + ", ".join(names) + "\n" + tag_summary()

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	toast_time = 5.0

func _process(delta: float) -> void:
	if Game.dead:
		return
	timer -= delta
	hud_label.text = "Next mutation in %s\n%s" % [fmt_time(maxf(timer, 0.0)), tag_summary()]

	if toast_time > 0.0:
		toast_time -= delta
		toast_label.modulate.a = clampf(toast_time / 1.5, 0.0, 1.0)

	if timer <= 0.0 and not overlay_open():
		open_draft()

func roll_draft() -> Array:
	var pool: Array = []
	for id in MUTS:
		if id != "wild" and id != "hgt" and not Game.mutations.has(id):
			pool.append(id)
	pool.shuffle()
	var result: Array = []
	for i in mini(3, pool.size()):
		result.append(pool[i])
	while result.size() < 3:
		result.append("wild")
	# sometimes a slot turns unstable, or the rare gene transfer turns up
	if randf() < WILD_CHANCE:
		result[randi() % 3] = "wild"
	if not Game.hgt and not Game.mutations.has("hgt") and randf() < HGT_CHANCE:
		result[randi() % 3] = "hgt"
	return result

func make_card(id: String) -> Control:
	var m = MUTS[id]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var name_label := Label.new()
	name_label.text = m.name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(220, 0)
	box.add_child(name_label)

	var tag_label := Label.new()
	tag_label.text = m.tag
	tag_label.modulate = tag_color(m.tag)
	box.add_child(tag_label)

	var up_label := Label.new()
	up_label.text = "+  " + m.up
	up_label.modulate = Color(0.6, 1.0, 0.7)
	up_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	up_label.custom_minimum_size = Vector2(220, 0)
	box.add_child(up_label)

	var down_label := Label.new()
	down_label.text = "-  " + m.down
	down_label.modulate = Color(1.0, 0.6, 0.55)
	down_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	down_label.custom_minimum_size = Vector2(220, 0)
	box.add_child(down_label)

	var take := Button.new()
	take.text = "Take it"
	take.pressed.connect(choose.bind(id))
	box.add_child(take)
	return card

func open_draft() -> void:
	timer = DRAFT_EVERY
	for child in cards_box.get_children():
		child.queue_free()
	for id in roll_draft():
		cards_box.add_child(make_card(id))
	owned_label.text = owned_summary()
	draft_layer.visible = true
	Sfx.play("open", 1.2)
	get_tree().paused = true

func skip_draft() -> void:
	Game.stock.amino += 10
	Game.changed.emit()
	draft_layer.visible = false
	get_tree().paused = false
	show_toast("Skipped: +10 amino acids")

func choose(id: String) -> void:
	draft_layer.visible = false
	get_tree().paused = false
	var message = ""
	if id == "wild":
		var key = WILD.keys().pick_random()
		apply_wild(key)
		Game.mutations.append("wild_" + key)
		message = "Unstable mutation: %s. %s" % [WILD[key].name, WILD[key].text]
	else:
		apply(id)
		Game.mutations.append(id)
		message = "%s: %s" % [MUTS[id].name, MUTS[id].up]
		if MUTS[id].down != "None. Lucky you." and MUTS[id].down != "Nothing at all.":
			message += "  (but: %s)" % MUTS[id].down
	message += check_synergies()
	show_toast(message)
	Sfx.play("gene", 0.9)
	Game.changed.emit()

func check_synergies() -> String:
	var text = ""
	var counts = tag_counts()
	for tag in TAG_ORDER:
		if counts[tag] >= 3 and not Game.synergies.has(tag):
			Game.synergies[tag] = true
			apply_bonus(tag)
			text += "\nSYNERGY: %s! %s" % [BONUSES[tag].name, BONUSES[tag].text]
	return text

func apply_bonus(tag: String) -> void:
	match tag:
		"Glutton": Game.gene_mult *= 1.25
		"Armoured": Game.tox_resist += 0.25
		"Engine": Game.convert_mult *= 1.5
		"Hoarder": Game.carb_cap += 15

func apply(id: String) -> void:
	match id:
		"leaky":
			Game.gene_mult *= 1.4
			Game.tox_resist -= 0.3
		"cheap":
			Game.channel_discount += 0.35
			Game.gene_mult *= 0.9
		"picky":
			Game.weights.carb *= 1.8
			Game.weights.lipid *= 0.6
		"shell":
			Game.tox_resist += 0.5
			Game.gene_mult *= 0.8
		"thick":
			Game.tox_resist += 0.35
			Game.channel_discount -= 0.4
		"efflux":
			Game.tox_resist += 0.2
			Game.atp_upkeep += 0.2
		"overclock":
			Game.convert_mult *= 2.0
			Game.tox_resist -= 0.25
		"cristae":
			Game.atp_yield += 1
			Game.convert_mult *= 0.7
		"supercharge":
			Game.convert_mult *= 1.5
			Game.carb_cap -= 8
		"bloat":
			Game.carb_cap += 20
			Game.gene_mult *= 0.9
		"packrat":
			Game.carb_cap += 12
			Game.atp_upkeep += 0.15
		"pantry":
			Game.stock.lipid += 15
			Game.stock.amino += 15
			Game.gene_mult *= 0.85
		"silent":
			pass
		"hgt":
			Game.hgt = true
			Game.gene_mult *= 1.1

func apply_wild(key: String) -> void:
	match key:
		"frameshift":
			Game.gene_mult *= 0.7
		"lucky":
			Game.gene_mult *= 1.5
		"warp":
			Game.tox_resist += 0.3
			Game.stock.lipid += 10
		"runaway":
			Game.carb_cap += 25
			Game.tox_resist -= 0.2
		"broken":
			Game.engulf_mult *= 0.6
		"accident":
			Game.stock.atp += 40
