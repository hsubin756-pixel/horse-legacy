extends RefCounted

const Fixture = preload("res://tests/persistence_fixture.gd")
var check: Callable
var directory: String

class FaultyManager extends SaveManager:
	var fail_at: String = ""
	func _write(file_path: String, contents: String) -> Error:
		if fail_at == "temporary-write" and file_path == path + ".tmp":
			super._write(file_path, contents.left(8))
			return ERR_FILE_CANT_WRITE
		if fail_at == "partial-write" and file_path == path + ".tmp":
			return super._write(file_path, contents.left(8))
		if fail_at == "backup-write" and file_path == path + ".bak.tmp":
			return ERR_FILE_CANT_WRITE
		return super._write(file_path, contents)
	func _replace(source: String, destination: String) -> Error:
		if fail_at == "backup-rename" and destination == path + ".bak":
			return ERR_FILE_CANT_WRITE
		if fail_at == "primary-rename" and destination == path:
			return ERR_FILE_CANT_WRITE
		return super._replace(source, destination)

func run(callback: Callable, test_directory: String) -> void:
	check = callback
	directory = test_directory
	DirAccess.make_dir_recursive_absolute(directory)
	_codec_checks()
	_file_checks()
	_failure_checks()
	_process_checks()

func _canonical(document: Dictionary) -> String:
	return JSON.stringify(document, "", true, true)

func _codec_checks() -> void:
	var session: GameSession = Fixture.session_for_test(directory.path_join("codec.json"))
	var document := SaveCodec.encode(session.state, session.selected_horse_id)
	var decoded := SaveCodec.decode(JSON.parse_string(_canonical(document)))
	check.call(decoded.ok, "Versioned JSON decodes into a validated game")
	if not decoded.ok:
		print(decoded.message)
		return
	check.call(_canonical(SaveCodec.encode(decoded.state, decoded.selected_horse_id)) == _canonical(document), "All model fields, historical ancestors and selected horse survive a JSON round trip")
	check.call(decoded.state.rng.randi() == session.state.rng.randi(), "64-bit RNG seed/state preserve exact continuation")
	decoded.state.owned_horses()[0].stats.values[&"speed"] = 1
	check.call(session.state.owned_horses()[0].stats.values[&"speed"] != 1, "Decoded game owns independent objects")
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json"))
	check.call(SaveCodec.decode(fixture).ok, "Checked-in schema v1 fixture remains readable")
	for version: Variant in [0, 2, 1.5, "1", true]:
		var bad := document.duplicate(true)
		bad.schema_version = version
		check.call(not SaveCodec.decode(bad).ok, "Unsupported or malformed version rejected: " + str(version))
	var mutations: Dictionary = {
		"fractional date": func(d: Dictionary) -> void: d.current_week = 1.5,
		"numeric string": func(d: Dictionary) -> void: d.farm.money = "100",
		"boolean condition": func(d: Dictionary) -> void: d.horses[0].fitness = true,
		"nonfinite stat": func(d: Dictionary) -> void: d.horses[0].stats[0] = NAN,
		"potential under current": func(d: Dictionary) -> void: d.horses[0].potential[0] = 1,
		"missing field": func(d: Dictionary) -> void: d.horses[0].erase("birth_week"),
		"unknown field": func(d: Dictionary) -> void: d.unversioned_feature = {},
		"duplicate horse ID": func(d: Dictionary) -> void: d.horses.append(d.horses[0].duplicate(true)),
		"missing owned horse": func(d: Dictionary) -> void: d.farm.horse_ids.append("horse-987"),
		"duplicate ownership": func(d: Dictionary) -> void: d.farm.horse_ids.append(d.farm.horse_ids[0]),
		"wrong ownership": func(d: Dictionary) -> void: d.horses[0].owner_farm_id = "",
		"unknown parent": func(d: Dictionary) -> void: d.horses[0].father_id = "horse-999",
		"wrong parent sex": func(d: Dictionary) -> void: d.horses[0].father_id = d.horses[1].id,
		"bloodline cycle": func(d: Dictionary) -> void: d.horses[2].father_id = d.horses[0].id,
		"future birth": func(d: Dictionary) -> void: d.horses[0].birth_week = 999,
		"ID counter collision": func(d: Dictionary) -> void: d.next_id = 2,
		"selected unowned ancestor": func(d: Dictionary) -> void: d.selected_horse_id = d.horses[2].id,
		"RNG int overflow": func(d: Dictionary) -> void: d.rng_state = "9223372036854775808",
		"RNG numeric precision loss": func(d: Dictionary) -> void: d.rng_state = 123456,
		"unsupported simulation": func(d: Dictionary) -> void: d.simulation_version = GameState.SIMULATION_VERSION + 1,
		"dangling race result": func(d: Dictionary) -> void: d.horses[0].race_result_ids.append("race-missing"),
	}
	for description: String in mutations:
		var bad := document.duplicate(true)
		mutations[description].call(bad)
		check.call(not SaveCodec.decode(bad).ok, "Invalid save rejected: " + description)

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _file_checks() -> void:
	var path := directory.path_join("slot.json")
	var session: GameSession = Fixture.session_for_test(path)
	check.call(not session.load_game().ok, "Missing save returns a recoverable error")
	check.call(session.save_game().ok and not session.saves.has_backup(), "First save creates the slot without inventing a backup")
	var first := FileAccess.get_file_as_string(path)
	session.state.current_week = 54
	check.call(session.save_game().ok and session.saves.has_backup(), "Second save retains the previous valid save")
	check.call(FileAccess.get_file_as_string(path + ".bak") == first, "Backup is byte-for-byte the previous save")
	var current := FileAccess.get_file_as_string(path)
	var counter: int = session.state.next_id
	session.state.next_id = 1
	check.call(not session.save_game().ok and FileAccess.get_file_as_string(path) == current, "Invalid live state cannot overwrite a valid save")
	session.state.next_id = counter
	var original: GameState = session.state
	var selected: String = session.selected_horse_id
	_write(path, "{broken")
	check.call(not session.load_game().ok and session.state == original and session.selected_horse_id == selected, "Corrupt load preserves active state and selection")
	check.call(not session.save_game().ok and FileAccess.get_file_as_string(path) == "{broken" and FileAccess.get_file_as_string(path + ".bak") == first, "Normal save refuses to overwrite an invalid primary or its valid backup")
	check.call(session.recover_backup().ok and session.state.current_week == 53, "Explicit recovery restores the older valid backup")
	check.call(FileAccess.get_file_as_string(path + ".before-recovery") == "{broken" and FileAccess.get_file_as_string(path) == first, "Recovery preserves the corrupt original and repairs the primary")
	check.call(session.save_game().ok, "Play can be saved again after backup recovery")
	_write(path + ".bak", "invalid backup")
	original = session.state
	var before_recovery := FileAccess.get_file_as_string(path)
	check.call(not session.recover_backup().ok and session.state == original and FileAccess.get_file_as_string(path) == before_recovery, "Invalid backup cannot replace a valid primary or current state")
	_write(path + ".bak", first)
	_write(path, "")
	check.call(session.recover_backup().ok and FileAccess.get_file_as_bytes(path + ".before-recovery").is_empty(), "Zero-byte primary can be recovered while preserving its original")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([255, 254, 0, 128]))
	file.close()
	check.call(session.recover_backup().ok and FileAccess.get_file_as_bytes(path + ".before-recovery") == PackedByteArray([255, 254, 0, 128]), "Recovery preserves an arbitrary corrupt binary primary exactly")
	var future: Dictionary = JSON.parse_string(current)
	future.schema_version = 2
	_write(path, _canonical(future))
	var future_bytes := FileAccess.get_file_as_bytes(path)
	check.call(not session.load_game().ok and not session.save_game().ok and FileAccess.get_file_as_bytes(path) == future_bytes, "Future-version save is neither loaded nor overwritten")
	_write(path, current)
	_write(path + ".tmp", first)
	check.call(session.load_game().ok and session.state.current_week == 54, "Uncommitted temporary save is ignored after interruption")
	DirAccess.remove_absolute(path)
	check.call(session.recover_backup().ok and session.saves.has_save(), "Missing primary can be recreated from a valid backup")

func _failure_checks() -> void:
	for stage: String in ["temporary-write", "partial-write", "backup-write", "backup-rename", "primary-rename"]:
		var path := directory.path_join(stage + ".json")
		var session: GameSession = Fixture.session_for_test(path)
		var manager := FaultyManager.new(path)
		session.saves = manager
		if not session.save_game().ok:
			check.call(false, "Failure test prerequisite save: " + stage)
			continue
		session.state.current_week = 54
		if not session.save_game().ok:
			check.call(false, "Failure test prerequisite backup: " + stage)
			continue
		var primary := FileAccess.get_file_as_bytes(path)
		session.state.current_week = 55
		manager.fail_at = stage
		check.call(not session.save_game().ok, "Injected failure is reported: " + stage)
		check.call(FileAccess.get_file_as_bytes(path) == primary and manager.load_game().state.current_week == 54, "Last committed save survives: " + stage)
		var backup: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
		check.call(SaveCodec.decode(backup).ok, "A valid backup survives: " + stage)
		manager.fail_at = ""
		check.call(session.save_game().ok, "Retry succeeds after I/O recovery: " + stage)
	var recovery: GameSession = Fixture.session_for_test(directory.path_join("recovery-failure.json"))
	var manager := FaultyManager.new(recovery.saves.path)
	recovery.saves = manager
	recovery.save_game()
	recovery.state.current_week = 54
	recovery.save_game()
	var original: GameState = recovery.state
	var contents := FileAccess.get_file_as_bytes(manager.path)
	manager.fail_at = "primary-rename"
	check.call(not recovery.recover_backup().ok and recovery.state == original and FileAccess.get_file_as_bytes(manager.path) == contents, "Recovery rename failure preserves active state and primary")

func _process_checks() -> void:
	var path := directory.path_join("process.json")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/persistence_worker.gd", "--", "write", path])
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	check.call(code == 0 and FileAccess.file_exists(path), "Separate writer process saves and exits successfully")
	if code != 0:
		print(output)
		return
	args[args.size() - 2] = "read"
	output.clear()
	code = OS.execute(OS.get_executable_path(), args, output, true)
	check.call(code == 0, "Separate reader restores all fields/RNG and continues with another save/load")
	for line: Variant in output:
		print(str(line).strip_edges())
