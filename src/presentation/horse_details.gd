class_name HorseDetails
extends PanelContainer

const STAT_LABELS: Array[String] = ["스피드", "지구력", "가속력", "파워", "투지", "지능"]
var name_label: Label
var summary_label: Label
var status_label: Label
var parent_label: Label
var condition_label: Label
var career_label: Label
var stat_bars: Array[ProgressBar] = []
var stat_values: Array[Label] = []
var displayed_horse_id: String = ""

func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(RanchTheme.label("HORSE PROFILE  /  말 상세", 14, RanchTheme.GOLD))
	name_label = RanchTheme.label("", 30)
	column.add_child(name_label)
	summary_label = RanchTheme.label("", 16, RanchTheme.MUTED)
	column.add_child(summary_label)
	status_label = RanchTheme.label("", 16, RanchTheme.GOLD)
	column.add_child(status_label)
	column.add_child(HSeparator.new())
	var stat_heading := HBoxContainer.new()
	var heading_label := RanchTheme.label("능력치", 15, RanchTheme.MUTED)
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_heading.add_child(heading_label)
	stat_heading.add_child(RanchTheme.label("현재 / 잠재", 15, RanchTheme.MUTED))
	column.add_child(stat_heading)
	for index: int in StatBlock.KEYS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var title := RanchTheme.label(STAT_LABELS[index])
		title.custom_minimum_size.x = 74
		row.add_child(title)
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.y = 8
		bar.show_percentage = false
		row.add_child(bar)
		stat_bars.append(bar)
		var value := RanchTheme.label("")
		value.custom_minimum_size.x = 94
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		stat_values.append(value)
		column.add_child(row)
	column.add_child(HSeparator.new())
	condition_label = RanchTheme.label("", 16)
	condition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(condition_label)
	career_label = RanchTheme.label("", 16)
	column.add_child(career_label)
	parent_label = RanchTheme.label("", 15, RanchTheme.MUTED)
	parent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(parent_label)

func show_horse(horse: Horse, state: GameState) -> void:
	displayed_horse_id = horse.id
	name_label.text = horse.name
	var sex_text := "수말" if horse.sex == Horse.Sex.MALE else "암말"
	summary_label.text = "%s · %d세 · %s" % [sex_text, horse.age_years(state.current_week), state.player_farm.name]
	var status_names: Array[String] = ["경주마 · 데뷔 전", "경주마 · 활동 중", "은퇴마"]
	var growth_names: Dictionary = {&"early": "조숙", &"normal": "보통", &"late": "만성"}
	var stage_names: Array[String] = ["자마", "성마", "사망 기록"]
	status_label.text = "%s · %s · %s 성장" % [status_names[horse.career_status], stage_names[horse.life_stage], growth_names[horse.growth_type]]
	for index: int in StatBlock.KEYS.size():
		var key: StringName = StatBlock.KEYS[index]
		stat_bars[index].value = horse.stats.values[key]
		stat_values[index].text = "%.1f / %.1f" % [horse.stats.values[key], horse.potential.values[key]]
	var health := "건강함" if horse.injury_weeks == 0 else "부상 · 회복까지 %d주" % horse.injury_weeks
	condition_label.text = "컨디션 %d  ·  피로 %d  ·  스트레스 %d\n%s" % [horse.fitness, horse.fatigue, horse.stress, health]
	career_label.text = "통산 %d전 %d승  ·  누적 상금 %d" % [horse.starts, horse.wins, horse.earnings]
	parent_label.text = "부: %s  /  모: %s" % [_parent_name(horse.father_id, state), _parent_name(horse.mother_id, state)]

func _parent_name(horse_id: String, state: GameState) -> String:
	if horse_id.is_empty():
		return "기록 없음"
	var parent: Horse = state.horses.get(horse_id)
	return parent.name if parent != null else "기록을 찾을 수 없음"
