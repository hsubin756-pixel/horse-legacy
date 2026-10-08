class_name SaveCodec
extends RefCounted

static func encode(state: GameState, selected_id: String) -> Dictionary:
	var horse_data: Array = []
	for horse: Horse in state.horses.values():
		var entry: Dictionary = {}
		for key: String in SaveSchema.HORSE_STRINGS:
			entry[key] = str(horse.get(key))
		for key: String in SaveSchema.HORSE_INTS + SaveSchema.CONDITION_FIELDS:
			entry[key] = horse.get(key)
		entry.stats = []
		entry.potential = []
		for key: StringName in StatBlock.KEYS:
			entry.stats.append(horse.stats.values[key])
			entry.potential.append(horse.potential.values[key])
		entry.race_result_ids = horse.race_result_ids.duplicate()
		horse_data.append(entry)
	return {
		"schema_version": GameState.SCHEMA_VERSION, "simulation_version": GameState.SIMULATION_VERSION,
		"current_week": state.current_week, "next_id": state.next_id,
		"rng_seed": str(state.rng.seed), "rng_state": str(state.rng.state),
		"selected_horse_id": selected_id,
		"farm": {"id": state.player_farm.id, "name": state.player_farm.name,
			"horse_ids": state.player_farm.horse_ids.duplicate(),
			"money": state.player_farm.money, "reputation": state.player_farm.reputation},
		"horses": horse_data,
		"training_assignments": state.training_assignments.duplicate(),
	}

static func decode(value: Variant) -> SaveResult:
	var reason := SaveSchema.validate(value)
	if not reason.is_empty():
		return SaveResult.failure(reason)
	var d: Dictionary = value
	var state := GameState.new()
	state.current_week = int(d.current_week)
	if d.schema_version >= 2:
		state.training_assignments.assign(d.training_assignments)
	state.next_id = int(d.next_id)
	state.rng.seed = d.rng_seed.to_int()
	state.rng.state = d.rng_state.to_int()
	state.player_farm.id = d.farm.id
	state.player_farm.name = d.farm.name
	state.player_farm.money = int(d.farm.money)
	state.player_farm.reputation = int(d.farm.reputation)
	state.player_farm.horse_ids.assign(d.farm.horse_ids)
	for entry: Dictionary in d.horses:
		var horse := Horse.new()
		for key: String in SaveSchema.HORSE_STRINGS:
			horse.set(key, StringName(entry[key]) if key == "growth_type" else entry[key])
		for key: String in SaveSchema.HORSE_INTS:
			horse.set(key, int(entry[key]))
		for key: String in SaveSchema.CONDITION_FIELDS:
			horse.set(key, float(entry[key]))
		horse.stats = StatBlock.from_array(entry.stats)
		horse.potential = StatBlock.from_array(entry.potential)
		horse.race_result_ids.assign(entry.race_result_ids)
		state.horses[horse.id] = horse
	return SaveResult.success(state, d.selected_horse_id)
