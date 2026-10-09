extends RefCounted

func run(check: Callable, directory: String) -> void:
	var session := _session()
	var rules := RaceSystem.read_rules()
	var entrants := RaceSystem.entrants_for(session.selected_horse(), rules)
	var original_inputs := JSON.stringify(entrants)
	var simulation := RaceSimulator.simulate(entrants, 1600, 71)
	check.call(simulation.ok and simulation.finishers.size() == 4 and simulation.frames.size() > 100, "Four runners finish a tick-based race with movement frames")
	if not simulation.ok: return
	check.call(JSON.stringify(simulation) == JSON.stringify(RaceSimulator.simulate(entrants, 1600, 71)) and JSON.stringify(entrants) == original_inputs, "Same race inputs and seed reproduce all frames without input mutation")
	entrants.reverse()
	check.call(JSON.stringify(simulation) == JSON.stringify(RaceSimulator.simulate(entrants, 1600, 71)), "Gate order makes race independent of input array order")
	entrants.reverse()
	var phases: Dictionary = {}
	var monotonic := true
	var previous := 0.0
	for frame: Dictionary in simulation.frames:
		var runner: Dictionary = frame.runners[0]
		phases[runner.phase] = true
		monotonic = monotonic and runner.distance >= previous and runner.distance <= 1600 and runner.stamina >= 0
		previous = runner.distance
	check.call(monotonic and phases.size() == 6 and previous == 1600, "Race crosses all six phases with bounded monotonic distance and stamina")
	var sorted := true
	var interpolated := false
	previous = 0.0
	for entry: Dictionary in simulation.finishers:
		sorted = sorted and entry.finish_usec >= previous
		previous = entry.finish_usec
		interpolated = interpolated or int(entry.finish_usec) % 250000 != 0
	check.call(sorted and interpolated, "Finish order uses interpolated crossing times within simulation ticks")
	var base_time := _time_for(simulation, 1)
	var strong := entrants.duplicate(true)
	strong[0].stats[0] = 95
	check.call(_time_for(RaceSimulator.simulate(strong, 1600, 71), 1) < base_time, "Higher speed improves finish time with fixed opponents and seed")
	var tired := entrants.duplicate(true)
	tired[0].fatigue = 95
	tired[0].stress = 70
	check.call(_time_for(RaceSimulator.simulate(tired, 1600, 71), 1) > base_time, "Fatigue and stress reduce race performance")
	var low_stamina := entrants.duplicate(true)
	var high_stamina := entrants.duplicate(true)
	low_stamina[0].stats[1] = 0
	high_stamina[0].stats[1] = 100
	check.call(_time_for(RaceSimulator.simulate(low_stamina, 2400, 71), 1) > _time_for(RaceSimulator.simulate(high_stamina, 2400, 71), 1), "Stamina depletion creates a measurable late-race slowdown")
	check.call(not RaceSimulator.simulate([], 1600, 1).ok and not RaceSimulator.simulate(entrants, 0, 1).ok, "Invalid race sizes and distances are rejected")
	var bad_entrants := entrants.duplicate(true)
	bad_entrants[0].stats[0] = NAN
	check.call(not RaceSimulator.simulate(bad_entrants, 1600, 1).ok, "Nonfinite race stats cannot enter simulation")
	var before := _snapshot(session)
	check.call(not session.enter_race("horse-999", 0).ok and not RaceSystem.run(session.state, session.selected_horse_id, session.selected_horse_id, "res://missing-race.json").ok and _snapshot(session) == before, "Invalid entry/config leaves time, state and RNG unchanged")
	for status: String in ["injury", "retired", "foal", "young", "dead"]:
		var invalid := _session()
		var horse := invalid.selected_horse()
		match status:
			"injury": horse.injury_weeks = 1
			"retired": horse.career_status = Horse.CareerStatus.RETIRED
			"foal": horse.life_stage = Horse.LifeStage.FOAL
			"young": horse.birth_week = -52
			"dead": horse.life_stage = Horse.LifeStage.DECEASED
		before = _snapshot(invalid)
		check.call(not invalid.enter_race(horse.id, 0).ok and _snapshot(invalid) == before, "Ineligible race entry is atomic: " + status)
	var first_id := session.selected_horse_id
	var second_id: String = session.state.player_farm.horse_ids[1]
	session.assign_training(first_id, "sprint")
	session.assign_training(second_id, "mental")
	var speed: float = session.selected_horse().stats.values[&"speed"]
	var second_spirit: float = session.state.horses[second_id].stats.values[&"spirit"]
	var money: int = session.state.player_farm.money
	var reentrant: Array[bool] = []
	var on_race := func(_r: Dictionary) -> void: reentrant.append(session.enter_race(first_id, session.state.current_week).ok)
	session.race_finished.connect(on_race)
	var result := session.enter_race(first_id, 0)
	session.race_finished.disconnect(on_race)
	check.call(result.ok, "Race entry completes and commits a valid game")
	if not result.ok:
		print(result.message)
		return
	check.call(session.state.current_week == 1 and session.selected_horse().starts == 1 and session.selected_horse().career_status == Horse.CareerStatus.ACTIVE, "Race spends one week and records career start")
	check.call(is_equal_approx(session.selected_horse().stats.values[&"speed"], speed + 0.1) and session.selected_horse().fatigue == 30 and session.selected_horse().fitness == 72, "Race replaces own training and receives no simultaneous rest recovery")
	check.call(session.state.horses[second_id].stats.values[&"spirit"] > second_spirit + 0.5 and session.state.training_assignments.is_empty(), "Other horse carries out its weekly training during race entry")
	var award := 0
	var won := false
	for rank: int in result.record.finishers.size():
		if result.record.finishers[rank].horse_id == first_id:
			award = int(result.record.finishers[rank].prize)
			won = rank == 0
	check.call(session.selected_horse().earnings == award and session.state.player_farm.money == money + award and session.selected_horse().wins == int(won), "Prize, win and farm balance match actual finishing rank")
	before = _snapshot(session)
	check.call(not session.enter_race(first_id, 0).ok and reentrant == [false] and not RaceSystem.apply_result(session.state, result.record).ok and _snapshot(session) == before, "Stale/reentrant entry and duplicate result cannot spend another week or pay twice")
	var overflow := _session()
	overflow.state.player_farm.money = SaveSchema.MAX_INTEGER
	for key: StringName in StatBlock.KEYS:
		overflow.selected_horse().stats.values[key] = 100
		overflow.selected_horse().potential.values[key] = 100
	before = _snapshot(overflow)
	check.call(not overflow.enter_race(overflow.selected_horse_id, 0).ok and _snapshot(overflow) == before, "Reward overflow rejects the whole race without spending time or RNG")
	session.saves = SaveManager.new(directory.path_join("racing.json"))
	check.call(session.save_game().ok, "Race history and career save successfully")
	var saved_snapshot := _snapshot(session)
	var next := session.enter_race(first_id, 1)
	var uninterrupted := _snapshot(session)
	check.call(session.load_game().ok and _snapshot(session) == saved_snapshot, "Loading race history does not repay prizes or alter careers")
	var resumed := session.enter_race(first_id, 1)
	check.call(next.ok and resumed.ok and _snapshot(session) == uninterrupted and JSON.stringify(next.frames) == JSON.stringify(resumed.frames), "Next race after load reproduces the full simulation and state")
	check.call(session.advance_weeks(4).ok and session.save_game().ok and session.load_game().ok, "Training/time/save flow remains usable after multiple races")
	var document := SaveCodec.encode(session.state, first_id)
	var mutations := {
		"duplicate result": func(d: Dictionary) -> void: d.race_results.append(d.race_results[0].duplicate(true)),
		"future race": func(d: Dictionary) -> void: d.race_results[0].week = d.current_week + 1,
		"unknown runner": func(d: Dictionary) -> void: d.race_results[0].finishers[0].horse_id = "horse-999",
		"bad placing": func(d: Dictionary) -> void: d.race_results[0].finishers.reverse(),
		"career mismatch": func(d: Dictionary) -> void: d.horses[0].starts += 1,
		"negative prize": func(d: Dictionary) -> void: d.race_results[0].finishers[0].prize = -1,
		"missing history": func(d: Dictionary) -> void: d.erase("race_results"),
		"race ID collision": func(d: Dictionary) -> void: d.next_id = int(d.race_results.back().id.trim_prefix("race-")),
	}
	for label: String in mutations:
		var bad := document.duplicate(true)
		mutations[label].call(bad)
		check.call(not SaveCodec.decode(bad).ok, "Invalid race save rejected: " + label)
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json"))
	legacy.schema_version = 2
	legacy.simulation_version = 3
	legacy.training_assignments = {legacy.selected_horse_id: "mental"}
	var decoded := SaveCodec.decode(legacy)
	check.call(decoded.ok and decoded.state.race_results.is_empty() and decoded.state.training_assignments[legacy.selected_horse_id] == "mental", "Schema 2 upgrades to empty race history while preserving pending training")

func _session() -> GameSession:
	var session := GameSession.new()
	session.new_game(71)
	return session

func _snapshot(session: GameSession) -> String:
	return JSON.stringify(SaveCodec.encode(session.state, session.selected_horse_id), "", true, true)

func _time_for(result: Dictionary, gate: int) -> float:
	for entry: Dictionary in result.finishers:
		if entry.gate == gate: return entry.finish_usec / 1000000.0
	return INF
