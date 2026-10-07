class_name RanchTheme
extends RefCounted

const PAPER := Color("eee8d7")
const MUTED := Color("b2bba9")
const GOLD := Color("d8b879")

static func panel(color: Color, padding: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK KR", "Malgun Gothic", "Apple SD Gothic Neo"])
	result.default_font = font
	result.default_font_size = 17
	result.set_color("font_color", "Label", PAPER)
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", Color.WHITE)
	result.set_stylebox("normal", "Button", panel(Color("243a30"), 16))
	result.set_stylebox("hover", "Button", panel(Color("345440"), 16))
	result.set_stylebox("pressed", "Button", panel(Color("426049"), 16))
	var focus := panel(Color(0, 0, 0, 0), 16)
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	result.set_stylebox("focus", "Button", focus)
	result.set_stylebox("panel", "PanelContainer", panel(Color("192c24"), 22))
	result.set_stylebox("background", "ProgressBar", panel(Color("101d18"), 0))
	result.set_stylebox("fill", "ProgressBar", panel(Color("b89c63"), 0))
	result.set_constant("separation", "VBoxContainer", 12)
	return result

static func label(text: String, size: int = 17, color: Color = PAPER) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result
