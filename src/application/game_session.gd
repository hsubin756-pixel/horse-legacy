class_name GameSession
extends RefCounted

signal game_started
signal horse_selected(horse_id: String)
signal weeks_advanced(result: Dictionary)

var state: GameState
var selected_horse_id: String = ""
var saves := SaveManager.new()
var last_start_error: String = ""
var _advancing: bool = false

func advance_weeks(weeks: int, expected_week: int = -1) -> Dictionary:
	if _advancing or (state != null and expected_week >= 0 and expected_week != state.current_week):
		return {"ok": false, "message": "이미 처리된 주간 진행 요청입니다."}
	_advancing = true
	var result := TimeSystem.advance(state, selected_horse_id, weeks)
	if result.ok:
		state = result.state
		weeks_advanced.emit(result)
	_advancing = false
	return result

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
	last_start_error = ""
	if seed_value < 0:
		var seed_source := RandomNumberGenerator.new()
		seed_source.randomize()
		seed_value = seed_source.randi()
	var candidate := NewGameFactory.create(seed_value, config_path)
	if candidate == null:
		last_start_error = "새 게임에 필요한 말 데이터를 읽거나 생성하지 못했습니다.\nGitHub에서 프로젝트 전체를 다시 받아 압축을 풀고 project.godot를 가져와 주세요."
		if not FileAccess.file_exists(config_path):
			last_start_error += "\n누락된 파일: " + config_path
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
