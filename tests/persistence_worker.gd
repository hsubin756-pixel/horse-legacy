extends SceneTree

const Fixture = preload("res://tests/persistence_fixture.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var mode: String = args[0]
	var path: String = args[1]
	if mode == "write":
		var session: GameSession = Fixture.session_for_test(path)
		var result := session.save_game()
		if not result.ok:
			push_error(result.message)
			quit(1)
			return
		var receipt: Dictionary = {"snapshot": JSON.stringify(SaveCodec.encode(session.state, session.selected_horse_id), "", true, true), "next_random": []}
		for index: int in 5:
			receipt.next_random.append(session.state.rng.randi())
		var file := FileAccess.open(path + ".receipt", FileAccess.WRITE)
		if file == null:
			quit(1)
			return
		file.store_string(JSON.stringify(receipt, "", true, true))
		file.close()
		print("Writer saved the full game and exited.")
		quit(0)
	elif mode == "read":
		var session := GameSession.new()
		session.saves = SaveManager.new(path)
		var result := session.load_game()
		if not result.ok:
			push_error(result.message)
			quit(1)
			return
		var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".receipt"))
		var actual := JSON.stringify(SaveCodec.encode(session.state, session.selected_horse_id), "", true, true)
		if actual != receipt.snapshot:
			push_error("Loaded snapshot differs from writer receipt")
			quit(1)
			return
		for expected: Variant in receipt.next_random:
			if session.state.rng.randi() != int(expected):
				push_error("RNG continuation differs")
				quit(1)
				return
		var next_id: String = session.state.allocate_id("horse")
		if session.state.horses.has(next_id) or not session.select_horse(session.state.player_farm.horse_ids[0]):
			quit(1)
			return
		if not session.save_game().ok or not session.load_game().ok:
			quit(1)
			return
		print("Reader restored all fields and RNG, continued selection/ID allocation, then saved and loaded again.")
		quit(0)
	else:
		quit(2)
