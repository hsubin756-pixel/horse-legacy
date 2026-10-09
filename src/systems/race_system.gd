class_name RaceSystem
extends RefCounted

const RULES_PATH: String = "res://data/rules/local_race.json"

static func read_rules(path: String = RULES_PATH) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not data is Dictionary: return {}
	if not SaveSchema.text(data.get("title"), false) or not SaveSchema.number(data.get("distance"), 800, 4000, true): return {}
	if not data.get("rivals") is Array or data.rivals.size() != 3 or not data.get("prizes") is Array or data.prizes.size() != 4: return {}
	for prize: Variant in data.prizes:
		if not SaveSchema.number(prize, 0, 1000000, true): return {}
	for key: String in ["fatigue_gain", "stress_gain", "fitness_loss"]:
		if not SaveSchema.number(data.get(key), 0, 100): return {}
	for rival: Variant in data.rivals:
		if not rival is Dictionary or not SaveSchema.text(rival.get("name"), false) or not rival.get("stats") is Array or StatBlock.from_array(rival.stats) == null: return {}
	return data

static func unavailable_reason(horse: Horse, week: int) -> String:
	if horse.life_stage != Horse.LifeStage.ADULT or horse.age_years(week) < 3: return "3세 이상 성마만 출전할 수 있습니다."
	if horse.career_status == Horse.CareerStatus.RETIRED: return "은퇴마는 출전할 수 없습니다."
	if horse.injury_weeks > 0: return "부상 회복 후 출전할 수 있습니다."
	return ""

static func entrants_for(horse: Horse, rules: Dictionary) -> Array:
	var stats: Array = []
	for key: StringName in StatBlock.KEYS: stats.append(horse.stats.values[key])
	var entrants: Array = [{"gate": 1, "horse_id": horse.id, "name": horse.name, "stats": stats, "fitness": horse.fitness, "fatigue": horse.fatigue, "stress": horse.stress}]
	for rival: Dictionary in rules.rivals:
		entrants.append({"gate": entrants.size() + 1, "horse_id": "", "name": rival.name, "stats": rival.stats.duplicate(), "fitness": 80.0, "fatigue": 0.0, "stress": 0.0})
	return entrants

static func run(state: GameState, selected_id: String, horse_id: String, path: String = RULES_PATH) -> Dictionary:
	if state == null or not state.player_farm.horse_ids.has(horse_id): return {"ok": false, "message": "보유 말을 선택해 주세요."}
	var reason := unavailable_reason(state.horses[horse_id], state.current_week)
	if not reason.is_empty(): return {"ok": false, "message": reason}
	var rules := read_rules(path)
	if rules.is_empty(): return {"ok": false, "message": "경주 설정을 읽을 수 없습니다."}
	var copy := SaveCodec.decode(SaveCodec.encode(state, selected_id))
	if not copy.ok: return {"ok": false, "message": copy.message}
	if copy.state.race_results.size() >= RaceRecord.MAX_RESULTS or copy.state.next_id >= SaveSchema.MAX_INTEGER - 1: return {"ok": false, "message": "경주 기록 저장 한도에 도달했습니다."}
	var seed_value: int = copy.state.rng.randi()
	var simulation := RaceSimulator.simulate(entrants_for(copy.state.horses[horse_id], rules), int(rules.distance), seed_value)
	if not simulation.ok: return simulation
	copy.state.training_assignments.erase(horse_id)
	var weekly := TimeSystem.advance(copy.state, selected_id, 1, TimeSystem.RULES_PATH, TrainingSystem.RULES_PATH, [horse_id])
	if not weekly.ok: return weekly
	var candidate: GameState = weekly.state
	var record: Dictionary = {"id": candidate.allocate_id("race"), "week": candidate.current_week, "title": rules.title, "distance": int(rules.distance), "seed": str(seed_value), "version": RaceSimulator.VERSION, "finishers": simulation.finishers}
	for rank: int in record.finishers.size(): record.finishers[rank].prize = int(rules.prizes[rank])
	var applied := apply_result(candidate, record)
	if not applied.ok: return applied
	var horse: Horse = candidate.horses[horse_id]
	horse.fatigue = minf(100.0, horse.fatigue + rules.fatigue_gain)
	horse.stress = minf(100.0, horse.stress + rules.stress_gain)
	horse.fitness = maxf(0.0, horse.fitness - rules.fitness_loss)
	var verified := SaveCodec.decode(SaveCodec.encode(candidate, selected_id))
	if not verified.ok: return {"ok": false, "message": verified.message}
	return {"ok": true, "message": "경주 결과와 상금을 반영했습니다. 1주가 지났습니다. 저장하지 않은 변경이 있습니다.", "state": candidate, "record": record.duplicate(true), "frames": simulation.frames}

# Validate every reference and amount before changing any career or balance.
static func apply_result(state: GameState, record: Dictionary) -> Dictionary:
	if state.race_results.size() >= RaceRecord.MAX_RESULTS: return {"ok": false, "message": "경주 기록 한도에 도달했습니다."}
	for existing: Dictionary in state.race_results:
		if existing.id == record.get("id"): return {"ok": false, "message": "이미 반영된 경주 결과입니다."}
	var reason := RaceRecord.validate(record, state.horses, state.current_week)
	if not reason.is_empty(): return {"ok": false, "message": reason}
	if int(record.week) != state.current_week or SaveSchema.id_number(record.id, "race") >= state.next_id: return {"ok": false, "message": "경주 날짜 또는 ID가 현재 상태와 일치하지 않습니다."}
	var reward: int = 0
	for entry: Dictionary in record.finishers:
		if entry.horse_id.is_empty(): continue
		if not state.player_farm.horse_ids.has(entry.horse_id): return {"ok": false, "message": "보유하지 않은 말의 결과입니다."}
		var horse: Horse = state.horses[entry.horse_id]
		var unavailable := unavailable_reason(horse, state.current_week)
		if not unavailable.is_empty(): return {"ok": false, "message": unavailable}
		if horse.earnings > SaveSchema.MAX_INTEGER - int(entry.prize) or horse.starts >= SaveSchema.MAX_INTEGER: return {"ok": false, "message": "경력 기록 한도에 도달했습니다."}
		for previous: Dictionary in state.race_results:
			if previous.week != record.week: continue
			for finisher: Dictionary in previous.finishers:
				if finisher.horse_id == horse.id: return {"ok": false, "message": "같은 주에 이미 경주한 말입니다."}
		reward += int(entry.prize)
	if state.player_farm.money > SaveSchema.MAX_INTEGER - reward: return {"ok": false, "message": "목장 자금 한도에 도달했습니다."}
	for rank: int in record.finishers.size():
		var entry: Dictionary = record.finishers[rank]
		if entry.horse_id.is_empty(): continue
		var horse: Horse = state.horses[entry.horse_id]
		horse.starts += 1
		horse.wins += 1 if rank == 0 else 0
		horse.earnings += int(entry.prize)
		horse.career_status = Horse.CareerStatus.ACTIVE
		horse.race_result_ids.append(record.id)
	state.player_farm.money += reward
	state.race_results.append(record.duplicate(true))
	return {"ok": true}
