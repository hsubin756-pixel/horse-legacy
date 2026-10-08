class_name SaveSchema
extends RefCounted

# Numeric JSON fields must survive double-precision parsing without rounding.
const MAX_INTEGER: int = 9007199254740991
const MAX_HORSES: int = 10000
const HORSE_STRINGS: Array[String] = ["id", "name", "father_id", "mother_id", "breeder_farm_id", "owner_farm_id", "growth_type"]
const HORSE_INTS: Array[String] = ["sex", "birth_week", "life_stage", "career_status", "injury_weeks", "starts", "wins", "earnings"]
const CONDITION_FIELDS: Array[String] = ["fitness", "fatigue", "stress"]

static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "저장 데이터가 올바른 객체 형식이 아닙니다."
	var d: Dictionary = value
	if not number(d.get("schema_version"), 1, MAX_INTEGER, true):
		return "저장 형식 버전이 없거나 잘못되었습니다."
	if d.schema_version != GameState.SCHEMA_VERSION:
		return "지원하지 않는 저장 형식 버전입니다. 파일을 변경하지 않았습니다."
	# Version 1 predates weekly simulation; its state requires no field conversion.
	if not number(d.get("simulation_version"), 1, GameState.SIMULATION_VERSION, true):
		return "지원하지 않는 시뮬레이션 버전입니다."
	if not exact_keys(d, ["schema_version", "simulation_version", "current_week", "next_id", "rng_seed", "rng_state", "selected_horse_id", "farm", "horses"]):
		return "저장 파일에 필수 항목이 없거나 알 수 없는 항목이 있습니다."
	if not number(d.current_week, 0, MAX_INTEGER, true) or not number(d.next_id, 1, MAX_INTEGER, true):
		return "날짜 또는 다음 ID가 잘못되었습니다."
	if not int_string(d.rng_seed) or not int_string(d.rng_state):
		return "난수 상태가 손상되었습니다."
	if not d.farm is Dictionary or not d.horses is Array or d.horses.size() > MAX_HORSES:
		return "목장 또는 말 목록이 잘못되었습니다."
	var farm: Dictionary = d.farm
	if not exact_keys(farm, ["id", "name", "horse_ids", "money", "reputation"]):
		return "목장 정보의 항목이 잘못되었습니다."
	var farm_number: int = id_number(farm.id, "farm")
	if farm_number < 1 or not text(farm.name, false):
		return "목장 ID 또는 이름이 잘못되었습니다."
	if not number(farm.money, 0, MAX_INTEGER, true) or not number(farm.reputation, 0, MAX_INTEGER, true):
		return "목장 자금 또는 명성이 잘못되었습니다."
	if not farm.horse_ids is Array or farm.horse_ids.is_empty():
		return "보유 말 목록이 없거나 잘못되었습니다."
	var owned: Dictionary = {}
	for horse_id: Variant in farm.horse_ids:
		if not horse_id is String or owned.has(horse_id):
			return "보유 말 ID가 잘못되었거나 중복되었습니다."
		owned[horse_id] = true
	if not d.selected_horse_id is String or not owned.has(d.selected_horse_id):
		return "선택한 말이 보유 말 목록에 없습니다."
	var horses: Dictionary = {}
	var largest_id: int = farm_number
	for entry: Variant in d.horses:
		var reason := validate_horse(entry, int(d.current_week), farm.id)
		if not reason.is_empty():
			return reason
		var h: Dictionary = entry
		if horses.has(h.id):
			return "말 ID가 중복되었습니다."
		horses[h.id] = h
		largest_id = maxi(largest_id, id_number(h.id, "horse"))
		if (h.owner_farm_id == farm.id) != owned.has(h.id):
			return "말의 소유권과 목장 목록이 일치하지 않습니다."
	if int(d.next_id) <= largest_id:
		return "다음 ID가 기존 기록과 충돌합니다."
	for horse_id: String in owned:
		if not horses.has(horse_id):
			return "보유 말의 상세 기록이 없습니다."
	for h: Dictionary in horses.values():
		for field: String in ["father_id", "mother_id"]:
			var parent_id: String = h[field]
			if parent_id.is_empty():
				continue
			if not horses.has(parent_id):
				return "부모의 기록을 찾을 수 없습니다."
			var parent: Dictionary = horses[parent_id]
			var expected_sex: int = Horse.Sex.MALE if field == "father_id" else Horse.Sex.FEMALE
			# Strictly increasing birth weeks also prohibit cycles, without recursive traversal.
			if parent.sex != expected_sex or parent.birth_week >= h.birth_week:
				return "부모의 성별·생년 또는 혈통 연결이 잘못되었습니다."
	return ""

static func validate_horse(value: Variant, current_week: int, farm_id: String) -> String:
	if not value is Dictionary:
		return "말 정보가 올바른 객체 형식이 아닙니다."
	var h: Dictionary = value
	var fields: Array = []
	fields.append_array(HORSE_STRINGS)
	fields.append_array(HORSE_INTS)
	fields.append_array(CONDITION_FIELDS)
	fields.append_array(["stats", "potential", "race_result_ids"])
	if not exact_keys(h, fields):
		return "말 정보에 필수 항목이 없거나 알 수 없는 항목이 있습니다."
	for key: String in HORSE_STRINGS:
		if not text(h[key], key != "id" and key != "name" and key != "growth_type"):
			return "말의 이름 또는 참조 ID가 잘못되었습니다."
	if id_number(h.id, "horse") < 1:
		return "말 ID 형식이 잘못되었습니다."
	if not h.growth_type in ["early", "normal", "late"]:
		return "성장 타입이 잘못되었습니다."
	if not h.owner_farm_id in ["", farm_id] or not h.breeder_farm_id in ["", farm_id]:
		return "참조하는 목장 기록이 없습니다."
	for key: String in HORSE_INTS:
		var minimum: int = -MAX_INTEGER if key == "birth_week" else 0
		if not number(h[key], minimum, MAX_INTEGER, true):
			return "말의 정수 정보가 손상되었습니다."
	if h.birth_week > current_week or not number(h.sex, 0, 1, true) or not number(h.life_stage, 0, 2, true) or not number(h.career_status, 0, 2, true):
		return "말의 생년·성별·상태가 잘못되었습니다."
	for key: String in CONDITION_FIELDS:
		if not number(h[key], 0, 100):
			return "말의 컨디션 값이 범위를 벗어났습니다."
	if not h.stats is Array or not h.potential is Array:
		return "능력 정보가 배열 형식이 아닙니다."
	var stats := StatBlock.from_array(h.stats)
	var potential := StatBlock.from_array(h.potential)
	if stats == null or potential == null:
		return "능력 정보가 누락되었거나 범위를 벗어났습니다."
	for key: StringName in StatBlock.KEYS:
		if stats.values[key] > potential.values[key]:
			return "현재 능력이 잠재 능력을 초과합니다."
	# Schema 1 predates racing. Never silently accept dangling result IDs.
	if not h.race_result_ids is Array or not h.race_result_ids.is_empty() or h.starts != 0 or h.wins != 0 or h.earnings != 0:
		return "이 저장 형식은 아직 경주 전적을 지원하지 않습니다."
	return ""

static func number(value: Variant, minimum: int, maximum: int, integer: bool = false) -> bool:
	if not (value is int or value is float):
		return false
	var n: float = float(value)
	return is_finite(n) and n >= minimum and n <= maximum and (not integer or n == floorf(n))

static func text(value: Variant, allow_empty: bool) -> bool:
	return value is String and value.length() <= 128 and (allow_empty or not value.strip_edges().is_empty())

static func int_string(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value

static func id_number(value: Variant, prefix: String) -> int:
	if not value is String or not value.begins_with(prefix + "-"):
		return -1
	var suffix: String = value.trim_prefix(prefix + "-")
	if not int_string(suffix) or suffix.to_int() < 1 or suffix.to_int() >= MAX_INTEGER:
		return -1
	return suffix.to_int()

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true
