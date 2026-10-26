extends Node

signal changed

const BASE_INTAKE := 0.5
const PER_CHANNEL := 0.5

var stock = {"carb": 0, "lipid": 0, "amino": 0}
var channels := 0
var unlocked: Dictionary = {}

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
	"efficient": {"name": "Efficient channels", "effect": "Channels cost 30% less",
		"cost": {"amino": 10, "lipid": 6}, "needs": ["glucose", "permease"], "pos": Vector2(2, 0.5)},
	"duplication": {"name": "Gene duplication", "effect": "+50% intake",
		"cost": {"amino": 15, "lipid": 10, "carb": 10}, "needs": ["permease", "scavenge"], "pos": Vector2(2, 1.5)},
}

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
		"efficient": channel_discount = 0.3
		"duplication": intake_mult *= 1.5
	changed.emit()

func channel_cost() -> int:
	return int(round((3 + channels * 2) * (1.0 - channel_discount)))

func intake_rate() -> float:
	return (BASE_INTAKE + channels * PER_CHANNEL) * intake_mult

func build_channel() -> void:
	var c = channel_cost()
	if stock.amino >= c:
		stock.amino -= c
		channels += 1
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
