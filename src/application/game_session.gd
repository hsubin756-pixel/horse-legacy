class_name GameSession
extends RefCounted

signal game_started
signal horse_selected(horse_id: String)

var state: GameState
var selected_horse_id: String = ""
var saves := SaveManager.new()

func save_game() -> SaveResult:
	return saves.save_game(state, selected_horse_id)

func load_game() -> SaveResult:
	return _apply_loaded(saves.load_game())

func recover_backup() -> SaveResult:
	return _apply_loaded(saves.recover_backup())

func _apply_loaded(result: SaveResult) -> SaveResult:
	if result.ok:
		state = result.state
		selected_horse_id = result.selected_horse_id
		game_started.emit()
		horse_selected.emit(selected_horse_id)
	return result

func new_game(seed_value: int = -1, config_path: String = NewGameFactory.DEFAULT_CONFIG) -> bool:
	if seed_value < 0:
		var seed_source := RandomNumberGenerator.new()
		seed_source.randomize()
		seed_value = seed_source.randi()
	var candidate := NewGameFactory.create(seed_value, config_path)
	if candidate == null:
		return false
	state = candidate
	selected_horse_id = state.player_farm.horse_ids[0]
	game_started.emit()
	horse_selected.emit(selected_horse_id)
	return true

func select_horse(horse_id: String) -> bool:
	if state == null or not state.player_farm.horse_ids.has(horse_id):
		return false
	selected_horse_id = horse_id
	horse_selected.emit(horse_id)
	return true

func selected_horse() -> Horse:
	if state == null:
		return null
	return state.horses.get(selected_horse_id)
