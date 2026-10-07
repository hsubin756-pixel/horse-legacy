class_name StatBlock
extends RefCounted

const KEYS: Array[StringName] = [&"speed", &"stamina", &"acceleration", &"power", &"spirit", &"intelligence"]
var values: Dictionary[StringName, float] = {}

func _init() -> void:
	for key: StringName in KEYS:
		values[key] = 0.0

static func from_array(source: Array) -> StatBlock:
	if source.size() != KEYS.size():
		return null
	var result := StatBlock.new()
	for index: int in KEYS.size():
		var value: Variant = source[index]
		if not (value is int or value is float):
			return null
		if not is_finite(float(value)) or value < 0 or value > 100:
			return null
		result.values[KEYS[index]] = float(value)
	return result
