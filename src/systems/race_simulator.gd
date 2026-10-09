class_name RaceSimulator
extends RefCounted

const STEP: float = 0.25
const VERSION: int = 1

static func phase(progress: float) -> String:
	if progress >= 1.0: return "FINISH"
	if progress < 0.03: return "START"
	if progress < 0.25: return "EARLY"
	if progress < 0.65: return "MIDDLE"
	if progress < 0.8: return "FINAL TURN"
	return "FINAL STRAIGHT"

# Inputs and frames are plain data; no nodes, rendering clock or live state mutation.
static func simulate(entrants: Array, distance: int, seed_value: int) -> Dictionary:
	if entrants.size() < 2 or entrants.size() > 12 or distance < 800 or distance > 4000:
		return {"ok": false, "message": "경주 거리 또는 참가 수가 잘못되었습니다."}
	var runners: Array[Dictionary] = []
	var gates: Dictionary = {}
	for entry: Variant in entrants:
		if not entry is Dictionary or not RaceRecord.valid_entrant(entry) or gates.has(entry.gate):
			return {"ok": false, "message": "경주 참가 데이터가 잘못되었습니다."}
		gates[entry.gate] = true
		runners.append(entry.duplicate(true))
	runners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.gate < b.gate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for runner: Dictionary in runners:
		runner.position = 0.0
		runner.velocity = 0.0
		runner.energy = 40.0 + runner.stats[1] * 0.8
		runner.finish_time = 0.0
		runner.form = rng.randf_range(0.99, 1.01)
	var frames: Array[Dictionary] = [_frame(0.0, runners, distance)]
	var finished := 0
	for tick: int in 4800:
		for runner: Dictionary in runners:
			if runner.finish_time > 0.0: continue
			var stats: Array = runner.stats
			var condition := clampf(0.7 + runner.fitness * 0.003 - runner.fatigue * 0.002 - runner.stress * 0.001, 0.4, 1.0)
			var segment := phase(runner.position / distance)
			var target: float = (12.0 + stats[0] * 0.085) * condition * runner.form
			if segment == "FINAL TURN": target *= 0.9 + stats[3] * 0.001
			if segment == "FINAL STRAIGHT": target *= 1.0 + stats[4] * 0.001
			if runner.energy <= 0.0: target *= 0.65 + stats[4] * 0.001
			runner.velocity = move_toward(runner.velocity, target, (0.8 + stats[2] * 0.025) * STEP)
			var previous: float = runner.position
			runner.position = minf(distance, previous + runner.velocity * STEP)
			runner.energy = maxf(0.0, runner.energy - STEP * pow(runner.velocity / 16.0, 2.0) * (1.2 - stats[5] * 0.003))
			if runner.position >= distance:
				runner.finish_time = tick * STEP + (distance - previous) / runner.velocity
				finished += 1
		frames.append(_frame((tick + 1) * STEP, runners, distance))
		if finished == runners.size(): break
	if finished != runners.size():
		return {"ok": false, "message": "제한 시간 내에 경주가 끝나지 않았습니다."}
	runners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.finish_time < b.finish_time if a.finish_time != b.finish_time else a.gate < b.gate)
	var finishers: Array[Dictionary] = []
	for runner: Dictionary in runners:
		var entry: Dictionary = {}
		for key: String in RaceRecord.ENTRANT_KEYS:
			entry[key] = runner[key]
		entry.finish_usec = roundi(runner.finish_time * 1000000.0)
		entry.remaining_stamina_milli = roundi(runner.energy * 1000.0)
		entry.prize = 0
		finishers.append(entry)
	finishers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.finish_usec < b.finish_usec if a.finish_usec != b.finish_usec else a.gate < b.gate)
	return {"ok": true, "finishers": finishers, "frames": frames}

static func _frame(time: float, runners: Array[Dictionary], distance: int) -> Dictionary:
	var positions: Array[Dictionary] = []
	for runner: Dictionary in runners:
		positions.append({"gate": runner.gate, "distance": runner.position, "stamina": runner.energy, "phase": phase(runner.position / distance)})
	return {"time": time, "runners": positions}
