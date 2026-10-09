class_name RaceRecord
extends RefCounted

const ENTRANT_KEYS: Array[String] = ["gate", "horse_id", "name", "stats", "fitness", "fatigue", "stress"]
const MAX_RESULTS: int = 10000

static func decode(data: Dictionary) -> Dictionary:
	var record := data.duplicate(true)
	for key: String in ["week", "distance", "version"]: record[key] = int(record[key])
	for entry: Dictionary in record.finishers:
		for key: String in ["gate", "finish_usec", "remaining_stamina_milli", "prize"]: entry[key] = int(entry[key])
		for key: String in ["fitness", "fatigue", "stress"]: entry[key] = float(entry[key])
		for index: int in entry.stats.size(): entry.stats[index] = float(entry.stats[index])
	return record

static func valid_entrant(entry: Dictionary) -> bool:
	for key: String in ENTRANT_KEYS:
		if not entry.has(key): return false
	if not SaveSchema.number(entry.gate, 1, 12, true) or not SaveSchema.text(entry.horse_id, true) or not SaveSchema.text(entry.name, false): return false
	if not entry.stats is Array or StatBlock.from_array(entry.stats) == null: return false
	for key: String in ["fitness", "fatigue", "stress"]:
		if not SaveSchema.number(entry[key], 0, 100): return false
	return true

static func validate(record: Variant, horses: Dictionary, current_week: int) -> String:
	if not record is Dictionary: return "경주 기록 형식이 잘못되었습니다."
	if not SaveSchema.exact_keys(record, ["id", "week", "title", "distance", "seed", "version", "finishers"]): return "경주 기록 항목이 잘못되었습니다."
	if SaveSchema.id_number(record.id, "race") < 1 or not SaveSchema.number(record.week, 1, current_week, true): return "경주 ID 또는 날짜가 잘못되었습니다."
	if not SaveSchema.text(record.title, false) or not SaveSchema.number(record.distance, 800, 4000, true) or not SaveSchema.int_string(record.seed) or not SaveSchema.number(record.version, 1, 1, true): return "경주 설정이 잘못되었습니다."
	if not record.finishers is Array or record.finishers.size() < 2 or record.finishers.size() > 12: return "경주 착순이 잘못되었습니다."
	var gates: Dictionary = {}
	var horse_ids: Dictionary = {}
	var previous_time: int = 0
	var previous_gate: int = 0
	for entry: Variant in record.finishers:
		if not entry is Dictionary or not valid_entrant(entry): return "경주 참가 기록이 잘못되었습니다."
		var fields: Array = ENTRANT_KEYS.duplicate()
		fields.append_array(["finish_usec", "remaining_stamina_milli", "prize"])
		if not SaveSchema.exact_keys(entry, fields) or gates.has(entry.gate): return "경주 참가 기록이 중복되거나 손상되었습니다."
		gates[entry.gate] = true
		if not SaveSchema.number(entry.finish_usec, 1, 1200000000, true) or not SaveSchema.number(entry.remaining_stamina_milli, 0, 120000, true) or not SaveSchema.number(entry.prize, 0, 1000000, true): return "경주 시간·상금·스태미나가 잘못되었습니다."
		if entry.finish_usec < previous_time or (entry.finish_usec == previous_time and entry.gate < previous_gate): return "경주 착순과 결승 시각이 일치하지 않습니다."
		previous_time = int(entry.finish_usec)
		previous_gate = int(entry.gate)
		if not entry.horse_id.is_empty():
			if not horses.has(entry.horse_id) or horse_ids.has(entry.horse_id): return "경주마 참조가 없거나 중복되었습니다."
			horse_ids[entry.horse_id] = true
	if horse_ids.is_empty(): return "경주 기록에 목장의 말이 없습니다."
	return ""

static func validate_history(records: Variant, horses: Dictionary, week: int, next_id: int) -> String:
	if not records is Array or records.size() > MAX_RESULTS: return "경주 기록 목록이 잘못되었습니다."
	var ids: Dictionary = {}
	var totals: Dictionary = {}
	for horse_id: String in horses:
		totals[horse_id] = {"ids": [], "wins": 0, "earnings": 0, "weeks": {}}
	for record: Variant in records:
		var reason := validate(record, horses, week)
		if not reason.is_empty(): return reason
		if ids.has(record.id) or SaveSchema.id_number(record.id, "race") >= next_id: return "경주 ID가 중복되거나 다음 ID와 충돌합니다."
		ids[record.id] = true
		for rank: int in record.finishers.size():
			var entry: Dictionary = record.finishers[rank]
			if entry.horse_id.is_empty(): continue
			var total: Dictionary = totals[entry.horse_id]
			if total.weeks.has(record.week): return "한 말이 같은 주에 두 번 경주했습니다."
			total.weeks[record.week] = true
			total.ids.append(record.id)
			total.wins += 1 if rank == 0 else 0
			total.earnings += int(entry.prize)
	for horse_id: String in horses:
		var horse: Dictionary = horses[horse_id]
		var total: Dictionary = totals[horse_id]
		if horse.race_result_ids != total.ids or horse.starts != total.ids.size() or horse.wins != total.wins or horse.earnings != total.earnings: return "말의 전적과 경주 기록이 일치하지 않습니다."
		if horse.starts > 0 and horse.career_status == Horse.CareerStatus.UNRACED: return "경주한 말의 경력 상태가 잘못되었습니다."
	return ""
