class_name WeekControls
extends VBoxContainer

signal advance_requested(weeks: int, expected_week: int)
var next_week_button: Button
var four_weeks_button: Button
var confirm: ConfirmationDialog
var report_label: Label
var _week: int = 0
var _pending_week: int = -1
var _locked: bool = false
var _cooldown: Timer

func _ready() -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	add_child(actions)
	next_week_button = Button.new()
	next_week_button.text = "1주 진행"
	next_week_button.pressed.connect(func() -> void: _submit(1, _week))
	actions.add_child(next_week_button)
	four_weeks_button = Button.new()
	four_weeks_button.text = "4주 진행…"
	four_weeks_button.pressed.connect(_request_four_weeks)
	actions.add_child(four_weeks_button)
	var hint := RanchTheme.label("배정한 훈련은 첫 주에만 적용 · 미배정 말은 휴식", 14, RanchTheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	report_label = RanchTheme.label("", 14)
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.hide()
	add_child(report_label)
	confirm = ConfirmationDialog.new()
	confirm.title = "4주 진행"
	confirm.dialog_text = "첫 주에는 배정한 훈련을 수행하고, 이후 3주는 모두 휴식합니다.\n성장·회복과 나이 변화가 매주 반영됩니다. 계속할까요?"
	confirm.ok_button_text = "4주 진행"
	confirm.cancel_button_text = "돌아가기"
	confirm.confirmed.connect(func() -> void: _submit(4, _pending_week))
	add_child(confirm)
	_cooldown = Timer.new()
	_cooldown.one_shot = true
	_cooldown.wait_time = 0.35
	_cooldown.timeout.connect(_unlock)
	add_child(_cooldown)

func refresh(state: GameState, clear_report: bool = false) -> void:
	_week = state.current_week
	if clear_report:
		report_label.hide()
		report_label.text = ""

func _request_four_weeks() -> void:
	if _locked:
		return
	_pending_week = _week
	confirm.popup_centered(Vector2i(460, 170))

func _submit(weeks: int, expected_week: int) -> void:
	if _locked:
		return
	_locked = true
	next_week_button.disabled = true
	four_weeks_button.disabled = true
	advance_requested.emit(weeks, expected_week)
	_cooldown.start()

func _unlock() -> void:
	_locked = false
	next_week_button.disabled = false
	four_weeks_button.disabled = false

func show_report(result: Dictionary) -> void:
	var lines: PackedStringArray = []
	for change: Dictionary in result.changes.slice(0, 4):
		var total_gain: float = 0.0
		for value: float in change.stats.values():
			total_gain += value
		var parts := PackedStringArray(["능력 합계 %+.2f" % total_gain, "컨디션 %+.0f" % change.fitness,
			"피로 %+.0f" % change.fatigue, "스트레스 %+.0f" % change.stress])
		if change.age_after != change.age_before:
			parts.append("%d세가 되었습니다" % change.age_after)
		if change.matured:
			parts.append("성마가 되었습니다")
		if change.healed:
			parts.append("부상 회복")
		lines.append(change.name + ": " + change.action + " · " + " · ".join(parts))
	if result.changes.size() > 4:
		lines.append("외 %d마리에도 주간 변화가 반영되었습니다." % (result.changes.size() - 4))
	report_label.text = "\n".join(lines)
	report_label.show()
