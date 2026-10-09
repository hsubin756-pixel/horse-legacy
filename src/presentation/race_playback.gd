class_name RacePlayback
extends RefCounted

var record: Dictionary = {}
var frames: Array = []
var elapsed: float = 0.0
var duration: float = 0.0
var speed: float = 4.0
var paused: bool = false
var finished: bool = true

func start(result: Dictionary) -> void:
	record = result.record.duplicate(true)
	frames = result.frames.duplicate(true)
	duration = record.finishers.back().finish_usec / 1000000.0
	elapsed = 0.0
	speed = 4.0
	paused = false
	finished = false

func show_result(value: Dictionary) -> void:
	record = value.duplicate(true)
	frames.clear()
	duration = record.finishers.back().finish_usec / 1000000.0
	elapsed = duration
	finished = true
	paused = false

func advance(delta: float) -> void:
	if finished or paused or not is_finite(delta) or delta <= 0.0: return
	elapsed = minf(duration, elapsed + delta * speed)
	finished = elapsed >= duration

func set_speed(value: float) -> void:
	if value in [1.0, 4.0, 8.0]: speed = value

func skip() -> void:
	elapsed = duration
	finished = true
	paused = false

func sample() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if record.is_empty(): return rows
	var low: Dictionary = {}
	var high: Dictionary = {}
	if not frames.is_empty():
		var index := mini(floori(elapsed / RaceSimulator.STEP), frames.size() - 1)
		low = frames[index]
		high = frames[mini(index + 1, frames.size() - 1)]
	for placing: int in record.finishers.size():
		var entry: Dictionary = record.finishers[placing]
		var crossed: bool = elapsed >= entry.finish_usec / 1000000.0
		var distance: float = record.distance
		var stamina: float = entry.remaining_stamina_milli / 1000.0
		if not crossed and not frames.is_empty():
			var a := _runner(low, int(entry.gate))
			var b := _runner(high, int(entry.gate))
			var end_time: float = high.time
			if b.distance >= record.distance:
				end_time = entry.finish_usec / 1000000.0
			var alpha := clampf((elapsed - low.time) / maxf(0.000001, end_time - low.time), 0.0, 1.0)
			distance = lerpf(a.distance, b.distance, alpha)
			stamina = lerpf(a.stamina, b.stamina, alpha)
		rows.append({"gate": entry.gate, "name": entry.name, "owned": not entry.horse_id.is_empty(), "distance": distance,
			"stamina": stamina, "finished": crossed, "placing": placing + 1, "phase": RaceSimulator.phase(distance / record.distance)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.finished and b.finished: return a.placing < b.placing
		if a.finished != b.finished: return a.finished
		return a.distance > b.distance if a.distance != b.distance else a.gate < b.gate)
	return rows

func _runner(frame: Dictionary, gate: int) -> Dictionary:
	for runner: Dictionary in frame.runners:
		if runner.gate == gate: return runner
	return {}
