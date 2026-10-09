extends RefCounted

func run(check: Callable, directory: String) -> void:
	var session := GameSession.new()
	session.new_game(71)
	var result := session.enter_race(session.selected_horse_id, 0)
	check.call(result.ok and session.state.pending_race_result_id == result.record.id, "Committed race marks its result as awaiting acknowledgement")
	var state_before := _snapshot(session)
	var input_before := JSON.stringify(result.frames)
	var playback := RacePlayback.new()
	playback.start(result)
	var start := playback.sample()
	check.call(start[0].gate == 1 and start[0].distance == 0 and not start[0].finished, "Replay begins at gates without exposing final placing as live order")
	playback.set_speed(1)
	playback.advance(0.125)
	check.call(playback.sample()[0].distance > 0 and playback.sample()[0].distance < result.frames[1].runners[0].distance, "Replay interpolates movement between simulation frames")
	var elapsed := playback.elapsed
	playback.paused = true
	playback.advance(20)
	check.call(playback.elapsed == elapsed, "Paused playback does not advance")
	playback.paused = false
	playback.advance(-5)
	playback.advance(NAN)
	playback.set_speed(17)
	check.call(playback.elapsed == elapsed and playback.speed == 1, "Invalid delta and unsupported speed do not corrupt playback")
	var fast := RacePlayback.new()
	var slow := RacePlayback.new()
	fast.start(result)
	slow.start(result)
	fast.set_speed(8)
	slow.set_speed(1)
	fast.advance(4)
	for index: int in 64: slow.advance(0.5)
	check.call(JSON.stringify(fast.sample()) == JSON.stringify(slow.sample()), "Different frame steps and playback speeds reach identical race positions")
	var finish_time: float = result.record.finishers[0].finish_usec / 1000000.0
	playback.elapsed = finish_time - 0.00001
	var before_finish := playback.sample()
	check.call(not before_finish[0].finished and before_finish[0].distance < result.record.distance, "Leader stays before finish until stored crossing time")
	playback.elapsed = finish_time
	var at_finish := playback.sample()
	check.call(at_finish[0].finished and at_finish[0].gate == result.record.finishers[0].gate and at_finish[0].distance == result.record.distance, "Stored crossing time and live finish agree exactly")
	playback.advance(10000)
	check.call(playback.finished and playback.elapsed == playback.duration, "Automatic playback stops exactly at the final finisher")
	fast.skip()
	check.call(JSON.stringify(fast.sample()) == JSON.stringify(playback.sample()), "Skip and natural playback completion display identical final ranking")
	var repeated := playback.sample()
	playback.advance(10)
	playback.skip()
	check.call(JSON.stringify(playback.sample()) == JSON.stringify(repeated) and _snapshot(session) == state_before and JSON.stringify(result.frames) == input_before, "Replay completion, skip and sampling never mutate game, RNG, prizes or source frames")
	var restored := RacePlayback.new()
	restored.show_result(result.record)
	check.call(restored.finished and restored.frames.is_empty() and JSON.stringify(restored.sample()) == JSON.stringify(playback.sample()), "Result-only view reconstructs final screen without simulation or frame persistence")
	session.saves = SaveManager.new(directory.path_join("pending-race.json"))
	check.call(session.save_game().ok and session.load_game().ok and _snapshot(session) == state_before, "Saving during replay preserves pending result and committed rewards exactly")
	check.call(not session.acknowledge_race_result("race-999") and session.state.pending_race_result_id == result.record.id, "Stale acknowledgement cannot clear another result")
	check.call(session.acknowledge_race_result(result.record.id) and not session.acknowledge_race_result(result.record.id), "Result acknowledgement succeeds only once")
	check.call(session.state.pending_race_result_id.is_empty() and session.save_game().ok and session.load_game().ok and session.state.pending_race_result_id.is_empty(), "Acknowledged save returns to ranch instead of reopening result")
	var document := SaveCodec.encode(session.state, session.selected_horse_id)
	for pending: Variant in ["race-999", 1, null]:
		var bad := document.duplicate(true)
		bad.pending_race_result_id = pending
		check.call(not SaveCodec.decode(bad).ok, "Invalid pending result rejected: " + str(pending))
	var legacy := document.duplicate(true)
	legacy.schema_version = 3
	legacy.erase("pending_race_result_id")
	var decoded := SaveCodec.decode(legacy)
	check.call(decoded.ok and decoded.state.pending_race_result_id.is_empty() and decoded.state.race_results.size() == 1, "Schema 3 race saves migrate to ranch with all historical results intact")

func _snapshot(session: GameSession) -> String:
	return JSON.stringify(SaveCodec.encode(session.state, session.selected_horse_id), "", true, true)
