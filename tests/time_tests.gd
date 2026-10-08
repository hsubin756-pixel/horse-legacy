extends RefCounted

func run(check: Callable, directory: String) -> void:
	var session := GameSession.new()
	check.call(not session.advance_weeks(1).ok, "Time cannot advance without an active game")
	session.new_game(123)
	var original: GameState = session.state
	check.call(not session.advance_weeks(0).ok and not session.advance_weeks(53).ok and session.state == original, "Invalid week counts preserve the current game")
	check.call(not TimeSystem.advance(session.state, session.selected_horse_id, 1, "res://missing-rules.json").ok and session.state == original, "Missing rules do not partially advance time")
	var horse: Horse = session.selected_horse()
	horse.fatigue = 35
	horse.stress = 20
	horse.injury_weeks = 2
	var before_speed: float = horse.stats.values[&"speed"]
	var result := session.advance_weeks(1, 0)
	horse = session.selected_horse()
	check.call(result.ok and session.state.current_week == 1 and original.current_week == 0, "One week commits once on an independent state")
	check.call(horse.fatigue < 35 and horse.stress < 20 and horse.fitness > 80 and horse.injury_weeks == 1, "Rest reduces fatigue/stress and recovers fitness/injury")
	check.call(horse.stats.values[&"speed"] == before_speed, "Injured horses do not receive natural growth")
	session.advance_weeks(1)
	check.call(session.selected_horse().injury_weeks == 0 and session.selected_horse().stats.values[&"speed"] == before_speed, "Healing week finishes injury before growth resumes the following week")
	session.advance_weeks(1)
	check.call(session.selected_horse().stats.values[&"speed"] > before_speed, "Recovered young horse resumes growth")
	session.advance_weeks(20)
	horse = session.selected_horse()
	check.call(horse.fatigue == 0 and horse.stress == 0 and horse.injury_weeks == 0 and horse.fitness == 100, "Long rest respects all condition bounds")
	var bulk := GameSession.new()
	var single := GameSession.new()
	bulk.new_game(246)
	single.new_game(246)
	bulk.advance_weeks(4)
	for index: int in 4:
		single.advance_weeks(1)
	check.call(_snapshot(bulk) == _snapshot(single), "Four-week advance matches four individual weekly ticks exactly")
	check.call(not bulk.advance_weeks(1, 0).ok and bulk.state.current_week == 4, "Stale expected week prevents duplicate command execution")
	var nested: Array[bool] = []
	var reentrant := func(_result: Dictionary) -> void: nested.append(bulk.advance_weeks(1).ok)
	bulk.weeks_advanced.connect(reentrant)
	bulk.advance_weeks(1)
	check.call(nested == [false] and bulk.state.current_week == 5, "Reentrant advance is rejected while notifying listeners")
	bulk.weeks_advanced.disconnect(reentrant)
	var boundary := GameSession.new()
	boundary.new_game(10)
	boundary.state.current_week = 51
	boundary.advance_weeks(1)
	check.call(boundary.state.current_week == 52 and boundary.selected_horse().age_years(52) == 4, "Year and age cross the 52-week boundary together")
	var juvenile := GameSession.new()
	juvenile.new_game(10)
	juvenile.selected_horse().life_stage = Horse.LifeStage.FOAL
	juvenile.selected_horse().birth_week = -155
	var matured := juvenile.advance_weeks(1)
	check.call(juvenile.selected_horse().life_stage == Horse.LifeStage.ADULT and matured.changes[0].matured, "Foal reaches the adult boundary and reports maturation")
	var capped := GameSession.new()
	capped.new_game(10)
	horse = capped.selected_horse()
	horse.stats.values[&"speed"] = horse.potential.values[&"speed"] - 0.01
	var potential: float = horse.potential.values[&"speed"]
	capped.advance_weeks(4)
	check.call(capped.selected_horse().stats.values[&"speed"] == potential and capped.selected_horse().potential.values[&"speed"] == potential, "Growth stops at potential without changing the genetic cap")
	var old := GameSession.new()
	old.new_game(10)
	old.selected_horse().birth_week = -10 * 52
	old.selected_horse().stats.values[&"speed"] = 0.01
	var old_stamina: float = old.selected_horse().stats.values[&"stamina"]
	old.advance_weeks(4)
	check.call(old.selected_horse().stats.values[&"stamina"] < old_stamina and old.selected_horse().stats.values[&"speed"] == 0, "Past-prime abilities decline without becoming negative")
	var history := GameSession.new()
	history.new_game(10)
	history.selected_horse().life_stage = Horse.LifeStage.DECEASED
	var before: Dictionary = SaveCodec.encode(history.state, history.selected_horse_id).horses[0]
	history.advance_weeks(4)
	check.call(before == SaveCodec.encode(history.state, history.selected_horse_id).horses[0], "Deceased ancestor records are not trained or healed by time")
	for kind: StringName in [&"early", &"normal", &"late"]:
		var typed := GameSession.new()
		typed.new_game(10)
		typed.selected_horse().growth_type = kind
		typed.selected_horse().birth_week = -4 * 52
		var speed: float = typed.selected_horse().stats.values[&"speed"]
		typed.advance_weeks(1)
		check.call((typed.selected_horse().stats.values[&"speed"] == speed) if kind == &"early" else (typed.selected_horse().stats.values[&"speed"] > speed), "Growth profile age window: " + str(kind))
	var resumed := GameSession.new()
	resumed.new_game(444)
	resumed.saves = SaveManager.new(directory.path_join("weekly.json"))
	resumed.advance_weeks(4)
	var saved := resumed.save_game()
	resumed.advance_weeks(4)
	var uninterrupted := _snapshot(resumed)
	var loaded := resumed.load_game()
	resumed.advance_weeks(4)
	check.call(saved.ok and loaded.ok and _snapshot(resumed) == uninterrupted, "Save/load between weekly advances matches uninterrupted simulation")
	var legacy := GameSession.new()
	legacy.saves = SaveManager.new(directory.path_join("legacy-weekly.json"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/save_v1.json"), legacy.saves.path)
	var old_bytes := FileAccess.get_file_as_bytes(legacy.saves.path)
	var legacy_loaded := legacy.load_game()
	check.call(legacy_loaded.ok and legacy.state.current_week == 0 and FileAccess.get_file_as_bytes(legacy.saves.path) == old_bytes, "Version 0.2 save loads unchanged from disk")
	var legacy_advanced := legacy.advance_weeks(1)
	var legacy_saved := legacy.save_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(legacy.saves.path))
	check.call(legacy_advanced.ok and legacy_saved.ok and data.schema_version == GameState.SCHEMA_VERSION and data.simulation_version == GameState.SIMULATION_VERSION and FileAccess.get_file_as_bytes(legacy.saves.path + ".bak") == old_bytes, "Legacy save advances under current simulation and retains its original as backup")

func _snapshot(session: GameSession) -> String:
	return JSON.stringify(SaveCodec.encode(session.state, session.selected_horse_id), "", true, true)
