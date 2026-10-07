class_name SaveManager
extends RefCounted

const DEFAULT_PATH: String = "user://saves/ranch.json"
const MAX_FILE_BYTES: int = 16 * 1024 * 1024
var path: String

func _init(save_path: String = DEFAULT_PATH) -> void:
	path = ProjectSettings.globalize_path(save_path)

func has_save() -> bool:
	return FileAccess.file_exists(path)

func has_backup() -> bool:
	return FileAccess.file_exists(path + ".bak")

func load_game() -> SaveResult:
	return _read(path)

func save_game(state: GameState, selected_id: String) -> SaveResult:
	if state == null:
		return SaveResult.failure("먼저 게임을 시작해 주세요.")
	var document := SaveCodec.encode(state, selected_id)
	var validated := SaveCodec.decode(document)
	if not validated.ok:
		return validated
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return SaveResult.failure("저장 폴더를 만들 수 없습니다. 쓰기 권한을 확인해 주세요.")
	var contents := JSON.stringify(document, "\t", true, true)
	var reason := _stage_valid(path + ".tmp", contents)
	if not reason.is_empty():
		return SaveResult.failure(reason)
	if has_save():
		var previous := _read(path)
		if not previous.ok:
			return SaveResult.failure("기존 저장 파일을 덮어쓰지 않았습니다. " + previous.message + " 백업이 있다면 먼저 복구해 주세요.")
		reason = _stage_valid(path + ".bak.tmp", FileAccess.get_file_as_string(path))
		if not reason.is_empty():
			return SaveResult.failure(reason)
		if _replace(path + ".bak.tmp", path + ".bak") != OK:
			return SaveResult.failure("백업을 교체하지 못했습니다. 기존 저장 파일을 유지합니다.")
	if _replace(path + ".tmp", path) != OK:
		return SaveResult.failure("새 저장 파일을 적용하지 못했습니다. 기존 파일과 백업을 유지합니다.")
	return SaveResult.success(validated.state, selected_id, "저장했습니다.")

func recover_backup() -> SaveResult:
	# Recovery is explicit; normal load never silently rolls back to an older save.
	var backup := _read(path + ".bak")
	if not backup.ok:
		return SaveResult.failure("백업을 복구할 수 없습니다. " + backup.message)
	var reason := _stage_valid(path + ".tmp", FileAccess.get_file_as_string(path + ".bak"))
	if not reason.is_empty():
		return SaveResult.failure(reason)
	if has_save():
		# Preserve even an invalid/newer primary before an explicitly requested recovery.
		if DirAccess.copy_absolute(path, path + ".before-recovery.tmp") != OK:
			return SaveResult.failure("복구 전 원본을 보존할 수 없습니다.")
		var original_hash := FileAccess.get_sha256(path)
		if original_hash.is_empty() or original_hash != FileAccess.get_sha256(path + ".before-recovery.tmp"):
			return SaveResult.failure("복구 전 원본 보존을 검증하지 못했습니다.")
		if _replace(path + ".before-recovery.tmp", path + ".before-recovery") != OK:
			return SaveResult.failure("복구 전 원본 보존에 실패했습니다.")
	if _replace(path + ".tmp", path) != OK:
		return SaveResult.failure("백업 적용에 실패했습니다. 기존 파일은 유지됩니다.")
	backup.message = "이전 저장의 백업을 복구했습니다."
	return backup

func _read(file_path: String) -> SaveResult:
	var contents := _read_text(file_path)
	if not contents.ok:
		return SaveResult.failure(contents.message)
	var parser := JSON.new()
	if parser.parse(contents.text) != OK:
		return SaveResult.failure("저장 파일을 해석하지 못했습니다. 파일이 손상되었을 수 있습니다.")
	return SaveCodec.decode(parser.data)

func _read_text(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "저장 파일이 없거나 읽을 수 없습니다."}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_FILE_BYTES:
		file.close()
		return {"ok": false, "message": "저장 파일 크기가 올바르지 않습니다."}
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if bytes.size() != length or read_error != OK:
		return {"ok": false, "message": "저장 파일을 끝까지 읽지 못했습니다."}
	var contents := bytes.get_string_from_utf8()
	if contents.to_utf8_buffer() != bytes:
		return {"ok": false, "message": "저장 파일의 문자 인코딩이 손상되었습니다."}
	return {"ok": true, "text": contents}

func _stage_valid(file_path: String, contents: String) -> String:
	if contents.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return "저장 가능한 파일 크기를 초과했습니다."
	if _write(file_path, contents) != OK:
		return "임시 파일 쓰기에 실패했습니다. 공간과 쓰기 권한을 확인해 주세요."
	var reread := _read_text(file_path)
	if not reread.ok or reread.text != contents:
		return "임시 파일을 완전히 기록하지 못했습니다."
	var verified := _read(file_path)
	return "" if verified.ok else verified.message

func _write(file_path: String, contents: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error

func _replace(source: String, destination: String) -> Error:
	# Same-directory rename; never delete the destination as a fallback.
	return DirAccess.rename_absolute(source, destination)
