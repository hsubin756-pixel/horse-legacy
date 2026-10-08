extends RefCounted

func run(check: Callable, directory: String) -> void:
	var empty := GameSession.new()
	check.call(not empty.assign_training("missing", "sprint").ok, "Training before new game is rejected")
	var session := _session()
	var id: String = session.selected_horse_id
	var initial := _snapshot(session)
	check.call(not session.assign_training("missing", "sprint").ok and not session.assign_training(id, "unknown").ok and _snapshot(session) == initial, "Unknown horse/program rejects without changing state")
	check.call(session.assign_training(id, "sprint").ok and session.state.current_week == 0 and session.selected_horse().fatigue == 0, "Assignment does not spend time or apply training early")
	session.assign_training(id, "mental")
	check.call(session.state.training_assignments[id] == "mental" and session.state.training_assignments.size() == 1, "Replacing an assignment leaves one weekly action")
	session.assign_training(id, "rest")
	check.call(session.state.training_assignments.is_empty(), "Rest cancels a pending training assignment")
	var targets := {"sprint": [&"speed", &"acceleration"], "endurance": [&"stamina"], "hill": [&"power"], "mental": [&"spirit", &"intelligence"]}
	for program: String in targets:
		var trained := _session()
		var rested := _session()
		trained.assign_training(trained.selected_horse_id, program)
		trained.advance_weeks(1)
		rested.advance_weeks(1)
		var correct := true
		for key: StringName in StatBlock.KEYS:
			var delta: float = trained.selected_horse().stats.values[key] - rested.selected_horse().stats.values[key]
			correct = correct and (delta > 0 if key in targets[program] else is_zero_approx(delta))
		check.call(correct and trained.selected_horse().fatigue == 22 and trained.selected_horse().stress == 10, "Training targets correct stats and consumes condition: " + program)
		check.call(trained.state.training_assignments.is_empty() and trained.state.owned_horses()[1].fatigue == 0, "Training consumed once; other horse rests: " + program)
	var unavailable := _session()
	for status: String in ["injured", "retired", "foal", "deceased"]:
		var horse := unavailable.selected_horse()
		horse.injury_weeks = 1 if status == "injured" else 0
		horse.career_status = Horse.CareerStatus.RETIRED if status == "retired" else Horse.CareerStatus.UNRACED
		horse.life_stage = Horse.LifeStage.FOAL if status == "foal" else (Horse.LifeStage.DECEASED if status == "deceased" else Horse.LifeStage.ADULT)
		check.call(not unavailable.assign_training(horse.id, "hill").ok and unavailable.assign_training(horse.id, "rest").ok, "Unavailable horse can rest but cannot train: " + status)
	var rules := TrainingSystem.read_rules()
	var fresh := _session().selected_horse()
	var tired := _session().selected_horse()
	tired.fatigue = 90
	tired.stress = 60
	check.call(TrainingSystem.efficiency(tired) < TrainingSystem.efficiency(fresh) and TrainingSystem.injury_chance(tired, rules) > TrainingSystem.injury_chance(fresh, rules), "Fatigue/stress reduce efficiency and overwork raises injury risk")
	var overworked := _session()
	overworked.selected_horse().fatigue = 100
	overworked.selected_horse().stress = 100
	var before_fitness: float = overworked.selected_horse().fitness
	overworked.assign_training(overworked.selected_horse_id, "sprint")
	overworked.advance_weeks(1)
	check.call(overworked.selected_horse().fitness < before_fitness and overworked.selected_horse().fatigue == 100 and overworked.selected_horse().stress == 100, "Overtraining lowers fitness and clamps condition")
	var found_injury := false
	for seed_value: int in 50:
		var injured := _session(seed_value)
		injured.selected_horse().fatigue = 100
		injured.assign_training(injured.selected_horse_id, "hill")
		var result := injured.advance_weeks(1)
		if injured.selected_horse().injury_weeks == 2:
			check.call(result.changes[0].action.contains("부상 발생") and not injured.assign_training(injured.selected_horse_id, "hill").ok, "Training injury is reported and prevents next training")
			injured.advance_weeks(2)
			check.call(injured.selected_horse().injury_weeks == 0 and injured.assign_training(injured.selected_horse_id, "hill").ok, "Injury heals after two rest weeks and allows training again")
			found_injury = true
			break
	check.call(found_injury, "Seeded overwork scenarios exercise actual injury path")
	var capped := _session()
	capped.selected_horse().stats.values = capped.selected_horse().potential.values.duplicate()
	capped.assign_training(capped.selected_horse_id, "sprint")
	capped.advance_weeks(1)
	check.call(capped.selected_horse().stats.values == capped.selected_horse().potential.values, "Natural growth plus training never exceed potential")
	var bulk := _session()
	var single := _session()
	for item: GameSession in [bulk, single]:
		item.selected_horse().fatigue = 100
		item.assign_training(item.selected_horse_id, "sprint")
	bulk.advance_weeks(4)
	for week: int in 4:
		single.advance_weeks(1)
	check.call(_snapshot(bulk) == _snapshot(single), "Four weeks applies training once then rest; matches individual ticks including RNG")
	var ordered := _session()
	for horse: Horse in ordered.state.owned_horses():
		horse.fatigue = 100
		ordered.assign_training(horse.id, "hill")
	var reordered_data := SaveCodec.encode(ordered.state, ordered.selected_horse_id)
	reordered_data.horses.reverse()
	var reordered := GameSession.new()
	reordered.state = SaveCodec.decode(reordered_data).state
	reordered.selected_horse_id = ordered.selected_horse_id
	ordered.advance_weeks(1)
	reordered.advance_weeks(1)
	var normal_data := SaveCodec.encode(ordered.state, ordered.selected_horse_id)
	var reverse_data := SaveCodec.encode(reordered.state, reordered.selected_horse_id)
	reverse_data.horses.reverse()
	check.call(JSON.stringify(normal_data) == JSON.stringify(reverse_data), "Horse serialization order does not change training RNG outcomes")
	ordered.selected_horse().injury_weeks = 0
	ordered.assign_training(ordered.selected_horse_id, "mental")
	ordered.new_game(42)
	check.call(ordered.state.training_assignments.is_empty(), "New game resets training assignments")
	var atomic := _session()
	atomic.assign_training(atomic.selected_horse_id, "sprint")
	var before := _snapshot(atomic)
	var failure := TimeSystem.advance(atomic.state, atomic.selected_horse_id, 4, TimeSystem.RULES_PATH, "res://missing-training.json")
	check.call(not failure.ok and _snapshot(atomic) == before, "Missing training rules preserve date, plan, stats and RNG")
	var invalid_path := directory.path_join("invalid-training.json")
	var invalid_rules := rules.duplicate(true)
	invalid_rules.programs.sprint.speed = "fast"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid_rules))
	file.close()
	check.call(TrainingSystem.read_rules(invalid_path).is_empty(), "Malformed training gains are rejected")
	var fallback := _session()
	fallback.assign_training(fallback.selected_horse_id, "hill")
	fallback.selected_horse().injury_weeks = 1
	var rested_result := fallback.advance_weeks(1)
	check.call(rested_result.ok and rested_result.changes[0].action.contains("훈련 불가로 휴식") and fallback.selected_horse().injury_weeks == 0 and fallback.selected_horse().fatigue == 0, "Unavailable pending plan falls back to rest and reports why")
	var saved := _session()
	saved.saves = SaveManager.new(directory.path_join("training.json"))
	saved.selected_horse().fatigue = 100
	saved.assign_training(saved.selected_horse_id, "sprint")
	check.call(saved.save_game().ok, "Pending training can be saved before advancing")
	saved.advance_weeks(1)
	var uninterrupted := _snapshot(saved)
	var loaded := saved.load_game()
	check.call(loaded.ok and saved.state.training_assignments[saved.selected_horse_id] == "sprint", "Loading restores pending plan")
	saved.advance_weeks(1)
	check.call(_snapshot(saved) == uninterrupted, "Loaded training reproduces stat, condition, injury and RNG outcome")
	var document := SaveCodec.encode(saved.state, saved.selected_horse_id)
	for bad_plan: Variant in [[], {"horse-999": "hill"}, {saved.selected_horse_id: "unknown"}, {saved.selected_horse_id: 5}, {saved.selected_horse_id: "rest"}]:
		var bad := document.duplicate(true)
		bad.training_assignments = bad_plan
		check.call(not SaveCodec.decode(bad).ok, "Invalid stored training assignment rejected: " + str(bad_plan))
	for simulation: int in [1, 2]:
		var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json"))
		legacy.simulation_version = simulation
		var decoded := SaveCodec.decode(legacy)
		check.call(decoded.ok and decoded.state.training_assignments.is_empty(), "Legacy schema 1 migrates to unassigned rest: simulation " + str(simulation))

func _session(seed_value: int = 42) -> GameSession:
	var session := GameSession.new()
	session.new_game(seed_value)
	return session

func _snapshot(session: GameSession) -> String:
	return JSON.stringify(SaveCodec.encode(session.state, session.selected_horse_id), "", true, true)
