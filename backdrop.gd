extends Node2D

const LYSO_R := 28.0

# where each organelle sits, relative to the middle of the cell
const DROPLET_POS = Vector2(325, 105)
const RER_POS = Vector2(310, -95)
const GOLGI_POS = Vector2(-70, -165)
const VACUOLE_POS = Vector2(-235, -120)
const PEROX_POS = Vector2(-20, 150)
const LYSO_SLOTS = [Vector2(170, 140), Vector2(-125, 150), Vector2(-390, -120)]
const DROPLETS = [Vector2(0, 0), Vector2(34, -18), Vector2(-30, -22), Vector2(20, 30), Vector2(-26, 26), Vector2(58, 14)]
const DROPLET_R = [16.0, 11.0, 13.0, 9.0, 12.0, 8.0]
const PEROX = [Vector2(0, 0), Vector2(26, 10), Vector2(-24, 12), Vector2(8, -22)]
const FLAGELLUM_FRAC := 0.394

var membrane
var nucleus
var t := 0.0
var born := {}        # organelle key -> time it appeared
var rings: Array = []

func _ready() -> void:
	membrane = get_parent().get_node_or_null("Membrane")
	nucleus = get_parent().get_node_or_null("Nucleus")

func cell_center() -> Vector2:
	var q = membrane.params()
	return Vector2((q.x0 + q.x1) * 0.5, (q.y0 + q.y1) * 0.5)

func nucleus_pos() -> Vector2:
	if nucleus != null:
		return nucleus.global_position
	return cell_center()

# Which upgrades summon which organelle.
func wanted() -> Dictionary:
	var w := {}
	var u = Game.unlocked
	var m = Game.mutations
	if u.has("scavenge"):
		w["droplets"] = true
	if u.has("permease"):
		w["rer"] = true
	if u.has("efficient"):
		w["golgi"] = true
	if u.has("pseudopods"):
		w["cytoskeleton"] = true
	if u.has("phagocytosis"):
		w["lysosomes"] = true
	if u.has("branching") or m.has("bloat") or m.has("packrat"):
		w["vacuole"] = true
	if m.has("shell") or m.has("efflux"):
		w["peroxisomes"] = true
	if u.has("flagellum"):
		w["flagellum"] = true
	if u.has("cilia"):
		w["cilia"] = true
	return w

func anchor(key: String) -> Vector2:
	var c = cell_center()
	match key:
		"droplets": return c + DROPLET_POS
		"rer": return c + RER_POS
		"golgi": return c + GOLGI_POS
		"vacuole": return c + VACUOLE_POS
		"peroxisomes": return c + PEROX_POS
		"lysosomes": return c + LYSO_SLOTS[0]
		"cytoskeleton": return nucleus_pos()
		"flagellum": return membrane.border_point(FLAGELLUM_FRAC)[0]
		"cilia": return membrane.border_point(0.64)[0]
	return c

# 0 when the organelle hasn't appeared, easing up to 1 as it forms.
func grow(key: String) -> float:
	if not born.has(key):
		return 0.0
	var u = clampf((t - born[key]) / 1.8, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

func lyso_grow(i: int) -> float:
	if not born.has("lysosomes"):
		return 0.0
	var u = clampf((t - born["lysosomes"] - i * 0.45) / 1.4, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

# Used by the Viruses script: where the formed lysosomes are.
func lysosome_positions() -> Array:
	var out: Array = []
	if membrane == null or not born.has("lysosomes"):
		return out
	var c = cell_center()
	for i in LYSO_SLOTS.size():
		if lyso_grow(i) > 0.9:
			out.append(c + LYSO_SLOTS[i])
	return out

func _process(delta: float) -> void:
	t += delta
	if membrane == null:
		return

	var w = wanted()
	for key in w:
		if not born.has(key):
			born[key] = t
			rings.append({"pos": anchor(key), "t": 0.0})

	var live: Array = []
	for r in rings:
		r.t += delta
		if r.t < 1.1:
			live.append(r)
	rings = live
	queue_redraw()

# ---------- drawing ----------

func draw_cytoskeleton(center: Vector2, g: float) -> void:
	for i in 18:
		var a = i * TAU / 18.0 + 0.15 * sin(i * 1.7)
		var dir = Vector2(cos(a), sin(a))
		var side = dir.orthogonal()
		var length = 170.0 + 40.0 * sin(i * 2.3)
		var bend = 22.0 * sin(i * 1.3 + t * 0.3)
		var pts := PackedVector2Array()
		for k in 9:
			var u = float(k) / 8.0
			pts.append(center + dir * (80.0 + length * u * g) + side * bend * sin(u * PI))
		draw_polyline(pts, Color(0.75, 0.85, 1.0, 0.14 * g), 1.4, true)

func draw_vacuole(base: Vector2, g: float) -> void:
	var r = 46.0 * (0.5 + 0.5 * g)
	var a = 0.3 * g
	draw_circle(base, r, Color(0.55, 0.75, 0.9, a * 0.45))
	draw_arc(base, r, 0.0, TAU, 40, Color(0.7, 0.88, 1.0, a * 1.6), 2.0, true)
	draw_arc(base, r * 0.72, -0.5, 1.2, 16, Color(1, 1, 1, a), 1.5, true)
	for i in 4:
		var ang = t * 0.2 + i * 1.6
		draw_circle(base + Vector2(cos(ang), sin(ang)) * r * 0.45, 2.2, Color(0.8, 0.95, 1.0, a * 1.4))

func draw_rer(base: Vector2, g: float) -> void:
	var a = 0.4 * g
	for s in 3:
		var pts := PackedVector2Array()
		for i in 21:
			var x = (-66.0 + i * 6.6) * g
			var y = sin(i * 0.45 + s * 1.2 + t * 0.4) * 7.0 + s * 15.0 - 15.0
			pts.append(base + Vector2(x, y))
		draw_polyline(pts, Color(0.55, 0.65, 0.95, a), 5.0, true)
		for i in 21:
			if i % 2 == 0:
				var p = pts[i]
				draw_circle(p + Vector2(0, -4.5), 1.5, Color(0.9, 0.93, 1.0, a * 1.3))
				draw_circle(p + Vector2(0, 4.5), 1.5, Color(0.9, 0.93, 1.0, a * 1.3))

func draw_golgi(base: Vector2, g: float) -> void:
	var a = 0.42 * g
	var origin = base + Vector2(0, 60)
	for k in 5:
		var r = (38.0 + k * 9.0) * g
		draw_arc(origin, r, -PI * 0.78, -PI * 0.22, 24, Color(0.95, 0.6, 0.8, a * (0.6 + 0.08 * k)), 5.0 - 0.3 * k, true)
	for i in 3:
		var ang_r = -PI * 0.2 + sin(t * 0.8 + i * 2.0) * 0.12 - i * 0.1
		var ang_l = -PI + (PI * 0.2) - sin(t * 0.7 + i * 1.7) * 0.12 + i * 0.1
		var dist = (92.0 + i * 8.0) * g
		draw_circle(origin + Vector2(cos(ang_r), sin(ang_r)) * dist, 3.2, Color(0.98, 0.75, 0.88, a * 1.2))
		draw_circle(origin + Vector2(cos(ang_l), sin(ang_l)) * dist, 3.2, Color(0.98, 0.75, 0.88, a * 1.2))

func draw_droplets(base: Vector2, g: float) -> void:
	var a = 0.42 * g
	for i in DROPLETS.size():
		var p = base + DROPLETS[i] + Vector2(sin(t * 0.5 + i), cos(t * 0.4 + i * 1.3)) * 2.0
		var r = DROPLET_R[i] * (0.4 + 0.6 * g)
		draw_circle(p, r, Color(0.95, 0.8, 0.35, a))
		draw_arc(p, r, 0.0, TAU, 20, Color(1.0, 0.9, 0.55, minf(1.0, a * 1.2)), 1.2, true)
		draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1.0, 1.0, 0.85, minf(1.0, a * 1.4)))

func draw_peroxisomes(base: Vector2, g: float) -> void:
	var a = 0.45 * g
	for i in PEROX.size():
		var p = base + PEROX[i] + Vector2(sin(t * 0.6 + i * 2.0), cos(t * 0.5 + i)) * 2.0
		var r = 8.0 * (0.4 + 0.6 * g)
		draw_circle(p, r, Color(0.55, 0.42, 0.3, a))
		draw_arc(p, r, 0.0, TAU, 16, Color(0.8, 0.65, 0.45, a), 1.2, true)
		draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.2, 0.14, 0.1, minf(1.0, a * 1.6)))

func draw_lysosome_bg(p: Vector2, g: float, idx: int) -> void:
	if g <= 0.0:
		return
	var rad = LYSO_R * (0.5 + 0.5 * g)
	var a = 0.42 * g
	var olive = Color(0.55, 0.78, 0.3)
	draw_circle(p, rad, Color(0.3, 0.5, 0.15, a * 0.7))
	for i in 18:
		var ang = i * TAU / 18.0
		var d = Vector2(cos(ang), sin(ang))
		draw_circle(p + d * rad, 2.4, Color(olive.r, olive.g, olive.b, a))
		draw_circle(p + d * (rad - 6.0), 1.7, Color(olive.r, olive.g, olive.b, a * 0.7))
	for i in 5:
		var ang2 = t * 0.9 + idx + i * TAU / 5.0
		var rr = rad * (0.3 + 0.2 * sin(t * 1.4 + i))
		draw_circle(p + Vector2(cos(ang2), sin(ang2)) * rr, 1.4, Color(0.85, 1.0, 0.5, minf(1.0, a * 1.2)))

func draw_flagellum(g: float) -> void:
	var bp = membrane.border_point(FLAGELLUM_FRAC)
	var pt: Vector2 = bp[0]
	var n: Vector2 = bp[1]
	var tang = n.orthogonal()
	var a = 0.55 * g
	var base = pt + n * 14.0
	var pts := PackedVector2Array()
	for i in 21:
		var d = i * 2.0 * g
		var amp = 7.0 * float(i) / 20.0
		pts.append(base + n * d + tang * sin(d * 0.2 - t * 8.0) * amp)
	draw_polyline(pts, Color(0.85, 0.92, 0.75, a), 3.0, true)
	draw_circle(base, 3.5, Color(0.9, 0.95, 0.8, a))

func draw_cilia(g: float) -> void:
	var a = 0.55 * g
	var f = 0.56
	var k = 0
	while f < 0.72:
		var bp = membrane.border_point(f)
		var n: Vector2 = bp[1]
		var tang = n.orthogonal()
		var start: Vector2 = bp[0] + n * 14.0
		var sway = sin(t * 5.0 + k * 0.8)
		var mid = start + n * 8.0 * g + tang * sway * 1.5
		var tip = start + n * 15.0 * g + tang * sway * 4.0
		draw_polyline(PackedVector2Array([start, mid, tip]), Color(0.85, 0.95, 0.85, a), 1.6, true)
		f += 0.0055
		k += 1

# While the genome is copied, spindle fibres form round the nucleus.
func draw_spindle(center: Vector2) -> void:
	var p = Game.replicate_progress
	var a = 0.5 * minf(1.0, p * 4.0)
	var pole_a = center + Vector2(0, -105)
	var pole_b = center + Vector2(0, 105)
	for i in 11:
		var bulge = (i - 5) * 20.0
		var pts := PackedVector2Array()
		for k in 15:
			var u = float(k) / 14.0
			pts.append(pole_a.lerp(pole_b, u) + Vector2(bulge * sin(u * PI), 0.0))
		draw_polyline(pts, Color(0.85, 0.95, 1.0, a * 0.55), 1.3, true)
	for pole in [pole_a, pole_b]:
		draw_circle(pole, 5.0, Color(1.0, 0.9, 0.5, a))
		for i in 8:
			var ang = i * TAU / 8.0 + t * 0.5
			draw_line(pole, pole + Vector2(cos(ang), sin(ang)) * 14.0, Color(1.0, 0.9, 0.5, a * 0.6), 1.2)

func _draw() -> void:
	if membrane == null:
		return
	var c = cell_center()
	if born.has("cytoskeleton"):
		draw_cytoskeleton(nucleus_pos(), grow("cytoskeleton"))
	if born.has("vacuole"):
		draw_vacuole(c + VACUOLE_POS, grow("vacuole"))
	if born.has("rer"):
		draw_rer(c + RER_POS, grow("rer"))
	if born.has("golgi"):
		draw_golgi(c + GOLGI_POS, grow("golgi"))
	if born.has("droplets"):
		draw_droplets(c + DROPLET_POS, grow("droplets"))
	if born.has("peroxisomes"):
		draw_peroxisomes(c + PEROX_POS, grow("peroxisomes"))
	if born.has("lysosomes"):
		for i in LYSO_SLOTS.size():
			draw_lysosome_bg(c + LYSO_SLOTS[i], lyso_grow(i), i)
	if born.has("flagellum"):
		draw_flagellum(grow("flagellum"))
	if born.has("cilia"):
		draw_cilia(grow("cilia"))
	if Game.replicating:
		draw_spindle(nucleus_pos())
	for r in rings:
		var k = r.t / 1.1
		draw_arc(r.pos, 10.0 + 80.0 * k, 0.0, TAU, 40, Color(1, 1, 1, 0.45 * (1.0 - k)), 2.0, true)
