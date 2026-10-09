class_name RaceTrack
extends Control

var rows: Array[Dictionary] = []
var race_distance: float = 1600.0

func _ready() -> void:
	custom_minimum_size = Vector2(640, 245)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func display(value: Array[Dictionary], distance: float) -> void:
	rows = value.duplicate(true)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.gate < b.gate)
	race_distance = distance
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var left := 184.0
	var width := maxf(100.0, size.x - left - 40.0)
	var lane_height := 46.0
	draw_rect(Rect2(Vector2(left - 14, 26), Vector2(width + 35, rows.size() * lane_height)), Color("263d2c"))
	for mark: int in 5:
		var x := left + width * mark / 4.0
		draw_line(Vector2(x, 28), Vector2(x, 26 + rows.size() * lane_height), Color("617159"), 1.0)
		draw_string(font, Vector2(x - 15, 19), "%dm" % (race_distance * mark / 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, RanchTheme.MUTED)
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var y := 49.0 + index * lane_height
		var color := RanchTheme.GOLD if row.owned else Color("bed2c0")
		draw_string(font, Vector2(4, y + 5), "%d %s" % [row.gate, row.name], HORIZONTAL_ALIGNMENT_LEFT, 168, 15, color)
		draw_line(Vector2(left - 14, y + 23), Vector2(left + width + 21, y + 23), Color("4e6148"), 1.0)
		var position := Vector2(left + width * clampf(row.distance / race_distance, 0.0, 1.0), y)
		_draw_horse(position, color)
	draw_line(Vector2(left + width, 25), Vector2(left + width, 26 + rows.size() * lane_height), RanchTheme.GOLD, 3.0)

func _draw_horse(p: Vector2, color: Color) -> void:
	draw_style_box(_body_style(color), Rect2(p + Vector2(-11, -5), Vector2(20, 10)))
	draw_line(p + Vector2(6, -2), p + Vector2(10, -12), color, 5)
	draw_circle(p + Vector2(13, -12), 4, color)
	draw_line(p + Vector2(-9, 2), p + Vector2(-12, 12), color, 3)
	draw_line(p + Vector2(6, 2), p + Vector2(10, 12), color, 3)
	draw_line(p + Vector2(-10, -3), p + Vector2(-17, -8), color, 2)

func _body_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style
