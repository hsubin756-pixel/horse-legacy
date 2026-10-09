extends SceneTree

var checks: int = 0
var failures: int = 0
var test_directory: String

class MissingDataSession extends GameSession:
	func new_game(seed_value: int = -1, _config_path: String = NewGameFactory.DEFAULT_CONFIG) -> bool:
		return super.new_game(seed_value, "res://missing-new-game-data.json")

func _initialize() -> void:
	_run.call_deferred()

func check_result(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	# A SceneTree script otherwise uses a 64x64 root window in headless mode.
	root.size = Vector2i(1120, 760)
	test_directory = ProjectSettings.globalize_path("user://tests/run-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(test_directory)
	_test_new_game()
	_test_bad_data()
	_test_session()
	var persistence = preload("res://tests/persistence_tests.gd").new()
	persistence.run(check_result, test_directory)
	var time_tests = preload("res://tests/time_tests.gd").new()
	time_tests.run(check_result, test_directory)
	var training_tests = preload("res://tests/training_tests.gd").new()
	training_tests.run(check_result, test_directory)
	var race_tests = preload("res://tests/race_tests.gd").new()
	race_tests.run(check_result, test_directory)
	var replay_tests = preload("res://tests/replay_tests.gd").new()
	replay_tests.run(check_result, test_directory)
	await _test_ui()
	await _test_start_feedback()
	await _test_race_ui()
	print("Horse Legacy: %d checks, %d passed, %d failed" % [checks, checks - failures, failures])
	if failures == 0:
		for file_name: String in DirAccess.get_files_at(test_directory):
			DirAccess.remove_absolute(test_directory.path_join(file_name))
		DirAccess.remove_absolute(test_directory)
	else:
		print("Failure artifacts: ", test_directory)
	quit(1 if failures > 0 else 0)

func _test_new_game() -> void:
	var state := NewGameFactory.create(1234)
	check_result(state != null, "Default new game configuration loads")
	if state == null:
		return
	var horses := state.owned_horses()
	check_result(horses.size() == 2, "New ranch has two owned horses")
	check_result(horses[0].sex == Horse.Sex.MALE and horses[1].sex == Horse.Sex.FEMALE, "Starting horses are male and female")
	var ids: Dictionary = {state.player_farm.id: true}
	var valid_stats: bool = true
	var valid_founders: bool = true
	for horse: Horse in horses:
		ids[horse.id] = true
		valid_founders = valid_founders and horse.owner_farm_id == state.player_farm.id and horse.father_id.is_empty() and horse.mother_id.is_empty()
		valid_founders = valid_founders and horse.age_years(state.current_week) == 3 and horse.career_status == Horse.CareerStatus.UNRACED and horse.life_stage == Horse.LifeStage.ADULT
		valid_founders = valid_founders and horse.starts == 0 and horse.wins == 0 and horse.injury_weeks == 0
		for key: StringName in StatBlock.KEYS:
			valid_stats = valid_stats and horse.stats.values[key] >= 0 and horse.stats.values[key] <= horse.potential.values[key] and horse.potential.values[key] <= 100
	check_result(ids.size() == 3 and not ids.has(""), "Farm and horse IDs are unique and nonempty")
	check_result(valid_stats, "All six current stats remain within their independent potential caps")
	check_result(valid_founders, "Founders have consistent age, ownership, health, and empty ancestry/career")
	check_result(horses[0].age_years(51) == 3 and horses[0].age_years(52) == 4, "Age changes at the 52-week boundary")
	check_result(not state.add_owned_horse(horses[0]) and state.player_farm.horse_ids.size() == 2, "Duplicate registration cannot duplicate ownership")
	var outsider := Horse.new()
	outsider.id = "outsider"
	outsider.owner_farm_id = "another-farm"
	check_result(not state.add_owned_horse(outsider) and state.horses.size() == 2, "Foreign ownership registration leaves state intact")
	var fresh_id := state.allocate_id("horse")
	check_result(not ids.has(fresh_id), "Future IDs do not collide with founders")
	var other := NewGameFactory.create(1234)
	check_result(other.rng.randi() == state.rng.randi(), "Explicit new-game seed reproduces RNG state")
	var original_potential: float = horses[0].potential.values[&"speed"]
	horses[0].stats.values[&"speed"] = 1
	horses[0].race_result_ids.append("test-result")
	check_result(horses[0].potential.values[&"speed"] == original_potential and horses[1].race_result_ids.is_empty(), "Horse data and current/potential blocks do not share mutable state")
	check_result(other.owned_horses()[0].stats.values[&"speed"] != 1 and other.owned_horses()[0].race_result_ids.is_empty(), "New games have independent mutable data")

func _test_bad_data() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NewGameFactory.DEFAULT_CONFIG))
	var bad := source.duplicate(true)
	bad.horses[0].stats[0] = "fast"
	check_result(NewGameFactory.from_config(bad, 1) == null, "Non-numeric stat is rejected")
	bad = source.duplicate(true)
	bad.horses[0].stats[0] = 101
	check_result(NewGameFactory.from_config(bad, 1) == null, "Out-of-range stat is rejected")
	bad = source.duplicate(true)
	bad.horses[0].potential[0] = 1
	check_result(NewGameFactory.from_config(bad, 1) == null, "Potential below current ability is rejected")
	bad = source.duplicate(true)
	bad.horses[0].age_years = 3.5
	check_result(NewGameFactory.from_config(bad, 1) == null, "Fractional age is not silently truncated")
	bad = source.duplicate(true)
	bad.horses[1].sex = "male"
	check_result(NewGameFactory.from_config(bad, 1) == null, "Initial male/female pair requirement is enforced")
	bad = source.duplicate(true)
	bad.horses[0].stats.pop_back()
	check_result(NewGameFactory.from_config(bad, 1) == null, "Missing stat is rejected")
	check_result(NewGameFactory.from_config({}, 1) == null, "Missing configuration fields are rejected")

func _test_session() -> void:
	var session := GameSession.new()
	check_result(not session.save_game().ok, "Saving before starting a game is rejected")
	check_result(not session.select_horse("missing") and session.selected_horse() == null, "Selection before a new game is safe")
	check_result(session.new_game(42), "Session starts a valid game")
	var previous_state: GameState = session.state
	var selected: String = session.selected_horse_id
	check_result(not session.select_horse("unknown") and session.selected_horse_id == selected, "Unknown selection preserves selected horse")
	check_result(not session.new_game(42, "res://missing-config.json") and session.state == previous_state and session.selected_horse_id == selected, "Failed new game preserves the active game")
	var second: String = session.state.player_farm.horse_ids[1]
	check_result(session.select_horse(second) and session.selected_horse().id == second, "Session selection resolves by ID")
	session.state.current_week = 17
	check_result(session.new_game(42) and session.state != previous_state and session.state.current_week == 0 and session.state.horses.size() == 2, "Restart creates a clean state without accumulated horses")

func _click(button: Button) -> void:
	await process_frame
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame
	var position: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion)
	var press := InputEventMouseButton.new()
	press.position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release)
	await process_frame

func _test_ui() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var screen := scene.instantiate() as MainScreen
	screen.session.saves = SaveManager.new(test_directory.path_join("ui.json"))
	root.add_child(screen)
	await process_frame
	await process_frame
	check_result(screen.title_screen.visible and not screen.ranch_screen.visible and screen.session.state == null, "App opens on the title screen without starting a hidden game")
	await _capture("title")
	await _click(screen.start_button)
	check_result(screen.session.state != null and screen.ranch_screen.visible and not screen.title_screen.visible, "Mouse input on New Game opens the ranch")
	if screen.session.state == null:
		screen.queue_free()
		await process_frame
		return
	check_result(screen.horse_buttons.size() == 2, "Ranch lists both horses")
	var horse: Horse = screen.session.selected_horse()
	check_result(screen.details.displayed_horse_id == horse.id and screen.details.name_label.text == horse.name, "Initial selection matches the horse detail")
	var second_id: String = screen.session.state.player_farm.horse_ids[1]
	await _click(screen.horse_buttons[second_id])
	horse = screen.session.selected_horse()
	check_result(horse.id == second_id and screen.details.name_label.text == horse.name and screen.horse_buttons[second_id].button_pressed, "Mouse selection updates the detail and selected button")
	check_result(screen.details.stat_bars[0].value == horse.stats.values[&"speed"] and screen.details.summary_label.text.contains("암말"), "Selected horse stats and sex are rendered from domain data")
	await _capture("ranch")
	var original: GameState = screen.session.state
	await _click(screen.restart_button)
	check_result(screen.restart_dialog.visible and screen.session.state == original, "Restart requires confirmation before replacing state")
	screen.restart_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check_result(not screen.restart_dialog.visible and screen.session.state == original, "Cancelling restart preserves current game")
	await _click(screen.restart_button)
	screen.restart_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.state != original and screen.session.state.horses.size() == 2 and screen.horse_buttons.size() == 2, "Confirmed restart replaces data and rebuilds the list without duplicates")
	await _test_weekly_ui(screen)
	await _test_training_ui(screen)
	await _test_persistence_ui(screen)
	screen.queue_free()
	await process_frame
	# A fresh screen must discover the saved game without starting a new one first.
	screen = scene.instantiate() as MainScreen
	screen.session.saves = SaveManager.new(test_directory.path_join("ui.json"))
	root.add_child(screen)
	await process_frame
	await process_frame
	check_result(not screen.continue_button.disabled and screen.session.state == null, "Fresh title screen discovers the existing save")
	await _click(screen.continue_button)
	check_result(screen.ranch_screen.visible and screen.session.state != null and screen.details.displayed_horse_id == screen.session.selected_horse_id, "Continue button restores the saved ranch and selection")
	screen.queue_free()
	await process_frame

func _test_start_feedback() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var screen := scene.instantiate() as MainScreen
	screen.session = MissingDataSession.new()
	screen.session.saves = SaveManager.new(test_directory.path_join("missing-data.json"))
	root.add_child(screen)
	await process_frame
	await process_frame
	await _click(screen.start_button)
	check_result(screen.startup_error_dialog.visible and screen.startup_error_dialog.dialog_text.contains("누락된 파일"), "Failed new game opens a visible diagnostic dialog")
	check_result(screen.title_screen.visible and screen.session.state == null and not screen.start_button.disabled, "Failed startup keeps the title usable for retry")
	screen.queue_free()
	await process_frame
	screen = scene.instantiate() as MainScreen
	screen.session.saves = SaveManager.new(test_directory.path_join("keyboard.json"))
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.start_button.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key)
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = false
	root.push_input(key)
	await process_frame
	check_result(screen.session.state != null and screen.ranch_screen.visible, "Enter activates the focused New Game button")
	screen.queue_free()
	await process_frame

func _test_weekly_ui(screen: MainScreen) -> void:
	var selected: String = screen.session.selected_horse_id
	await _click(screen.week_controls.next_week_button)
	check_result(screen.session.state.current_week == 1 and screen.date_label.text.contains("2주") and screen.session.selected_horse_id == selected, "One-week button updates date and preserves selected horse")
	screen.week_controls.next_week_button.pressed.emit()
	check_result(screen.session.state.current_week == 1, "Rapid duplicate button activation is ignored")
	check_result(screen.week_controls.report_label.visible and screen.details.stat_values[0].text.contains(".1"), "Weekly growth appears in the report and decimal stat display")
	await create_timer(0.4).timeout
	await _click(screen.week_controls.four_weeks_button)
	check_result(screen.week_controls.confirm.visible and screen.session.state.current_week == 1, "Four-week button asks before advancing")
	screen.week_controls.confirm.get_cancel_button().pressed.emit()
	await process_frame
	check_result(screen.session.state.current_week == 1, "Cancelling multiple weeks preserves progress")
	await _click(screen.week_controls.four_weeks_button)
	screen.week_controls.confirm.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.state.current_week == 5 and screen.week_controls.report_label.visible, "Confirming four weeks runs and reports all four ticks")
	await _capture("weekly")

func _test_training_ui(screen: MainScreen) -> void:
	await create_timer(0.4).timeout
	var first: String = screen.session.selected_horse_id
	var second: String = screen.session.state.player_farm.horse_ids[1]
	var speed: float = screen.session.selected_horse().stats.values[&"speed"]
	await _click(screen.training_controls.buttons["sprint"])
	check_result(screen.session.state.training_assignments.get(first) == "sprint" and screen.training_controls.heading.text.contains("단거리"), "Clicking training assigns selected horse and updates UI")
	await _click(screen.horse_buttons[second])
	check_result(screen.training_controls.buttons["rest"].button_pressed, "Switching horse shows that horse's independent plan")
	await _click(screen.training_controls.buttons["mental"])
	await _click(screen.horse_buttons[first])
	check_result(screen.training_controls.buttons["sprint"].button_pressed and screen.session.state.training_assignments.size() == 2, "Horse switching preserves both training plans")
	await _capture("training")
	await _click(screen.week_controls.next_week_button)
	check_result(screen.session.selected_horse().stats.values[&"speed"] > speed + 0.5 and screen.training_controls.buttons["rest"].button_pressed and screen.week_controls.report_label.text.contains("단거리 훈련"), "Weekly button applies training, reports action and resets plan to rest")
	screen.session.selected_horse().fatigue = 80
	screen.session.select_horse(first)
	check_result(screen.training_controls.info.text.contains("과로 상태"), "Overwork warning shown before training selection")
	screen.session.selected_horse().injury_weeks = 1
	screen.session.select_horse(first)
	check_result(screen.training_controls.buttons["sprint"].disabled and not screen.training_controls.buttons["rest"].disabled, "Injured horse UI disables training and keeps rest available")
	screen.session.selected_horse().injury_weeks = 0
	screen.session.select_horse(first)
	await _click(screen.training_controls.buttons["endurance"])

func _test_persistence_ui(screen: MainScreen) -> void:
	check_result(screen.load_button.disabled and screen.recovery_button.disabled, "Load and recovery are disabled when their files do not exist")
	var second_id: String = screen.session.state.player_farm.horse_ids[1]
	screen.session.select_horse(second_id)
	var ancestor := Horse.new()
	ancestor.id = screen.session.state.allocate_id("horse")
	ancestor.name = "기록에 남은 조상"
	ancestor.birth_week = -600
	screen.session.state.horses[ancestor.id] = ancestor
	screen.session.state.owned_horses()[0].father_id = ancestor.id
	screen.session.state.current_week = 53
	await _click(screen.save_button)
	check_result(screen.session.saves.has_save() and not screen.load_button.disabled and screen.error_label.text == "저장했습니다.", "Save button writes the current game and reports success")
	var saved := FileAccess.get_file_as_bytes(screen.session.saves.path)
	screen.session.state.current_week = 54
	await _click(screen.save_button)
	check_result(screen.file_dialog.visible and FileAccess.get_file_as_bytes(screen.session.saves.path) == saved, "Overwrite confirmation appears before disk changes")
	screen.file_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check_result(not screen.file_dialog.visible and FileAccess.get_file_as_bytes(screen.session.saves.path) == saved, "Cancel overwrite preserves the saved game")
	await _click(screen.save_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.saves.has_backup() and not screen.recovery_button.disabled, "Confirmed save makes backup recovery available")
	screen.session.state.current_week = 100
	var active: GameState = screen.session.state
	await _click(screen.load_button)
	screen.file_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check_result(screen.session.state == active and screen.session.state.current_week == 100, "Cancel load preserves unsaved progress")
	await _click(screen.load_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.state.current_week == 54 and screen.session.selected_horse_id == second_id and screen.details.displayed_horse_id == second_id, "Confirmed load restores time, selection and details together")
	check_result(screen.session.state.training_assignments.get(screen.session.state.player_farm.horse_ids[0]) == "endurance" and screen.training_controls.buttons["rest"].button_pressed, "UI load restores pending training and shows selected horse's own plan")
	check_result(screen.session.state.horses.size() == 3 and screen.date_label.text.contains("보유 말 2마리"), "Historical ancestors are restored without inflating the owned horse count")
	await _capture("loaded")
	active = screen.session.state
	var file := FileAccess.open(screen.session.saves.path, FileAccess.WRITE)
	file.store_string("broken save")
	file.close()
	await _click(screen.load_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.state == active and screen.error_label.visible and screen.error_label.text.contains("손상"), "UI reports corrupt save without replacing current progress")
	await _click(screen.recovery_button)
	screen.file_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check_result(screen.session.state == active and FileAccess.get_file_as_string(screen.session.saves.path) == "broken save", "Cancel recovery leaves memory and disk untouched")
	await _click(screen.recovery_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.state.current_week == 53 and screen.error_label.text.contains("백업"), "Confirmed UI recovery restores the previous save")

func _test_race_ui() -> void:
	var screen := (load("res://scenes/main.tscn") as PackedScene).instantiate() as MainScreen
	screen.session.saves = SaveManager.new(test_directory.path_join("race-ui.json"))
	root.add_child(screen)
	await process_frame
	await _click(screen.start_button)
	await _click(screen.race_controls.entry_button)
	check_result(screen.race_controls.confirm.visible and screen.session.state.current_week == 0, "Race UI confirms the horse, training replacement and weekly cost")
	screen.race_controls.confirm.get_cancel_button().pressed.emit()
	await process_frame
	check_result(screen.session.state.race_results.is_empty() and screen.session.state.current_week == 0, "Cancel race leaves ranch untouched")
	await _click(screen.race_controls.entry_button)
	screen.race_controls.confirm.get_ok_button().pressed.emit()
	await process_frame
	check_result(screen.session.state.current_week == 1 and screen.replay.visible and not screen.replay.playback.finished and screen.details.career_label.text.contains("1전"), "Confirm race opens moving replay after committing career once")
	await _click(screen.replay.pause_button)
	var elapsed: float = screen.replay.playback.elapsed
	await process_frame
	check_result(screen.replay.playback.paused and screen.replay.playback.elapsed == elapsed and screen.replay.return_button.disabled, "Replay pause freezes movement and result acknowledgement waits for finish")
	await _click(screen.replay.speeds[8])
	check_result(screen.replay.playback.speed == 8 and screen.replay.speeds[8].button_pressed, "Replay speed button selects eight-times playback")
	screen.replay.playback.elapsed = screen.replay.playback.duration * 0.6
	screen.replay.refresh()
	await _capture("race-replay")
	await _click(screen.replay.save_button)
	check_result(screen.session.saves.has_save() and screen.replay.status_label.text == "저장했습니다.", "Save during playback reports success on race screen")
	var before := JSON.stringify(SaveCodec.encode(screen.session.state, screen.session.selected_horse_id))
	await _click(screen.replay.save_button)
	check_result(screen.file_dialog.visible, "Replay overwrite still requires confirmation")
	screen.file_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check_result(screen.replay.visible and screen.replay.playback.paused, "Cancel overwrite keeps replay paused and usable")
	await _click(screen.replay.skip_button)
	check_result(screen.replay.playback.finished and screen.replay.standings.text.contains("4위") and not screen.replay.return_button.disabled, "Skip displays the committed final result and enables return")
	await _click(screen.replay.load_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(JSON.stringify(SaveCodec.encode(screen.session.state, screen.session.selected_horse_id)) == before and screen.replay.visible and screen.replay.playback.finished, "Loading mid-replay save opens final result without awarding it again")
	await _capture("race-result")
	var race_path: String = screen.session.saves.path
	screen.queue_free()
	await process_frame
	screen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as MainScreen
	screen.session.saves = SaveManager.new(race_path)
	root.add_child(screen)
	await process_frame
	await _click(screen.continue_button)
	check_result(screen.replay.visible and screen.replay.playback.finished and screen.replay.playback.frames.is_empty(), "Fresh game instance continues pending save directly at result screen")
	await _click(screen.replay.return_button)
	check_result(not screen.replay.visible and screen.session.state.pending_race_result_id.is_empty() and screen.ranch_screen.is_visible_in_tree(), "Acknowledging result returns to usable ranch and clears pending marker")
	await _click(screen.save_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	await _click(screen.load_button)
	screen.file_dialog.get_ok_button().pressed.emit()
	await process_frame
	check_result(not screen.replay.visible and screen.session.selected_horse().starts == 1, "Loading acknowledged save remains at ranch with one career start")
	screen.session.selected_horse().injury_weeks = 1
	screen.session.select_horse(screen.session.selected_horse_id)
	check_result(screen.race_controls.entry_button.disabled and screen.race_controls.summary.text.contains("부상"), "Race UI explains why an injured horse cannot enter")
	screen.queue_free()
	await process_frame

func _capture(label: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var directory := arg.trim_prefix("--screenshots=")
			DirAccess.make_dir_recursive_absolute(directory)
			var error := root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
			check_result(error == OK, label + " screenshot captured")
