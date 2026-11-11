class_name HubStyle
extends RefCounted

# Shared look for the station screens: the cockpit's colours (CockpitPalette), boxes and labels.

const PANEL_BG := Color(0.23, 0.22, 0.2)
const TAG_BG := Color(0.05, 0.075, 0.045, 0.88)
const TEXT := CockpitPalette.CREAM
const DIM := CockpitPalette.STEEL
const GOOD := CockpitPalette.SCOPE
const BAD := CockpitPalette.ALARM
const ACCENT := CockpitPalette.YELLOW_LIT


static func box(bg: Color, border: Color, border_width: int = 2, margin: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	return style


static func label(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override(&"font_size", font_size)
	result.add_theme_color_override(&"font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func button(text: String, font_size: int = 16) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(0, 36)
	result.add_theme_font_size_override(&"font_size", font_size)
	result.add_theme_stylebox_override(&"normal", box(CockpitPalette.YELLOW, CockpitPalette.OUTLINE, 3, 6))
	result.add_theme_stylebox_override(&"hover", box(CockpitPalette.YELLOW_LIT, CockpitPalette.OUTLINE, 3, 6))
	result.add_theme_stylebox_override(&"pressed", box(CockpitPalette.YELLOW_DARK, CockpitPalette.OUTLINE, 3, 6))
	result.add_theme_stylebox_override(&"disabled", box(CockpitPalette.STEEL_DARK, CockpitPalette.OUTLINE, 3, 6))
	result.add_theme_color_override(&"font_color", CockpitPalette.INK_DARK)
	result.add_theme_color_override(&"font_hover_color", CockpitPalette.INK_DARK)
	result.add_theme_color_override(&"font_pressed_color", CockpitPalette.CREAM)
	result.add_theme_color_override(&"font_disabled_color", CockpitPalette.STEEL)
	return result


# A choice in a list (field, insurance plan): toggles, one per ButtonGroup.
static func choice(text: String, group: ButtonGroup) -> Button:
	var result := Button.new()
	result.text = text
	result.toggle_mode = true
	result.button_group = group
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.custom_minimum_size = Vector2(0, 32)
	result.add_theme_font_size_override(&"font_size", 15)
	result.add_theme_stylebox_override(&"normal", box(Color(0.12, 0.12, 0.11), CockpitPalette.OUTLINE, 2, 6))
	result.add_theme_stylebox_override(&"hover", box(Color(0.16, 0.16, 0.14), GOOD, 2, 6))
	result.add_theme_stylebox_override(&"pressed", box(Color(0.1, 0.16, 0.08), GOOD, 2, 6))
	result.add_theme_stylebox_override(&"hover_pressed", box(Color(0.1, 0.16, 0.08), ACCENT, 2, 6))
	result.add_theme_stylebox_override(&"disabled", box(Color(0.1, 0.1, 0.1), CockpitPalette.OUTLINE, 2, 6))
	result.add_theme_color_override(&"font_color", TEXT)
	result.add_theme_color_override(&"font_pressed_color", GOOD)
	result.add_theme_color_override(&"font_hover_pressed_color", ACCENT)
	result.add_theme_color_override(&"font_disabled_color", CockpitPalette.TILE_OFF_TEXT)
	return result


static func format_credits(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""

	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","

		grouped += digits[i]

	return ("-" if amount < 0 else "") + grouped + " cr"
