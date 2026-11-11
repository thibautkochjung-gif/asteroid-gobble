class_name HudText
extends RefCounted

# Text drawing shared by the cockpit widgets: centres text in a rect, shrinks the font size
# until it fits (module names vary in length), and can add a 1 px drop shadow.

const MIN_SIZE: int = 7


static func fit_size(font: Font, text: String, max_width: float, font_size: int) -> int:
	var fitted := font_size

	while fitted > MIN_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > max_width:
		fitted -= 1

	return fitted


static func draw_centered(item: CanvasItem, font: Font, text: String, rect: Rect2, font_size: int, color: Color, shadow: Color = Color.TRANSPARENT) -> void:
	var fitted := fit_size(font, text, rect.size.x, font_size)
	var ascent := font.get_ascent(fitted)
	var descent := font.get_descent(fitted)
	var baseline := rect.position.y + (rect.size.y + ascent - descent) / 2.0
	var origin := Vector2(rect.position.x, baseline)

	if shadow.a > 0.0:
		item.draw_string(font, origin + Vector2(0.0, 1.0), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted, shadow)

	item.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fitted, color)
