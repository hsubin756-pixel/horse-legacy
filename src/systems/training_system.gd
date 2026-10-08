class_name TrainingSystem
extends RefCounted

const RULES_PATH: String = "res://data/rules/training_rules.json"
const PROGRAMS: Array[String] = ["rest", "sprint", "endurance", "hill", "mental"]
const LABELS: Array[String] = ["휴식", "단거리 훈련", "지구력 훈련", "언덕 훈련", "정신 훈련"]

static func label_for(program: String) -> String:
	var index := PROGRAMS.find(program)
	return LABELS[index] if index >= 0 else "알 수 없는 훈련"

static func unavailable_reason(horse: Horse) -> String:
	if horse.life_stage != Horse.LifeStage.ADULT:
		return "성마만 훈련할 수 있습니다."
	if horse.career_status == Horse.CareerStatus.RETIRED:
		return "은퇴마는 휴식합니다."
	if horse.injury_weeks > 0:
		return "부상 회복 중에는 휴식이 필요합니다."
	return ""

static func read_rules(path: String = RULES_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		return {}
	for key: String in ["fatigue_gain", "stress_gain", "fitness_gain", "overwork_fitness_loss"]:
		if not SaveSchema.number(parsed.get(key), 0, 100):
			return {}
	if not SaveSchema.number(parsed.get("overwork_threshold"), 1, 99) or not SaveSchema.number(parsed.get("injury_max_chance"), 0, 1):
		return {}
	if not SaveSchema.number(parsed.get("injury_weeks"), 1, 52, true) or not parsed.get("programs") is Dictionary:
		return {}
	for program: String in PROGRAMS.slice(1):
		var gains: Variant = parsed.programs.get(program)
		if not gains is Dictionary or gains.is_empty():
			return {}
		for key: Variant in gains:
			if not key is String or not StringName(key) in StatBlock.KEYS or not SaveSchema.number(gains[key], 0, 10):
				return {}
	return parsed

static func efficiency(horse: Horse) -> float:
	return maxf(0.1, 1.0 - horse.fatigue * 0.006 - horse.stress * 0.004)

static func injury_chance(horse: Horse, rules: Dictionary) -> float:
	if horse.fatigue < rules.overwork_threshold:
		return 0.0
	return float(rules.injury_max_chance) * (horse.fatigue - rules.overwork_threshold + 1.0) / (101.0 - rules.overwork_threshold)

# Called instead of rest, using condition before this week's action.
static func apply(horse: Horse, program: String, rules: Dictionary, rng: RandomNumberGenerator) -> bool:
	var multiplier := efficiency(horse)
	var risk := injury_chance(horse, rules)
	for key: String in rules.programs[program]:
		horse.stats.values[StringName(key)] = minf(horse.potential.values[StringName(key)], horse.stats.values[StringName(key)] + float(rules.programs[program][key]) * multiplier)
	var overworked: bool = horse.fatigue >= rules.overwork_threshold
	horse.fitness = clampf(horse.fitness + (-float(rules.overwork_fitness_loss) if overworked else float(rules.fitness_gain)), 0.0, 100.0)
	horse.fatigue = minf(100.0, horse.fatigue + rules.fatigue_gain)
	horse.stress = minf(100.0, horse.stress + rules.stress_gain)
	var injured: bool = risk > 0.0 and rng.randf() < risk
	if injured:
		horse.injury_weeks = int(rules.injury_weeks)
	return injured
