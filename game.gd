extends Node

signal changed
signal channels_changed
signal converted
signal died
signal divided

const BASE_LEAK := 0.2      # molecules/sec of each type leaking through the plain membrane
const PER_CHANNEL := 0.5    # molecules/sec added by each channel of that type
const CONVERT_RATE := 0.5   # carbs/sec converted by each mitochondrion
const CARB_RESERVE := 5     # mitochondria leave this many carbs for gene costs
const BASE_ENGULF := 18.0   # click reach in pixels
const ENZYME_RATE := 1.0    # glucose drops each synthase enzyme processes per second
const QUEUE_MAX := 8        # drops that can wait at the enzyme station
const DIVIDE_COST := {"carb": 5, "lipid": 15, "amino": 15, "atp": 20}
const REPLICATE_TIME := 20.0   # seconds it takes to copy the genome
const VULN_MULT := 1.5         # toxin damage multiplier while copying
const TYPES := ["carb", "lipid", "amino"]
const NAMES := {"carb": "Sugar", "lipid": "Lipid", "amino": "Amino acid"}

var stock = {"carb": 0, "lipid": 0, "amino": 0, "atp": 0}
var carb_cap := 20:
	set(value):
		carb_cap = maxi(8, value)
var enzymes := 1
var station_queue := 0
var channel_count = {"carb": 0, "lipid": 0, "amino": 0}
var channel_list: Array = []   # each entry: {"type", "frac", "timer"}
var unlocked: Dictionary = {}

var mitochondria := 0
var mito_timer := 0.0
var convert_mult := 1.0     # mutations speed up or slow down the mitochondria
var atp_yield := 3          # ATP made from each carb
var atp_upkeep := 0.0       # ATP lost per second just to keep the cell running
var upkeep_acc := 0.0

var engulf_mult := 1.0
var auto_engulf := false

# Swimming (set by the flagellum or cilia gene)
var swim_speed := 0.0       # map units per second; 0 until a gene is expressed
var swim_drain := 0.0       # charge used per second of swimming
var boost := 0.0
var boost_max := 100.0
var atp_per_charge := 0.5   # ATP needed per point of charge

# Intake is boosted by genes and by the environment the cell is drifting through.
var gene_mult := 1.0
var env_mult := 1.0
var toxin_level := 0.0      # 0 to 1, set by the minimap
var integrity := 100.0      # membrane health, 0 to 100
var tox_resist := 0.0:      # fraction of toxin damage blocked (negative = takes extra)
	set(value):
		tox_resist = clampf(value, -1.0, 0.85)
var intake_mult: float:
	get:
		return gene_mult * env_mult * integrity_factor()

# Run state
var dead := false
var run_time := 0.0
var best_time := 0.0        # best run this session (not reset)
var replicating := false
var replicate_progress := 0.0

# Mutations picked this run
var mutations: Array = []
var synergies: Dictionary = {}
var hgt := false            # horizontal gene transfer: rival genes no longer lock each other out

# Kept between runs
var generation := 1
var inherited: Array = []   # gene ids passed down to each new run

func integrity_factor() -> float:
	if integrity >= 60.0:
		return 1.0
	return lerpf(0.2, 1.0, integrity / 60.0)

var weights = {"carb": 1.0, "lipid": 1.0, "amino": 1.0}
var channel_discount := 0.0:
	set(value):
		channel_discount = clampf(value, -0.9, 0.8)

const GENES = {
	"transporters": {"name": "Transporter proteins", "effect": "+25% intake",
		"cost": {"amino": 4}, "needs": [], "pos": Vector2(0, 1)},
	"glucose": {"name": "Glucose transporters", "effect": "Carbs arrive 2x as often",
		"cost": {"amino": 6, "carb": 4}, "needs": ["transporters"], "pos": Vector2(1, 0)},
	"permease": {"name": "Amino acid permeases", "effect": "Amino acids arrive 2x",
		"cost": {"amino": 6, "carb": 4}, "needs": ["transporters"], "pos": Vector2(1, 1)},
	"scavenge": {"name": "Lipid scavenging", "effect": "Lipids arrive 2x as often",
		"cost": {"amino": 6, "carb": 4}, "needs": ["transporters"], "pos": Vector2(1, 2)},
	"mitochondrion": {"name": "Mitochondrion", "effect": "Converts carbs to ATP",
		"cost": {"amino": 8, "lipid": 5}, "needs": ["glucose"], "pos": Vector2(2, 0)},
	"efficient": {"name": "Efficient channels", "effect": "Channels cost 30% less",
		"cost": {"amino": 10, "lipid": 6, "atp": 8}, "needs": ["glucose", "permease"], "pos": Vector2(2, 1)},
	"duplication": {"name": "Gene duplication", "effect": "+50% intake",
		"cost": {"amino": 15, "lipid": 10, "atp": 20}, "needs": ["permease", "scavenge"], "pos": Vector2(2, 2)},
	"pseudopods": {"name": "Pseudopods", "effect": "Click reach 2.5x",
		"cost": {"amino": 3}, "needs": [], "pos": Vector2(0, 3)},
	"phagocytosis": {"name": "Phagocytosis", "effect": "Auto-engulfs nearby molecules",
		"cost": {"amino": 8, "lipid": 5}, "needs": ["pseudopods"], "pos": Vector2(1, 3)},
	"synthase": {"name": "Glycogen synthase", "effect": "+1 enzyme: stores carbs faster",
		"cost": {"amino": 6, "lipid": 3}, "needs": [], "pos": Vector2(2, 3)},
	"branching": {"name": "Branching enzyme", "effect": "Carb storage +20",
		"cost": {"amino": 6, "lipid": 3}, "needs": ["synthase"], "pos": Vector2(3, 3)},
	"flagellum": {"name": "Flagellum", "effect": "Fast swim, no cilia",
		"cost": {"amino": 12, "lipid": 8, "atp": 25}, "needs": ["mitochondrion"],
		"excludes": ["cilia"], "pos": Vector2(3, 0)},
	"cilia": {"name": "Cilia", "effect": "Cheap swim, no flagellum",
		"cost": {"amino": 10, "lipid": 6, "atp": 15}, "needs": ["mitochondrion"],
		"excludes": ["flagellum"], "pos": Vector2(3, 1)},
}

func _process(delta: float) -> void:
	if not dead:
		run_time += delta

	# keeping the cell running costs ATP
	if atp_upkeep > 0.0 and not dead:
		upkeep_acc += atp_upkeep * delta
		while upkeep_acc >= 1.0:
			upkeep_acc -= 1.0
			if stock.atp > 0:
				stock.atp -= 1

	# copying the genome before dividing
	if replicating and not dead:
		replicate_progress += delta / REPLICATE_TIME
		if replicate_progress >= 1.0:
			replicate_progress = 1.0
			replicating = false
			best_time = maxf(best_time, run_time)
			divided.emit()

	if mitochondria <= 0:
		return
	mito_timer += delta
	var interval = 1.0 / (CONVERT_RATE * convert_mult * mitochondria)
	while mito_timer >= interval and stock.carb > CARB_RESERVE:
		mito_timer -= interval
		stock.carb -= 1
		stock.atp += atp_yield
		converted.emit()
		changed.emit()
	if stock.carb <= CARB_RESERVE:
		mito_timer = 0.0

func can_divide() -> bool:
	return not dead and not replicating and can_afford(DIVIDE_COST)

func begin_division() -> void:
	if not can_divide():
		return
	for k in DIVIDE_COST:
		stock[k] -= DIVIDE_COST[k]
	replicating = true
	replicate_progress = 0.0
	changed.emit()
	Sfx.play("open", 0.8)

# Pass a gene (and the genes it depends on) down to future runs.
func inherit(id: String) -> void:
	if GENES[id].has("excludes"):
		for other in GENES[id].excludes:
			inherited.erase(other)
	if not inherited.has(id):
		inherited.append(id)
	for need in GENES[id].needs:
		inherit(need)

# Puts everything back to how a fresh run starts, then applies inherited genes.
func reset() -> void:
	stock = {"carb": 0, "lipid": 0, "amino": 0, "atp": 0}
	carb_cap = 20
	enzymes = 1
	station_queue = 0
	channel_count = {"carb": 0, "lipid": 0, "amino": 0}
	channel_list = []
	unlocked = {}
	mitochondria = 0
	mito_timer = 0.0
	convert_mult = 1.0
	atp_yield = 3
	atp_upkeep = 0.0
	upkeep_acc = 0.0
	engulf_mult = 1.0
	auto_engulf = false
	swim_speed = 0.0
	swim_drain = 0.0
	boost = 0.0
	atp_per_charge = 0.5
	gene_mult = 1.0
	env_mult = 1.0
	toxin_level = 0.0
	integrity = 100.0
	tox_resist = 0.0
	weights = {"carb": 1.0, "lipid": 1.0, "amino": 1.0}
	channel_discount = 0.0
	mutations = []
	synergies = {}
	hgt = false
	run_time = 0.0
	dead = false
	replicating = false
	replicate_progress = 0.0
	for id in inherited:
		unlocked[id] = true
		apply_effect(id)

# Hurts the membrane. If it gives way, the run is over.
func damage(amount: float) -> void:
	if dead:
		return
	var dmg = amount
	if replicating:
		dmg = amount * VULN_MULT
	integrity = maxf(0.0, integrity - dmg)
	if integrity <= 0.0:
		die()

func die() -> void:
	if dead:
		return
	dead = true
	replicating = false
	best_time = maxf(best_time, run_time)
	died.emit()

func engulf_radius() -> float:
	return BASE_ENGULF * engulf_mult

# Returns false if the stockpile for this type is full and the molecule is lost.
func add(type: String, amount: int = 1) -> bool:
	if type == "carb" and stock.carb >= carb_cap:
		Sfx.play("overflow", 1.0, 0.15)
		return false
	stock[type] += amount
	changed.emit()
	return true

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if stock[k] < cost[k]:
			return false
	return true

# A gene is available when its prerequisites are expressed and none of its rivals are.
func prereqs_met(id: String) -> bool:
	for need in GENES[id].needs:
		if not unlocked.has(need):
			return false
	if not hgt and GENES[id].has("excludes"):
		for other in GENES[id].excludes:
			if unlocked.has(other):
				return false
	return true

func unlock(id: String) -> void:
	if unlocked.has(id) or not prereqs_met(id) or not can_afford(GENES[id].cost):
		return
	for k in GENES[id].cost:
		stock[k] -= GENES[id].cost[k]
	unlocked[id] = true
	apply_effect(id)
	changed.emit()

func lesser(current: float, new_value: float) -> float:
	if current <= 0.0:
		return new_value
	return minf(current, new_value)

# What a gene actually does (also used for free when a gene is inherited).
func apply_effect(id: String) -> void:
	match id:
		"transporters": gene_mult *= 1.25
		"glucose": weights.carb *= 2.0
		"permease": weights.amino *= 2.0
		"scavenge": weights.lipid *= 2.0
		"mitochondrion": mitochondria = 1
		"efficient": channel_discount += 0.3
		"duplication": gene_mult *= 1.5
		"pseudopods": engulf_mult = 2.5
		"phagocytosis": auto_engulf = true
		"synthase": enzymes += 1
		"branching": carb_cap += 20
		"flagellum":
			swim_speed = maxf(swim_speed, 45.0)
			swim_drain = lesser(swim_drain, 25.0)
			atp_per_charge = minf(atp_per_charge, 0.5)
			boost = boost_max
		"cilia":
			swim_speed = maxf(swim_speed, 18.0)
			swim_drain = lesser(swim_drain, 14.0)
			atp_per_charge = minf(atp_per_charge, 0.25)
			boost = boost_max

# ATP needed to top the boost bar right up.
func recharge_cost() -> int:
	return int(ceil((boost_max - boost) * atp_per_charge))

# Turns ATP into swim charge, as much as you can afford.
func recharge() -> void:
	var missing = boost_max - boost
	if missing <= 0.0 or stock.atp <= 0:
		return
	var gain = minf(missing, float(stock.atp) / atp_per_charge)
	stock.atp -= int(ceil(gain * atp_per_charge))
	boost += gain
	changed.emit()
	Sfx.play("build", 1.3)

func mito_cost() -> Dictionary:
	return {"amino": 6, "lipid": 4 + 3 * (mitochondria - 1)}

func build_mitochondrion() -> void:
	if mitochondria < 1:
		return
	var cost = mito_cost()
	if not can_afford(cost):
		return
	for k in cost:
		stock[k] -= cost[k]
	mitochondria += 1
	changed.emit()

func total_channels() -> int:
	return channel_list.size()

func channel_cost(type: String) -> int:
	return int(round((3 + channel_count[type] * 2) * (1.0 - channel_discount)))

func type_rate(type: String) -> float:
	return (BASE_LEAK + channel_count[type] * PER_CHANNEL) * intake_mult * weights[type]

func intake_rate() -> float:
	var total := 0.0
	for k in TYPES:
		total += type_rate(k)
	return total

func build_channel(type: String) -> void:
	var c = channel_cost(type)
	if stock.amino < c:
		return
	stock.amino -= c
	var n = channel_list.size()
	channel_list.append({"type": type, "frac": fmod(0.05 + n * 0.618034, 1.0), "timer": 0.0})
	channel_count[type] += 1
	channels_changed.emit()
	changed.emit()

func random_type() -> String:
	var total = 0.0
	for k in weights:
		total += weights[k]
	var roll = randf() * total
	for k in weights:
		roll -= weights[k]
		if roll <= 0.0:
			return k
	return "carb"
