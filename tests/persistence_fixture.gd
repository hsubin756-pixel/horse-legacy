extends RefCounted

static func session_for_test(path: String) -> GameSession:
	var session := GameSession.new()
	session.saves = SaveManager.new(path)
	session.new_game(24681357)
	var state: GameState = session.state
	state.current_week = 53
	state.player_farm.name = "이어지는 목장"
	state.player_farm.money = 12500
	state.player_farm.reputation = 7
	var sire: Horse = state.owned_horses()[0]
	sire.stats.values[&"speed"] = 59.125
	sire.fatigue = 22.5
	sire.stress = 14.25
	sire.injury_weeks = 2
	sire.growth_type = &"late"
	var ancestor := Horse.new()
	ancestor.id = state.allocate_id("horse")
	ancestor.name = "Old Lantern"
	ancestor.birth_week = -600
	ancestor.career_status = Horse.CareerStatus.RETIRED
	ancestor.life_stage = Horse.LifeStage.DECEASED
	state.horses[ancestor.id] = ancestor
	sire.father_id = ancestor.id
	sire.breeder_farm_id = state.player_farm.id
	session.select_horse(state.player_farm.horse_ids[1])
	for index: int in 7:
		state.rng.randi()
	return session
