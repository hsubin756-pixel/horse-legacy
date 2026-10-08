class_name GameState
extends RefCounted

const WEEKS_PER_YEAR: int = 52
const SCHEMA_VERSION: int = 1
const SIMULATION_VERSION: int = 2
var current_week: int = 0
var next_id: int = 1
var horses: Dictionary[String, Horse] = {}
var player_farm := Farm.new()
var rng := RandomNumberGenerator.new()

func allocate_id(prefix: String) -> String:
	var result := "%s-%d" % [prefix, next_id]
	next_id += 1
	return result

func add_owned_horse(horse: Horse) -> bool:
	if horse == null or horse.id.is_empty() or horses.has(horse.id):
		return false
	if player_farm.id.is_empty() or horse.owner_farm_id != player_farm.id:
		return false
	horses[horse.id] = horse
	player_farm.horse_ids.append(horse.id)
	return true

func owned_horses() -> Array[Horse]:
	var result: Array[Horse] = []
	for horse_id: String in player_farm.horse_ids:
		result.append(horses[horse_id])
	return result
