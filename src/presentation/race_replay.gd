class_name RaceReplay
extends PanelContainer

signal save_requested
signal load_requested
signal closed(race_id: String)
var playback := RacePlayback.new()
var title_label: Label
var progress_label: Label
var event_label: Label
var standings: Label
var status_label: Label
var track: RaceTrack
var pause_button: Button
var skip_button: Button
var return_button: Button
var save_button: Button
var load_button: Button
var speeds: Dictionary[int, Button] = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0e1c15")
	background.set_content_margin_all(20)
	add_theme_stylebox_override("panel", background)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	title_label = RanchTheme.label("", 26, RanchTheme.GOLD)
	body.add_child(title_label)
	progress_label = RanchTheme.label("", 17)
	body.add_child(progress_label)
	track = RaceTrack.new()
	body.add_child(track)
	event_label = RanchTheme.label("", 17, RanchTheme.GOLD)
	body.add_child(event_label)
	standings = RanchTheme.label("", 16)
	standings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(standings)
	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 8)
	body.add_child(controls)
	pause_button = _button(controls, "일시정지", func() -> void: playback.paused = not playback.paused; refresh())
	var group := ButtonGroup.new()
	for speed: int in [1, 4, 8]:
		var button := _button(controls, "%d배속" % speed, func() -> void: playback.set_speed(speed); refresh())
		button.toggle_mode = true
		button.button_group = group
		speeds[speed] = button
	skip_button = _button(controls, "결과 보기", func() -> void: playback.skip(); refresh())
	var files := HFlowContainer.new()
	files.add_theme_constant_override("h_separation", 8)
	body.add_child(files)
	save_button = _button(files, "저장", func() -> void: save_requested.emit())
	load_button = _button(files, "불러오기", func() -> void: load_requested.emit())
	return_button = _button(files, "결과 확인 · 목장으로", func() -> void:
		if playback.finished: closed.emit(playback.record.id))
	status_label = RanchTheme.label("재생 중 저장한 게임은 불러올 때 결과 화면에서 이어집니다.", 14, RanchTheme.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status_label)
	hide()

func _button(parent: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func start(result: Dictionary) -> void:
	playback.start(result)
	status_label.text = "재생 중 저장한 게임은 불러올 때 결과 화면에서 이어집니다."
	show()
	refresh()
	pause_button.grab_focus()

func show_result(record: Dictionary) -> void:
	playback.show_result(record)
	status_label.text = "저장된 경주 결과입니다. 전적과 상금은 이미 반영되어 있습니다."
	show()
	refresh()
	return_button.grab_focus()

func _process(delta: float) -> void:
	if not visible or playback.record.is_empty() or playback.finished: return
	playback.advance(delta)
	refresh()

func refresh() -> void:
	var rows := playback.sample()
	if rows.is_empty(): return
	var record := playback.record
	title_label.text = record.title + (" · 최종 결과" if playback.finished else " · 경주 중")
	progress_label.text = "%.1f초 / %.1f초 · 선두 %.0fm / %dm · 남은 거리 %.0fm" % [playback.elapsed, playback.duration, rows[0].distance, record.distance, maxf(0.0, record.distance - rows[0].distance)]
	track.display(rows, record.distance)
	var phase_labels := {"START": "출발", "EARLY": "초반", "MIDDLE": "중반", "FINAL TURN": "마지막 코너", "FINAL STRAIGHT": "마지막 직선", "FINISH": "결승 통과"}
	event_label.text = ("우승: " if playback.finished else "선두: ") + rows[0].name + " · " + phase_labels[rows[0].phase]
	var lines := PackedStringArray()
	for rank: int in rows.size():
		var row: Dictionary = rows[rank]
		var suffix := " · 우리 목장" if row.owned else ""
		if playback.finished:
			var entry: Dictionary = record.finishers[rank]
			lines.append("%d위  %s%s · %.2f초 · 상금 %d" % [rank + 1, row.name, suffix, entry.finish_usec / 1000000.0, entry.prize])
		else:
			lines.append("%d위  %s%s · %.0fm · 스태미나 %.1f%s" % [rank + 1, row.name, suffix, row.distance, row.stamina, " · 완주" if row.finished else ""])
	standings.text = "\n".join(lines)
	pause_button.text = "계속 재생" if playback.paused else "일시정지"
	pause_button.disabled = playback.finished
	skip_button.disabled = playback.finished
	return_button.disabled = not playback.finished
	for value: int in speeds:
		speeds[value].disabled = playback.finished
		speeds[value].set_pressed_no_signal(playback.speed == value)
