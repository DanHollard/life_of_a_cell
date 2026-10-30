extends Node2D

const FIRST_VIRUS := 75.0      # seconds into the run
const SHOW_PANEL_AT := 55.0
const VIRUS_SPEED := 20.0
const DOCK_DIST := 18.0
const ENTRY_TIME := 3.5        # seconds a docked virus needs to get in
const GROW := 0.045            # infection load gained per second
const START_LOAD := 0.15
const LEARN_TIME := 10.0       # seconds for Dicer to learn a strain
const SILENCE := 0.075         # load removed per second once RISC knows the strain
const BURST_DAMAGE := 10.0
const ATP_DRAIN := 0.5         # ATP per second per infection
const MAX_VIRUSES := 8
const MAX_INFECTIONS := 5

# the engulfing sequence
const T_REACH := 0.5           # membrane arms reach out
const T_WRAP := 0.35           # the vesicle closes round the virus
const PULL_MIN := 1.0          # shortest trip into the cell
const PULL_MAX := 2.6          # longest trip (to a far lysosome)
const PULL_SPEED := 160.0      # pixels per second the vesicle travels
const T_FUSE := 0.4            # the vesicle merges with a lysosome
const T_DIGEST := 1.5          # the lysosome breaks the virus down
const VESICLE_R := 22.0
const LYSO_R := 28.0
const DIGEST_DEPTH := 90.0     # how far in the temporary lysosome forms (if you own none)
const AMINO_REWARD := 2
const BREAKOUT_CHANCE := 0.10  # chance a swallowed virus escapes the lysosome

const STRAINS = [
	{"name": "Alpha", "color": Color(0.8, 1.0, 0.3), "spikes": 6},
	{"name": "Beta", "color": Color(1.0, 0.4, 0.7), "spikes": 8},
	{"name": "Gamma", "color": Color(0.2, 0.9, 0.7), "spikes": 10},
	{"name": "Delta", "color": Color(1.0, 0.35, 0.3), "spikes": 12},
]

const UPGRADES = {
	"dicer": {"name": "Dicer", "cost": {"amino": 8, "lipid": 3},
		"tip": "Chops viral RNA into siRNAs. Reveals infections and learns each strain in 10 seconds."},
	"risc": {"name": "RISC", "cost": {"amino": 12, "lipid": 6},
		"tip": "Uses siRNAs to silence viruses the cell has learned. Needs Dicer."},
	"interferon": {"name": "Interferon response", "cost": {"amino": 10, "lipid": 8, "atp": 25},
		"tip": "Alarm signal: viruses enter 2x slower, replicate 40% slower and escape lysosomes half as often. Costs ATP while any virus is present."},
}

var membrane
var nucleus
var t := 0.0
var next_spawn := FIRST_VIRUS
var cur_entry := ENTRY_TIME
var viruses: Array = []
var engulfs: Array = []
var infections: Array = []
var effects: Array = []
var has := {"dicer": false, "risc": false, "interferon": false}
var seen := {}        # strain index -> true
var learned := {}     # strain index -> true
var applied_pen := 1.0
var atp_acc := 0.0
var warned := false
var sluggish_told := false
var toast_label := Label.new()
var toast_time := 0.0
var panel: PanelContainer
var status := Label.new()
var buttons := {}

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")
	nucleus = get_parent().get_node_or_null("Nucleus")

	var hud := CanvasLayer.new()
	add_child(hud)

	panel = PanelContainer.new()
	panel.visible = false
	hud.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Immunity"
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	for id in UPGRADES:
		var b := Button.new()
		b.tooltip_text = UPGRADES[id].tip
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(250, 0)
		b.pressed.connect(buy.bind(id))
		box.add_child(b)
		buttons[id] = b
	status.add_theme_font_size_override("font_size", 11)
	status.custom_minimum_size = Vector2(250, 0)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	place_panel()

	var screen = get_viewport_rect().size
	toast_label.position = Vector2(screen.x * 0.5 - 280.0, 104)
	toast_label.custom_minimum_size = Vector2(560, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_font_size_override("font_size", 15)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.modulate.a = 0.0
	hud.add_child(toast_label)

# Waits a frame so the panel knows its size, then tucks it into the bottom-right corner.
func place_panel() -> void:
	await get_tree().process_frame
	var screen = get_viewport_rect().size
	panel.position = Vector2(screen.x - panel.size.x - 12.0, screen.y - panel.size.y - 12.0)

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	toast_time = 6.0

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

func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append(str(cost[k]) + " " + str(k))
	return ", ".join(parts)

func buy(id: String) -> void:
	if has[id]:
		return
	var u = UPGRADES[id]
	if id == "risc" and not has.dicer:
		return
	if not Game.can_afford(u.cost):
		return
	for k in u.cost:
		Game.stock[k] -= u.cost[k]
	has[id] = true
	Game.changed.emit()
	Sfx.play("gene", 1.1)
	show_toast("%s: %s" % [u.name, u.tip])

func spawn_virus(strain: int) -> void:
	if viruses.size() >= MAX_VIRUSES or membrane == null:
		return
	var q = membrane.params()
	var screen = get_viewport_rect().size
	for i in 40:
		var p = Vector2(randf_range(10.0, screen.x - 10.0), randf_range(112.0, screen.y - 10.0))
		var d = border_dist(p, q)
		if d > 50.0 and d < 120.0:
			viruses.append({"pos": p, "strain": strain, "docked": false, "timer": 0.0,
				"phase": randf() * TAU, "spin": 0.0, "n": Vector2.UP})
			seen[strain] = true
			return

func enter_cell(v: Dictionary) -> void:
	if infections.size() >= MAX_INFECTIONS:
		return
	var n: Vector2 = v.n
	var inside = v.pos - n * randf_range(60.0, 110.0)
	infections.append({"strain": v.strain, "load": START_LOAD, "learn": 0.0,
		"pos": inside, "phase": randf() * TAU})
	effects.append({"pos": v.pos, "t": 0.0, "color": STRAINS[v.strain].color})
	Sfx.play("overflow", 0.8)
	if has.dicer:
		show_toast("Infection! Strain %s has entered the cell." % STRAINS[v.strain].name)
	elif not sluggish_told:
		sluggish_told = true
		show_toast("Your cell feels sluggish... something is wrong inside.")

func burst(ix: Dictionary) -> void:
	effects.append({"pos": ix.pos, "t": 0.0, "color": STRAINS[ix.strain].color, "big": true})
	Sfx.play("overflow", 0.5)
	Sfx.play("close", 0.6)
	Game.damage(BURST_DAMAGE)
	for i in 3:
		spawn_virus(ix.strain)
	show_toast("BURST! New viruses are released and the membrane is damaged.")

# The closest resident lysosome (from the Backdrop node), if the cell has any yet.
func nearest_lysosome(from: Vector2) -> Dictionary:
	var backdrop = get_parent().get_node_or_null("Backdrop")
	if backdrop == null:
		return {"found": false, "pos": Vector2.ZERO}
	var best = Vector2.ZERO
	var best_d = INF
	var found = false
	for p in backdrop.lysosome_positions():
		var d = from.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
			found = true
	return {"found": found, "pos": best}

# The membrane starts reaching out to swallow this virus.
func start_engulf(v: Dictionary) -> void:
	var q = membrane.params()
	var n = border_normal(v.pos, q)
	var dv = border_dist(v.pos, q)
	var chance = BREAKOUT_CHANCE
	if has.interferon:
		chance *= 0.5
	var contact: Vector2 = v.pos - n * dv
	var dest: Vector2 = contact - n * DIGEST_DEPTH
	var resident = false
	var res = nearest_lysosome(v.pos)
	if res.found:
		dest = res.pos
		resident = true
	var pull = clampf(v.pos.distance_to(dest) / PULL_SPEED, PULL_MIN, PULL_MAX)
	engulfs.append({"V": v.pos, "n": n, "A": contact, "dest": dest, "resident": resident,
		"strain": v.strain, "age": 0.0, "spin": v.spin, "breaks": randf() < chance,
		"pull": pull, "total": T_REACH + T_WRAP + pull + T_FUSE + T_DIGEST})

func finish_engulf(e: Dictionary) -> void:
	var dest: Vector2 = e.dest
	if e.breaks:
		breakout(e, dest)
		return
	Game.stock.amino += AMINO_REWARD
	Game.changed.emit()
	effects.append({"pos": dest, "t": 0.0, "color": Color(0.5, 1.0, 0.7)})
	effects.append({"pos": dest, "t": 0.0, "life": 1.1, "color": Color(0.8, 0.6, 1.0),
		"text": "+%d amino" % AMINO_REWARD})
	Sfx.play("store", 1.5)

# The virus tears out of the lysosome and starts replicating in the cytoplasm.
func breakout(e: Dictionary, dest: Vector2) -> void:
	effects.append({"pos": dest, "t": 0.0, "color": Color(1.0, 0.35, 0.25), "big": true})
	Sfx.play("overflow", 0.6)
	Sfx.play("close", 0.7)
	if infections.size() >= MAX_INFECTIONS:
		show_toast("The virus tore out of the lysosome, but the cell is already overwhelmed.")
		Game.damage(3.0)
		return
	infections.append({"strain": e.strain, "load": START_LOAD, "learn": 0.0,
		"pos": dest, "phase": randf() * TAU})
	if has.dicer:
		show_toast("It escaped the lysosome! Strain %s is replicating in the cytoplasm." % STRAINS[e.strain].name)
	else:
		show_toast("Something tore out of the lysosome...")

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if overlay_open() or membrane == null:
		return
	if panel.visible and panel.get_global_rect().has_point(event.position):
		return
	var mouse = get_global_mouse_position()
	var best = -1
	var best_d = Game.engulf_radius() + 8.0
	for i in viruses.size():
		var d = viruses[i].pos.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		start_engulf(viruses[best])
		viruses.remove_at(best)
		Sfx.play("absorb", 0.6)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	t += delta
	if membrane == null:
		return
	var q = membrane.params()

	panel.visible = t >= SHOW_PANEL_AT
	if not warned and t >= SHOW_PANEL_AT:
		warned = true
		show_toast("The water is stirring... viruses are coming. Click them to engulf them (a few may escape digestion), or build an immunity (bottom right).")

	# a new virus arrives every so often, and gets more frequent over time
	if t >= next_spawn:
		var active = mini(4, 1 + int(t / 150.0))
		spawn_virus(randi() % active)
		next_spawn = t + maxf(16.0, 40.0 - t / 12.0) + randf_range(-4.0, 4.0)

	cur_entry = ENTRY_TIME
	var grow = GROW
	if has.interferon:
		cur_entry *= 2.0
		grow *= 0.6

	# viruses drift in, dock, then get inside
	var kept: Array = []
	for v in viruses:
		v.spin += delta * 1.5
		if v.docked:
			v.timer += delta
			if v.timer >= cur_entry:
				enter_cell(v)
				continue
		else:
			var n = border_normal(v.pos, q)
			v.n = n
			var side = n.orthogonal() * sin(t * 1.7 + v.phase) * 8.0
			v.pos += (-n * VIRUS_SPEED + side) * delta
			if border_dist(v.pos, q) <= DOCK_DIST:
				v.docked = true
				v.timer = 0.0
				Sfx.play("tick", 0.6)
		kept.append(v)
	viruses = kept

	# viruses being swallowed
	var kept_e: Array = []
	for e in engulfs:
		var prev: float = e.age
		e.age += delta
		e.spin += delta * 1.5
		if prev < T_REACH + T_WRAP and e.age >= T_REACH + T_WRAP:
			Sfx.play("pop", 1.3)
		if e.age >= e.total:
			finish_engulf(e)
			continue
		kept_e.append(e)
	engulfs = kept_e

	# infections grow, get learned, get silenced or burst
	var alive_inf: Array = []
	for ix in infections:
		ix.load += grow * delta
		if has.dicer and not learned.has(ix.strain):
			ix.learn += delta / LEARN_TIME
			if ix.learn >= 1.0:
				learned[ix.strain] = true
				show_toast("Dicer has learned strain %s. RISC can silence it now." % STRAINS[ix.strain].name)
				Sfx.play("gene", 1.2)
		if has.risc and learned.has(ix.strain):
			ix.load -= SILENCE * delta
		if ix.load <= 0.0:
			show_toast("Strain %s silenced!" % STRAINS[ix.strain].name)
			effects.append({"pos": ix.pos, "t": 0.0, "color": Color(0.5, 1.0, 1.0)})
			Sfx.play("store", 1.5)
			continue
		if ix.load >= 1.0:
			burst(ix)
			continue
		alive_inf.append(ix)
	infections = alive_inf

	# infections hijack the cell's machinery (intake) and burn its ATP
	var target = maxf(0.4, pow(0.8, infections.size()))
	if absf(target - applied_pen) > 0.0001:
		Game.gene_mult *= target / applied_pen
		applied_pen = target

	var drain = ATP_DRAIN * infections.size()
	if has.interferon and (infections.size() > 0 or viruses.size() > 0):
		drain += 0.4
	if drain > 0.0:
		atp_acc += drain * delta
		while atp_acc >= 1.0:
			atp_acc -= 1.0
			if Game.stock.atp > 0:
				Game.stock.atp -= 1

	var live_fx: Array = []
	for fx in effects:
		fx.t += delta
		if fx.t < fx.get("life", 0.45):
			live_fx.append(fx)
	effects = live_fx

	if toast_time > 0.0:
		toast_time -= delta
		toast_label.modulate.a = clampf(toast_time / 1.5, 0.0, 1.0)

	# the immunity panel
	for id in UPGRADES:
		var u = UPGRADES[id]
		var b: Button = buttons[id]
		if has[id]:
			b.text = "✓ " + u.name
			b.disabled = true
		else:
			b.text = "%s  (%s)" % [u.name, cost_text(u.cost)]
			var ok = Game.can_afford(u.cost)
			if id == "risc" and not has.dicer:
				ok = false
			b.disabled = not ok
	var parts := PackedStringArray()
	for s in seen.keys():
		var label = STRAINS[s].name
		if learned.has(s):
			label += " (siRNA ready)"
		parts.append(label)
	if parts.is_empty():
		status.text = "No viruses seen yet."
	else:
		status.text = "Strains seen: " + ", ".join(parts)
	queue_redraw()

# ---------- drawing ----------

func draw_virus_at(c: Vector2, strain: int, spin: float, sc: float, al: float) -> void:
	var s = STRAINS[strain]
	var col: Color = s.color
	var spikes: int = s.spikes
	draw_circle(c, 17.0 * sc, Color(col.r, col.g, col.b, 0.12 * al))
	for i in spikes:
		var a = spin + i * TAU / float(spikes)
		var dir = Vector2(cos(a), sin(a))
		draw_line(c + dir * 8.0 * sc, c + dir * 14.0 * sc, Color(col.r, col.g, col.b, al), 2.0)
		draw_circle(c + dir * 14.0 * sc, 1.8, Color(col.r, col.g, col.b, al))
	draw_circle(c, 8.5 * sc, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, al))
	draw_arc(c, 8.5 * sc, 0.0, TAU, 6, Color(col.r, col.g, col.b, al), 2.0, true)
	draw_circle(c, 3.0 * sc, Color(col.r, col.g, col.b, al))

func draw_virus(v: Dictionary) -> void:
	draw_virus_at(v.pos, v.strain, v.spin, 1.0, 1.0)
	if v.docked:
		var p = clampf(v.timer / cur_entry, 0.0, 1.0)
		draw_arc(v.pos, 21.0, -PI / 2.0, -PI / 2.0 + TAU * p, 28, Color(1, 1, 1, 0.9), 2.5, true)

func draw_infection(ix: Dictionary) -> void:
	var s = STRAINS[ix.strain]
	var col: Color = s.color
	var c: Vector2 = ix.pos
	var lv: float = ix.load
	if not has.dicer:
		# without Dicer you can only sense that something is wrong
		draw_circle(c, 10.0 + 10.0 * lv, Color(col.r, col.g, col.b, 0.07))
		return
	draw_circle(c, 9.0 + 12.0 * lv, Color(col.r, col.g, col.b, 0.3))
	draw_circle(c, 5.0 + 6.0 * lv, Color(col.r, col.g, col.b, 0.6))
	var n = int(lv * 14.0)
	for i in n:
		var a = ix.phase + i * 2.39996
		var r = 9.0 + 14.0 * sqrt(float(i) / 14.0) * lv
		draw_circle(c + Vector2(cos(a), sin(a)) * r, 2.0, col)
	draw_arc(c, 26.0, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 2.5, true)
	draw_arc(c, 26.0, -PI / 2.0, -PI / 2.0 + TAU * lv, 28, Color(1, 1, 1, 0.85), 2.5, true)
	if learned.has(ix.strain) and has.risc:
		draw_arc(c, 31.0 + 2.0 * sin(t * 6.0), 0.0, TAU, 28, Color(0.5, 1.0, 1.0, 0.7), 1.5, true)
	elif not learned.has(ix.strain):
		draw_arc(c, 32.0, -PI / 2.0, -PI / 2.0 + TAU * ix.learn, 28, Color(0.6, 0.8, 1.0, 0.8), 1.5, true)
	draw_string(ThemeDB.fallback_font, c + Vector2(-24, -36), s.name, HORIZONTAL_ALIGNMENT_CENTER, 48, 12, Color(1, 1, 1, 0.9))

func ease_io(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)

# A point along one of the two membrane arms that reach round the virus.
func arm_point(e: Dictionary, side: float, u: float) -> Vector2:
	var tang: Vector2 = e.n.orthogonal()
	var start: Vector2 = e.A + tang * side * 10.0
	var dist: float = (e.V - e.A).dot(e.n)
	var ctrl: Vector2 = e.A + e.n * dist * 0.6 + tang * side * (VESICLE_R + 16.0)
	var finish: Vector2 = e.V + tang * side * VESICLE_R
	var a = start.lerp(ctrl, u)
	var b = ctrl.lerp(finish, u)
	return a.lerp(b, u)

func vesicle_pos(e: Dictionary) -> Vector2:
	var dest: Vector2 = e.dest
	var u = clampf((e.age - T_REACH - T_WRAP) / e.pull, 0.0, 1.0)
	var from: Vector2 = e.V
	return from.lerp(dest, ease_io(u))

# A little bilayer bubble: two rings of lipid heads.
func draw_vesicle(c: Vector2, alpha: float) -> void:
	draw_circle(c, VESICLE_R, Color(0.95, 0.75, 0.3, 0.10 * alpha))
	for i in 18:
		var a = i * TAU / 18.0
		var d = Vector2(cos(a), sin(a))
		draw_circle(c + d * VESICLE_R, 2.6, Color(0.95, 0.75, 0.3, alpha))
		draw_circle(c + d * (VESICLE_R - 7.0), 2.0, Color(0.95, 0.75, 0.3, 0.7 * alpha))
	draw_arc(c, VESICLE_R - 3.5, 0.0, TAU, 32, Color(0.9, 0.9, 0.7, 0.35 * alpha), 1.0, true)

# An olive-green organelle full of digestive enzymes. Cracks show when it is failing.
func draw_lysosome(c: Vector2, rad: float, alpha: float, stress: float, age: float) -> void:
	var olive = Color(0.55, 0.78, 0.3)
	draw_circle(c, rad, Color(0.3, 0.5, 0.15, 0.28 * alpha))
	draw_circle(c, rad * 0.8, Color(0.4, 0.7, 0.2, 0.12 * alpha))
	var count := 20
	for i in count:
		var a = i * TAU / float(count)
		var d = Vector2(cos(a), sin(a))
		draw_circle(c + d * rad, 2.8, Color(olive.r, olive.g, olive.b, alpha))
		draw_circle(c + d * (rad - 7.0), 2.0, Color(olive.r, olive.g, olive.b, 0.7 * alpha))
	for i in 7:
		var a = age * 2.2 + i * TAU / 7.0
		var r = rad * (0.35 + 0.25 * sin(age * 3.0 + i))
		draw_circle(c + Vector2(cos(a), sin(a)) * r, 1.6, Color(0.85, 1.0, 0.5, 0.9 * alpha))
	if stress > 0.0:
		for i in 5:
			var a = i * TAU / 5.0 + 0.4
			var d = Vector2(cos(a), sin(a))
			var p0 = c + d * (rad - 6.0)
			var p1 = c + d * (rad + 7.0 * stress)
			var mid = (p0 + p1) * 0.5 + d.orthogonal() * 4.0
			draw_polyline(PackedVector2Array([p0, mid, p1]), Color(1.0, 0.3, 0.25, stress), 2.0, true)

func draw_engulf(e: Dictionary) -> void:
	var age: float = e.age
	var head = Color(0.95, 0.75, 0.3)
	var tang: Vector2 = e.n.orthogonal()
	var t1 = T_REACH
	var t2 = T_REACH + T_WRAP
	var t3 = t2 + e.pull
	var t4 = t3 + T_FUSE

	if age < t2:
		# two arms of membrane reach out and then close round the virus
		var p = ease_io(clampf(age / T_REACH, 0.0, 1.0))
		var fade = 1.0
		if age > t1:
			fade = 1.0 - (age - t1) / T_WRAP
		for side in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			for i in 13:
				pts.append(arm_point(e, side, p * float(i) / 12.0))
			draw_polyline(pts, Color(head.r, head.g, head.b, 0.5 * fade), 8.0, true)
			draw_polyline(pts, Color(1.0, 0.9, 0.6, 0.9 * fade), 2.0, true)
			draw_circle(pts[pts.size() - 1], 4.0, Color(head.r, head.g, head.b, fade))
		draw_virus_at(e.V, e.strain, e.spin, 1.0, 1.0)
		if age > t1:
			draw_vesicle(e.V, clampf((age - t1) / T_WRAP, 0.0, 1.0))
		return

	var c = vesicle_pos(e)
	if age < t3:
		# the vesicle pinches off and is carried into the cell
		var u = clampf((age - t2) / e.pull, 0.0, 1.0)
		if u < 0.35:
			var nk = 1.0 - u / 0.35
			var towards: Vector2 = (e.A - c).normalized()
			for side in [-1.0, 1.0]:
				var a0: Vector2 = e.A + tang * side * 8.0
				var a1: Vector2 = c + towards * VESICLE_R + tang * side * 6.0
				draw_line(a0, a1, Color(head.r, head.g, head.b, 0.6 * nk), 3.0, true)
		draw_virus_at(c, e.strain, e.spin, 0.8, 1.0)
		draw_vesicle(c, 1.0)
		return

	if age < t4:
		# the vesicle fuses with a lysosome (one of yours, if you have any)
		var kf = clampf((age - t3) / T_FUSE, 0.0, 1.0)
		draw_virus_at(c, e.strain, e.spin, 0.8, 1.0)
		draw_vesicle(c, 1.0 - kf)
		if e.resident:
			draw_lysosome(c, LYSO_R, 0.45 + 0.55 * kf, 0.0, age)
		else:
			var rad = lerpf(VESICLE_R, LYSO_R, ease_io(kf))
			draw_lysosome(c, rad, kf, 0.0, age)
		return

	# digestion: enzymes break the virus down, unless it is one of the escapers
	var kd = clampf((age - t4) / T_DIGEST, 0.0, 1.0)
	var stress = 0.0
	var shake = Vector2.ZERO
	var sf = 1.0 - kd
	var va = 1.0 - 0.8 * kd
	var ly_alpha = 1.0 - maxf(0.0, (kd - 0.8) / 0.2)
	if e.breaks:
		stress = clampf((kd - 0.45) / 0.55, 0.0, 1.0)
		shake = Vector2(sin(age * 70.0), cos(age * 61.0)) * 3.0 * stress
		sf = lerpf(1.0 - minf(kd, 0.45), 1.0, stress)
		va = lerpf(1.0 - 0.8 * minf(kd, 0.45), 1.0, stress)
		ly_alpha = 1.0
	var cc = c + shake
	draw_virus_at(cc, e.strain, e.spin * (1.0 + 2.0 * stress), 0.8 * sf, va)
	draw_lysosome(cc, LYSO_R, ly_alpha, stress, age)
	draw_string(ThemeDB.fallback_font, cc + Vector2(-30, -LYSO_R - 8.0), "Lysosome", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(0.8, 1.0, 0.6, 0.85 * ly_alpha))

func _draw() -> void:
	for ix in infections:
		draw_infection(ix)
	for v in viruses:
		draw_virus(v)
	for e in engulfs:
		draw_engulf(e)
	for fx in effects:
		var life: float = fx.get("life", 0.45)
		var k = fx.t / life
		var col: Color = fx.color
		col.a = 1.0 - k
		if fx.has("text"):
			draw_string(ThemeDB.fallback_font, fx.pos + Vector2(-26, -8.0 - 30.0 * k), fx.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		else:
			var r = 6.0 + 24.0 * k
			if fx.has("big"):
				r = 10.0 + 70.0 * k
			draw_arc(fx.pos, r, 0.0, TAU, 32, col, 2.5, true)
