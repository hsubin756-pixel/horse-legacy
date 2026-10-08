class_name TimeSystem
extends RefCounted

const RULES_PATH: String = "res://data/rules/time_rules.json"

static func read_rules(path: String = RULES_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	if not SaveSchema.number(parsed.get("adult_age_years"), 1, 10, true):
		return {}
	for key: String in ["rest_fitness", "rest_fatigue", "rest_stress", "growth_fatigue_limit", "weekly_decline"]:
		if not SaveSchema.number(parsed.get(key), 0, 100):
			return {}
	if not parsed.get("growth") is Dictionary:
		return {}
	for kind: String in ["early", "normal", "late"]:
		var profile: Variant = parsed.growth.get(kind)
		if not profile is Dictionary:
			return {}
		if not SaveSchema.number(profile.get("growth_until"), 1, 20, true) or not SaveSchema.number(profile.get("decline_from"), 1, 30, true):
			return {}
		if profile.decline_from < profile.growth_until or not SaveSchema.number(profile.get("weekly_gain"), 0, 1):
			return {}
	return parsed

static func advance(state: GameState, selected_id: String, weeks: int, rules_path: String = RULES_PATH) -> Dictionary:
	if state == null:
		return {"ok": false, "message": "먼저 새 게임을 시작하거나 저장한 목장을 불러와 주세요."}
	if weeks < 1 or weeks > 52 or state.current_week > SaveSchema.MAX_INTEGER - weeks:
		return {"ok": false, "message": "한 번에 진행할 수 있는 기간은 1~52주입니다."}
	var rules := read_rules(rules_path)
	if rules.is_empty():
		return {"ok": false, "message": "주간 진행 규칙을 읽을 수 없습니다. 프로젝트 파일을 확인해 주세요."}
	# Calculate on an independent, validated state; commit only once the whole action succeeds.
	var candidate := SaveCodec.decode(SaveCodec.encode(state, selected_id))
	if not candidate.ok:
		return {"ok": false, "message": candidate.message}
	for step: int in weeks:
		candidate.state.current_week += 1
		for horse: Horse in candidate.state.horses.values():
			_tick_horse(horse, candidate.state.current_week, rules)
	var changes: Array[Dictionary] = []
	for horse: Horse in candidate.state.owned_horses():
		var previous: Horse = state.horses[horse.id]
		var gains: Dictionary = {}
		for key: StringName in StatBlock.KEYS:
			gains[key] = horse.stats.values[key] - previous.stats.values[key]
		changes.append({"horse_id": horse.id, "name": horse.name, "stats": gains,
			"age_before": previous.age_years(state.current_week), "age_after": horse.age_years(candidate.state.current_week),
			"matured": previous.life_stage == Horse.LifeStage.FOAL and horse.life_stage == Horse.LifeStage.ADULT,
			"healed": previous.injury_weeks > 0 and horse.injury_weeks == 0,
			"fitness": horse.fitness - previous.fitness, "fatigue": horse.fatigue - previous.fatigue,
			"stress": horse.stress - previous.stress})
	return {"ok": true, "message": "%d주가 지났습니다. 저장하지 않은 변경이 있습니다." % weeks,
		"state": candidate.state, "weeks": weeks, "changes": changes}

static func _tick_horse(horse: Horse, week: int, rules: Dictionary) -> void:
	if horse.life_stage == Horse.LifeStage.DECEASED:
		return
	var age: int = horse.age_years(week)
	var profile: Dictionary = rules.growth[str(horse.growth_type)]
	# Use the condition at the beginning of this week for growth eligibility.
	var can_grow: bool = horse.injury_weeks == 0 and horse.fatigue < rules.growth_fatigue_limit
	for key: StringName in StatBlock.KEYS:
		var delta: float = 0.0
		if age < profile.growth_until and can_grow:
			delta = profile.weekly_gain
		elif age >= profile.decline_from:
			delta = -float(rules.weekly_decline)
		horse.stats.values[key] = clampf(horse.stats.values[key] + delta, 0.0, horse.potential.values[key])
	# Unassigned horses rest. Training and racing actions are added in later steps.
	horse.fitness = minf(100.0, horse.fitness + rules.rest_fitness)
	horse.fatigue = maxf(0.0, horse.fatigue - rules.rest_fatigue)
	horse.stress = maxf(0.0, horse.stress - rules.rest_stress)
	horse.injury_weeks = maxi(0, horse.injury_weeks - 1)
	if horse.life_stage == Horse.LifeStage.FOAL and age >= rules.adult_age_years:
		horse.life_stage = Horse.LifeStage.ADULT
