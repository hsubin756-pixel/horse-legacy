class_name GameSession
extends RefCounted

signal game_started
signal horse_selected(horse_id: String)
signal weeks_advanced(result: Dictionary)
signal training_changed
signal race_finished(result: Dictionary)

var state: GameState
var selected_horse_id: String = ""
var saves := SaveManager.new()
var last_start_error: String = ""
var _advancing: bool = false

func acknowledge_race_result(race_id: String) -> bool:
	if state == null or race_id.is_empty() or state.pending_race_result_id != race_id:
		return false
	state.pending_race_result_id = ""
	return true

func enter_race(horse_id: String, expected_week: int) -> Dictionary:
	if _advancing or state == null or expected_week != state.current_week:
		return {"ok": false, "message": "경주 출전 요청이 만료되었거나 이미 처리되었습니다."}
	_advancing = true
	var result := RaceSystem.run(state, selected_horse_id, horse_id)
	if result.ok:
		state = result.state
		race_finished.emit(result)
	_advancing = false
	return result

func assign_training(horse_id: String, program: String) -> Dictionary:
	if _advancing or state == null or not state.player_farm.horse_ids.has(horse_id):
		return {"ok": false, "message": "훈련을 배정할 수 있는 보유 말을 선택해 주세요."}
	if not program in TrainingSystem.PROGRAMS:
		return {"ok": false, "message": "알 수 없는 훈련 종류입니다."}
	var reason := TrainingSystem.unavailable_reason(state.horses[horse_id])
	if program != "rest" and not reason.is_empty():
		return {"ok": false, "message": reason}
	if program == "rest":
		state.training_assignments.erase(horse_id)
	else:
		state.training_assignments[horse_id] = program
	training_changed.emit()
	return {"ok": true, "message": "이번 주 %s 배정 · 저장하지 않은 변경이 있습니다." % TrainingSystem.label_for(program)}

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
