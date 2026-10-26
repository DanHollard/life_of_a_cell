extends Node

signal changed
signal channels_changed

const BASE_LEAK := 0.2      # molecules/sec of each type leaking through the plain membrane
const PER_CHANNEL := 0.5    # molecules/sec added by each channel of that type
const CONVERT_RATE := 0.5   # carbs/sec converted by each mitochondrion
const ATP_PER_CARB := 3
const CARB_RESERVE := 5     # mitochondria leave this many carbs for gene costs
const TYPES := ["carb", "lipid", "amino"]
const NAMES := {"carb": "Sugar", "lipid": "Lipid", "amino": "Amino acid"}

var stock = {"carb": 0, "lipid": 0, "amino": 0, "atp": 0}
var channel_count = {"carb": 0, "lipid": 0, "amino": 0}
var channel_list: Array = []   # each entry: {"type", "frac", "timer"}
var unlocked: Dictionary = {}

var mitochondria := 0
var mito_timer := 0.0

var intake_mult := 1.0
var weights = {"carb": 1.0, "lipid": 1.0, "amino": 1.0}
var channel_discount := 0.0

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
}

func _process(delta: float) -> void:
	if mitochondria <= 0:
		return
	mito_timer += delta
	var interval = 1.0 / (CONVERT_RATE * mitochondria)
	while mito_timer >= interval and stock.carb > CARB_RESERVE:
		mito_timer -= interval
		stock.carb -= 1
		stock.atp += ATP_PER_CARB
		changed.emit()
	if stock.carb <= CARB_RESERVE:
		mito_timer = 0.0

func add(type: String, amount: int = 1) -> void:
	stock[type] += amount
	changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if stock[k] < cost[k]:
			return false
	return true

func prereqs_met(id: String) -> bool:
	for need in GENES[id].needs:
		if not unlocked.has(need):
			return false
	return true

func unlock(id: String) -> void:
	if unlocked.has(id) or not prereqs_met(id) or not can_afford(GENES[id].cost):
		return
	for k in GENES[id].cost:
		stock[k] -= GENES[id].cost[k]
	unlocked[id] = true
	match id:
		"transporters": intake_mult *= 1.25
		"glucose": weights.carb *= 2.0
		"permease": weights.amino *= 2.0
		"scavenge": weights.lipid *= 2.0
		"mitochondrion": mitochondria = 1
		"efficient": channel_discount = 0.3
		"duplication": intake_mult *= 1.5
	changed.emit()

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
