class_name NewGameFactory
extends RefCounted

const DEFAULT_CONFIG: String = "res://data/rules/new_game.json"

static func create(seed_value: int, config_path: String = DEFAULT_CONFIG) -> GameState:
	if not FileAccess.file_exists(config_path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary:
		return null
	return from_config(parsed, seed_value)

static func from_config(config: Dictionary, seed_value: int) -> GameState:
	var farm_name: Variant = config.get("farm_name")
	var entries: Variant = config.get("horses")
	if not farm_name is String or farm_name.strip_edges().is_empty():
		return null
	if not entries is Array or entries.size() < 2:
		return null
	var state := GameState.new()
	state.rng.seed = seed_value
	state.player_farm.id = state.allocate_id("farm")
	state.player_farm.name = farm_name
	var sexes: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			return null
		var horse := _create_horse(entry, state)
		if horse == null or not state.add_owned_horse(horse):
			return null
		sexes[horse.sex] = true
	if not sexes.has(Horse.Sex.MALE) or not sexes.has(Horse.Sex.FEMALE):
		return null
	return state

static func _create_horse(entry: Dictionary, state: GameState) -> Horse:
	var horse_name: Variant = entry.get("name")
	var sex_value: Variant = entry.get("sex")
	var age: Variant = entry.get("age_years")
	if not horse_name is String or horse_name.strip_edges().is_empty():
		return null
	if sex_value != "male" and sex_value != "female":
		return null
	if not (age is int or age is float):
		return null
	if not is_finite(float(age)) or float(age) != floorf(float(age)) or age < 3 or age > 6:
		return null
	if not entry.get("stats") is Array or not entry.get("potential") is Array:
		return null
	var stats := StatBlock.from_array(entry.stats)
	var potential := StatBlock.from_array(entry.potential)
	if stats == null or potential == null:
		return null
	for key: StringName in StatBlock.KEYS:
		if stats.values[key] > potential.values[key]:
			return null
	var horse := Horse.new()
	horse.id = state.allocate_id("horse")
	horse.name = horse_name
	horse.sex = Horse.Sex.MALE if sex_value == "male" else Horse.Sex.FEMALE
	horse.birth_week = state.current_week - int(age) * GameState.WEEKS_PER_YEAR
	horse.owner_farm_id = state.player_farm.id
	horse.stats = stats
	horse.potential = potential
	return horse
