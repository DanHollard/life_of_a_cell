extends Node2D

const SIZE := 130.0          # minimap size on screen
const ARENA := 600.0         # size of the extracellular world
const RES := 32              # resolution of the zone picture
const DRIFT_SPEED := 5.0     # how fast the current carries the cell (units/sec)
const WANDER := 3.0          # random jostling
const ADVECT := Vector2(3.0, 1.0)   # how fast the zones are carried across the arena

var time := 0.0
var cell := Vector2(300, 300)
var vel := Vector2.ZERO
var exposure := 0.0
var trail: Array = []
var trail_timer := 0.0
var tex_timer := 0.0

var target := Vector2.ZERO
var has_target := false
var swimming := false

var nutrient_noise: FastNoiseLite
var toxin_noise: FastNoiseLite
var flow_x: FastNoiseLite
var flow_y: FastNoiseLite
var img: Image
var tex: ImageTexture
var nucleus
var recharge_button := Button.new()

func make_noise(freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 2
	n.seed = randi() % 100000
	return n

func _ready() -> void:
	nucleus = get_parent().get_node_or_null("Nucleus")
	nutrient_noise = make_noise(0.009)
	toxin_noise = make_noise(0.009)
	flow_x = make_noise(0.004)
	flow_y = make_noise(0.004)
	img = Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	tex = ImageTexture.create_from_image(img)

	# the recharge button lives under the map
	var hud := CanvasLayer.new()
	add_child(hud)
	var screen = get_viewport_rect().size
	recharge_button.position = Vector2(screen.x - SIZE - 12.0, 12.0 + SIZE + 54.0)
	recharge_button.custom_minimum_size = Vector2(SIZE, 0)
	recharge_button.focus_mode = Control.FOCUS_NONE
	recharge_button.add_theme_font_size_override("font_size", 12)
	recharge_button.pressed.connect(Game.recharge)
	hud.add_child(recharge_button)

	# start somewhere safe and fairly pleasant
	var best = Vector2(300, 300)
	var best_score = -10.0
	for i in 150:
		var p = Vector2(randf_range(60.0, ARENA - 60.0), randf_range(60.0, ARENA - 60.0))
		var score = (1.0 - field(toxin_noise, p)) - absf(field(nutrient_noise, p) - 0.5)
		if score > best_score:
			best_score = score
			best = p
	cell = best
	refresh_texture()

func overlay_open() -> bool:
	return nucleus != null and nucleus.layer != null and nucleus.layer.visible

# A smooth value from 0 to 1 at a point in the arena, carried along by the current.
func field(noise: FastNoiseLite, p: Vector2) -> float:
	var v = noise.get_noise_3d(p.x - time * ADVECT.x, p.y - time * ADVECT.y, time * 0.01)
	return clampf(0.5 + 0.7 * v, 0.0, 1.0)

func zone_color(n: float, tx: float) -> Color:
	var c = Color(0.07, 0.12, 0.2)
	var rich = clampf((n - 0.5) / 0.3, 0.0, 1.0)
	c = c.lerp(Color(0.15, 0.6, 0.4), rich * 0.85)
	var toxic = clampf((tx - 0.55) / 0.2, 0.0, 1.0)
	c = c.lerp(Color(0.7, 0.15, 0.55), toxic * 0.9)
	return c

func refresh_texture() -> void:
	for y in RES:
		for x in RES:
			var p = Vector2((x + 0.5) / RES * ARENA, (y + 0.5) / RES * ARENA)
			img.set_pixel(x, y, zone_color(field(nutrient_noise, p), field(toxin_noise, p)))
	tex.update(img)

# Click the map to set a course, right-click to clear it.
func _input(event: InputEvent) -> void:
	if Game.swim_speed <= 0.0 or overlay_open():
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var screen = get_viewport_rect().size
	var pos = Vector2(screen.x - SIZE - 12.0, 12.0)
	var rect = Rect2(pos, Vector2(SIZE, SIZE))
	if not rect.has_point(event.position):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		target = (event.position - pos) / SIZE * ARENA
		has_target = true
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		has_target = false
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	time += delta

	# drift: the current carries the cell, with a little random jostling
	var current = Vector2(
		flow_x.get_noise_3d(cell.x, cell.y, time * 0.01),
		flow_y.get_noise_3d(cell.x, cell.y, time * 0.01))
	vel = vel.lerp(current * DRIFT_SPEED * 2.0, minf(1.0, delta * 0.6))
	vel += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * WANDER * delta
	cell += vel * delta

	# swimming: hold Shift to head for the course you set
	swimming = false
	if has_target:
		var to_t = target - cell
		if to_t.length() < 4.0:
			has_target = false
		elif Game.swim_speed > 0.0 and Game.boost > 0.0 and Input.is_key_pressed(KEY_SHIFT) and not overlay_open():
			swimming = true
			cell += to_t.normalized() * Game.swim_speed * delta
			Game.boost = maxf(0.0, Game.boost - Game.swim_drain * delta)

	if cell.x < 15.0:
		cell.x = 15.0
		vel.x = absf(vel.x)
	if cell.x > ARENA - 15.0:
		cell.x = ARENA - 15.0
		vel.x = -absf(vel.x)
	if cell.y < 15.0:
		cell.y = 15.0
		vel.y = absf(vel.y)
	if cell.y > ARENA - 15.0:
		cell.y = ARENA - 15.0
		vel.y = -absf(vel.y)

	# what the cell feels where it is
	var n = field(nutrient_noise, cell)
	var tx = field(toxin_noise, cell)
	Game.env_mult = lerpf(0.5, 2.0, clampf((n - 0.3) / 0.4, 0.0, 1.0))
	var target_exposure = clampf((tx - 0.55) / 0.25, 0.0, 1.0)
	exposure = lerpf(exposure, target_exposure, minf(1.0, delta * 0.6))
	Game.toxin_level = exposure

	tex_timer += delta
	if tex_timer >= 0.5:
		tex_timer = 0.0
		refresh_texture()

	trail_timer += delta
	if trail_timer >= 0.8:
		trail_timer = 0.0
		trail.append(cell)
		if trail.size() > 50:
			trail.pop_front()

	recharge_button.visible = Game.swim_speed > 0.0
	recharge_button.text = "Recharge (%d ATP)" % Game.recharge_cost()
	recharge_button.disabled = Game.boost >= Game.boost_max or Game.stock.atp <= 0

	queue_redraw()

func _draw() -> void:
	var screen = get_viewport_rect().size
	var pos = Vector2(screen.x - SIZE - 12.0, 12.0)
	var rect = Rect2(pos, Vector2(SIZE, SIZE))
	var k = SIZE / ARENA
	var font = ThemeDB.fallback_font

	draw_rect(rect.grow(3.0), Color(0.02, 0.03, 0.05, 0.85))
	draw_texture_rect(tex, rect, false)
	draw_rect(rect, Color(1, 1, 1, 0.35), false, 1.5)

	# where the cell has been
	for i in range(1, trail.size()):
		var a = float(i) / float(trail.size())
		draw_line(pos + trail[i - 1] * k, pos + trail[i] * k, Color(1, 1, 1, 0.45 * a), 1.0)

	var c = pos + cell * k

	# the course you have set
	if has_target:
		var tp = pos + target * k
		draw_line(c, tp, Color(1, 1, 1, 0.35), 1.0)
		draw_arc(tp, 4.5, 0.0, TAU, 16, Color(1.0, 0.9, 0.4), 1.5, true)
		draw_line(tp + Vector2(-3, -3), tp + Vector2(3, 3), Color(1.0, 0.9, 0.4), 1.5)
		draw_line(tp + Vector2(-3, 3), tp + Vector2(3, -3), Color(1.0, 0.9, 0.4), 1.5)

	# the cell
	draw_circle(c, 3.5, Color(1, 1, 1))
	draw_arc(c, 6.0 + 1.5 * sin(time * 3.0), 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.0, true)
	if swimming:
		draw_arc(c, 9.0 + 2.0 * sin(time * 20.0), 0.0, TAU, 20, Color(0.6, 0.9, 1.0, 0.9), 1.5, true)

	# nutrient readout
	var text = "Nutrients x%.1f" % Game.env_mult
	draw_string(font, pos + Vector2(5, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.8))
	draw_string(font, pos + Vector2(4, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.95))

	# toxin gauge along the bottom of the map
	var bar = Rect2(pos + Vector2(4, SIZE - 12), Vector2(SIZE - 8, 7))
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var fill = Rect2(bar.position, Vector2(bar.size.x * Game.toxin_level, bar.size.y))
	var fill_color = Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.25, 0.3), Game.toxin_level)
	draw_rect(fill, fill_color)
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 1.0)
	draw_string(font, pos + Vector2(5, SIZE - 15), "Toxins", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.9))

	# swim charge, once you can swim
	if Game.swim_speed > 0.0:
		var sb = Rect2(pos + Vector2(0, SIZE + 8.0), Vector2(SIZE, 8.0))
		draw_rect(sb, Color(0, 0, 0, 0.6))
		var frac = Game.boost / Game.boost_max
		var sc = Color(0.4, 0.8, 1.0)
		if frac < 0.25:
			sc = Color(1.0, 0.45, 0.35)
		draw_rect(Rect2(sb.position, Vector2(sb.size.x * frac, sb.size.y)), sc)
		draw_rect(sb, Color(1, 1, 1, 0.5), false, 1.0)
		draw_string(font, pos + Vector2(0, SIZE + 30.0), "Click map: set course", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
		draw_string(font, pos + Vector2(0, SIZE + 42.0), "Hold SHIFT: swim", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
