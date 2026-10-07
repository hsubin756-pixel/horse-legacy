class_name Horse
extends RefCounted

enum Sex { MALE, FEMALE }
enum LifeStage { FOAL, ADULT, DECEASED }
enum CareerStatus { UNRACED, ACTIVE, RETIRED }

var id: String = ""
var name: String = ""
var sex: Sex = Sex.MALE
# Weeks relative to the ranch's founding. Founders can have negative birth weeks.
var birth_week: int = 0
var father_id: String = "" # Empty means an unknown founder, never a fabricated ancestor.
var mother_id: String = ""
var breeder_farm_id: String = ""
var owner_farm_id: String = ""
var life_stage: LifeStage = LifeStage.ADULT
var career_status: CareerStatus = CareerStatus.UNRACED
var growth_type: StringName = &"normal"
var stats := StatBlock.new()
var potential := StatBlock.new()
var fitness: float = 80.0
var fatigue: float = 0.0
var stress: float = 0.0
var injury_weeks: int = 0
var starts: int = 0
var wins: int = 0
var earnings: int = 0
var race_result_ids: Array[String] = []

func age_years(current_week: int) -> int:
	return floori(float(maxi(0, current_week - birth_week)) / GameState.WEEKS_PER_YEAR)
