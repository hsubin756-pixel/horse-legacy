class_name SaveResult
extends RefCounted

var ok: bool = false
var message: String = ""
var state: GameState
var selected_horse_id: String = ""

static func failure(reason: String) -> SaveResult:
	var result := SaveResult.new()
	result.message = reason
	return result

static func success(game: GameState, selected: String, notice: String = "") -> SaveResult:
	var result := SaveResult.new()
	result.ok = true
	result.state = game
	result.selected_horse_id = selected
	result.message = notice
	return result
