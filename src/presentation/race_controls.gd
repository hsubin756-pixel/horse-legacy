class_name RaceControls
extends VBoxContainer

signal entry_requested(horse_id: String, expected_week: int)
var entry_button: Button
var confirm: ConfirmationDialog
var summary: Label
var result_label: Label
var _horse_id: String = ""
var _week: int = 0
var _pending_id: String = ""
var _pending_week: int = -1

func _ready() -> void:
	entry_button = Button.new()
	entry_button.text = "선택한 말 경주 출전…"
	entry_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	entry_button.pressed.connect(_request)
	add_child(entry_button)
	summary = RanchTheme.label("", 14, RanchTheme.MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	result_label = RanchTheme.label("", 15)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(result_label)
	confirm = ConfirmationDialog.new()
	confirm.title = "경주 출전"
	confirm.ok_button_text = "출전하고 1주 진행"
	confirm.cancel_button_text = "돌아가기"
	confirm.confirmed.connect(func() -> void: entry_requested.emit(_pending_id, _pending_week))
	add_child(confirm)

func refresh(horse: Horse, state: GameState) -> void:
	_horse_id = horse.id
	_week = state.current_week
	var rules := RaceSystem.read_rules()
	var reason := RaceSystem.unavailable_reason(horse, _week)
	entry_button.disabled = not reason.is_empty() or rules.is_empty()
	summary.text = reason if not reason.is_empty() else ("경주 설정을 읽을 수 없습니다." if rules.is_empty() else "%s · %dm · 4두 · 우승 상금 %d\n출전: %s · 1주 소요 · 출전마 훈련을 대체 · 다른 말은 배정 행동 수행" % [rules.title, rules.distance, rules.prizes[0], horse.name])
	result_label.text = ""
	if not state.race_results.is_empty():
		var record: Dictionary = state.race_results.back()
		var lines := PackedStringArray(["최근 경주: %s · 목장 %d년 %d주" % [record.title, int(record.week) / 52 + 1, int(record.week) % 52 + 1]])
		for rank: int in record.finishers.size():
			var entry: Dictionary = record.finishers[rank]
			lines.append("%d위  %s%s · %.2f초 · 상금 %d" % [rank + 1, entry.name, " (우리 목장)" if not entry.horse_id.is_empty() else "", entry.finish_usec / 1000000.0, entry.prize])
		result_label.text = "\n".join(lines)

func _request() -> void:
	if entry_button.disabled: return
	_pending_id = _horse_id
	_pending_week = _week
	confirm.dialog_text = summary.text + "\n출전마는 이번 주 훈련·휴식 회복 없이 경주 피로를 받습니다.\n경주는 자동 계산되며 착순과 상금을 즉시 반영합니다. 계속할까요?"
	confirm.popup_centered(Vector2i(660, 250))
