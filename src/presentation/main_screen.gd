class_name MainScreen
extends Control

var session := GameSession.new()
var start_button: Button
var restart_button: Button
var restart_dialog: ConfirmationDialog
var title_screen: VBoxContainer
var ranch_screen: VBoxContainer
var horse_list: VBoxContainer
var details: HorseDetails
var farm_label: Label
var date_label: Label
var error_label: Label
var horse_buttons: Dictionary[String, Button] = {}
var continue_button: Button
var save_button: Button
var load_button: Button
var recovery_button: Button
var title_recovery_button: Button
var file_dialog: ConfirmationDialog
var pending_file_action: String = ""

func _ready() -> void:
	theme = RanchTheme.create()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(RanchTheme.label("H O R S E   L E G A C Y", 32, RanchTheme.GOLD))
	column.add_child(RanchTheme.label("한 마리에서 시작되는, 여러 세대의 이야기", 17, RanchTheme.MUTED))
	error_label = RanchTheme.label("", 16, Color("ffc6a0"))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.hide()
	column.add_child(error_label)
	_build_title(column)
	_build_ranch(column)
	var notice := RanchTheme.label("수동 저장 · 종료하기 전에 저장해 주세요. 백업은 한 번 이전에 저장한 상태입니다.", 14, RanchTheme.MUTED)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(notice)
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.title = "새 목장 시작"
	restart_dialog.dialog_text = "저장하지 않은 진행을 버리고 새 목장을 시작할까요?\n기존 저장 파일은 저장 버튼을 누르기 전까지 유지됩니다."
	restart_dialog.ok_button_text = "새로 시작"
	restart_dialog.cancel_button_text = "돌아가기"
	restart_dialog.confirmed.connect(_start_game)
	add_child(restart_dialog)
	file_dialog = ConfirmationDialog.new()
	file_dialog.cancel_button_text = "돌아가기"
	file_dialog.confirmed.connect(_perform_file_action)
	file_dialog.canceled.connect(func() -> void: pending_file_action = "")
	add_child(file_dialog)
	session.game_started.connect(_on_game_started)
	session.horse_selected.connect(_on_horse_selected)
	_update_file_buttons()
	start_button.grab_focus()

func _build_title(parent: VBoxContainer) -> void:
	title_screen = VBoxContainer.new()
	title_screen.add_theme_constant_override("separation", 20)
	parent.add_child(title_screen)
	var panel := PanelContainer.new()
	title_screen.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	panel.add_child(body)
	body.add_child(RanchTheme.label("당신의 혈통은 여기서 시작됩니다.", 26))
	var intro := RanchTheme.label("작은 목장과 두 마리의 말.\n첫 주인으로서, 앞으로 이어질 목장의 이야기를 시작하세요.", 19)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	start_button = Button.new()
	start_button.text = "새 게임 시작"
	start_button.custom_minimum_size = Vector2(240, 60)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start_button.pressed.connect(_start_game)
	body.add_child(start_button)
	continue_button = Button.new()
	continue_button.text = "저장한 목장 이어하기"
	continue_button.pressed.connect(_request_file_action.bind("load"))
	body.add_child(continue_button)
	title_recovery_button = Button.new()
	title_recovery_button.text = "이전 저장 백업 복구"
	title_recovery_button.pressed.connect(_request_file_action.bind("recover"))
	body.add_child(title_recovery_button)

func _build_ranch(parent: VBoxContainer) -> void:
	ranch_screen = VBoxContainer.new()
	ranch_screen.add_theme_constant_override("separation", 18)
	ranch_screen.hide()
	parent.add_child(ranch_screen)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 20)
	ranch_screen.add_child(heading)
	var heading_text := VBoxContainer.new()
	heading_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_text)
	farm_label = RanchTheme.label("", 26)
	heading_text.add_child(farm_label)
	date_label = RanchTheme.label("", 15, RanchTheme.MUTED)
	heading_text.add_child(date_label)
	restart_button = Button.new()
	restart_button.text = "새 목장 시작"
	restart_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	restart_button.pressed.connect(func() -> void: restart_dialog.popup_centered(Vector2i(440, 180)))
	heading.add_child(restart_button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	ranch_screen.add_child(actions)
	save_button = Button.new()
	save_button.text = "저장"
	save_button.pressed.connect(_request_file_action.bind("save"))
	actions.add_child(save_button)
	load_button = Button.new()
	load_button.text = "불러오기"
	load_button.pressed.connect(_request_file_action.bind("load"))
	actions.add_child(load_button)
	recovery_button = Button.new()
	recovery_button.text = "백업 복구"
	recovery_button.pressed.connect(_request_file_action.bind("recover"))
	actions.add_child(recovery_button)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	ranch_screen.add_child(body)
	var stable := PanelContainer.new()
	stable.custom_minimum_size.x = 290
	stable.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(stable)
	horse_list = VBoxContainer.new()
	stable.add_child(horse_list)
	details = HorseDetails.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(details)

func _start_game() -> void:
	if not session.new_game():
		error_label.add_theme_color_override("font_color", Color("ffc6a0"))
		error_label.text = "새 게임 데이터를 읽지 못했습니다. data/rules/new_game.json을 확인해 주세요."
		error_label.show()

func _on_game_started() -> void:
	error_label.hide()
	_update_file_buttons()
	title_screen.hide()
	ranch_screen.show()
	farm_label.text = session.state.player_farm.name
	var week: int = session.state.current_week
	date_label.text = "목장 %d년 · %d주  /  보유 말 %d마리" % [floori(float(week) / GameState.WEEKS_PER_YEAR) + 1, week % GameState.WEEKS_PER_YEAR + 1, session.state.player_farm.horse_ids.size()]
	for child: Node in horse_list.get_children():
		horse_list.remove_child(child)
		child.queue_free()
	horse_buttons.clear()
	horse_list.add_child(RanchTheme.label("STABLE  /  마방", 14, RanchTheme.GOLD))
	var group := ButtonGroup.new()
	for horse: Horse in session.state.owned_horses():
		var button := Button.new()
		var sex_text := "수말" if horse.sex == Horse.Sex.MALE else "암말"
		button.text = "%s\n%s · %d세" % [horse.name, sex_text, horse.age_years(week)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 80
		button.pressed.connect(_select_horse.bind(horse.id))
		horse_list.add_child(button)
		horse_buttons[horse.id] = button
	horse_buttons[session.selected_horse_id].grab_focus()

func _select_horse(horse_id: String) -> void:
	session.select_horse(horse_id)

func _on_horse_selected(horse_id: String) -> void:
	details.show_horse(session.selected_horse(), session.state)
	horse_buttons[horse_id].set_pressed_no_signal(true)

func _update_file_buttons() -> void:
	continue_button.disabled = not session.saves.has_save()
	load_button.disabled = not session.saves.has_save()
	save_button.disabled = session.state == null
	recovery_button.disabled = not session.saves.has_backup()
	title_recovery_button.disabled = not session.saves.has_backup()

func _request_file_action(action: String) -> void:
	pending_file_action = action
	if action == "save" and session.saves.has_save():
		file_dialog.title = "저장 덮어쓰기"
		file_dialog.dialog_text = "저장된 목장을 현재 상태로 덮어쓸까요?\n기존의 유효한 저장은 이전 저장 백업으로 남습니다."
		file_dialog.ok_button_text = "저장"
	elif action == "load" and session.state != null:
		file_dialog.title = "저장한 목장 불러오기"
		file_dialog.dialog_text = "저장하지 않은 진행을 버리고 마지막 저장을 불러올까요?"
		file_dialog.ok_button_text = "불러오기"
	elif action == "recover":
		file_dialog.title = "이전 저장 백업 복구"
		file_dialog.dialog_text = "이전 저장의 백업으로 돌아갈까요?\n저장하지 않은 진행은 사라집니다. 복구 전 원본 파일은 별도로 보존합니다."
		file_dialog.ok_button_text = "백업 복구"
	else:
		_perform_file_action()
		return
	file_dialog.popup_centered(Vector2i(500, 190))

func _perform_file_action() -> void:
	var result: SaveResult
	match pending_file_action:
		"save": result = session.save_game()
		"load": result = session.load_game()
		"recover": result = session.recover_backup()
		_: return
	pending_file_action = ""
	_update_file_buttons()
	error_label.add_theme_color_override("font_color", RanchTheme.GOLD if result.ok else Color("ffc6a0"))
	error_label.text = result.message if not result.message.is_empty() else "저장한 목장을 불러왔습니다."
	error_label.show()
