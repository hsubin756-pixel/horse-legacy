class_name TrainingControls
extends VBoxContainer

signal assignment_requested(horse_id: String, program: String)
var buttons: Dictionary[String, Button] = {}
var heading: Label
var info: Label
var _horse_id: String = ""

func _ready() -> void:
	heading = RanchTheme.label("", 17, RanchTheme.GOLD)
	add_child(heading)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	add_child(row)
	var group := ButtonGroup.new()
	for program: String in TrainingSystem.PROGRAMS:
		var button := Button.new()
		button.text = TrainingSystem.label_for(program)
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func() -> void: assignment_requested.emit(_horse_id, program))
		row.add_child(button)
		buttons[program] = button
	info = RanchTheme.label("", 14, RanchTheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)

func refresh(horse: Horse, state: GameState) -> void:
	_horse_id = horse.id
	var program: String = state.training_assignments.get(horse.id, "rest")
	heading.text = "%s · 이번 주: %s" % [horse.name, TrainingSystem.label_for(program)]
	var reason := TrainingSystem.unavailable_reason(horse)
	var rules := TrainingSystem.read_rules()
	for key: String in buttons:
		buttons[key].disabled = key != "rest" and (not reason.is_empty() or rules.is_empty())
		buttons[key].set_pressed_no_signal(key == program)
	info.text = "단거리: 스피드·가속 / 지구력: 지구력 / 언덕: 파워 / 정신: 투지·지능\n배정은 이번 주에만 적용됩니다. 다음 주부터 미배정 휴식합니다."
	if not reason.is_empty():
		info.text += "\n" + reason
	elif rules.is_empty():
		info.text += "\n훈련 규칙 파일을 읽을 수 없습니다."
	else:
		info.text += "\n훈련 효율 %.0f%% · 부상 위험 %.1f%% · 훈련 시 피로 +%.0f / 스트레스 +%.0f" % [TrainingSystem.efficiency(horse) * 100.0, TrainingSystem.injury_chance(horse, rules) * 100.0, rules.fatigue_gain, rules.stress_gain]
		if horse.fatigue >= rules.overwork_threshold:
			info.text += "\n과로 상태: 컨디션 하락과 부상 위험이 있습니다. 휴식을 권장합니다."
