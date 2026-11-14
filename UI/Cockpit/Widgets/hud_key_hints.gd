class_name HudKeyHints
extends Control

# A row of key caps with what each key does, centred in the widget: "[K] NOSE IN  [L] NOSE OUT".
# Shows what a system can do right now (a bolted rock bolter), so the player doesn't have to look
# up the bindings. A lit cap is drawn pressed in. Knows nothing about the ship: the cockpit fills
# title and hints, and empties hints to hide it.

const KEY_PADDING := Vector2(6.0, 3.0)
const KEY_GAP: float = 5.0 # Between a key cap and its words
const HINT_GAP: float = 16.0 # Between two hints
const TITLE_GAP: float = 6.0 # Between the title and the row

@export var font_size: int = 14
@export var title_size: int = 11

var title: String = "":
	set(value):
		if title == value:
			return

		title = value
		queue_redraw()
var hints: Array[Dictionary] = []: # { "key": String, "text": String, "lit": bool }
	set(value):
		if hints == value:
			return

		hints = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if hints.is_empty():
		return

	var font := get_theme_default_font()
	var cap_height := font_size + KEY_PADDING.y * 2.0
	var baseline := size.y - KEY_PADDING.y - 2.0
	var x := (size.x - _get_row_width(font)) * 0.5

	if not title.is_empty():
		var title_at := Vector2(0.0, baseline - cap_height - TITLE_GAP)
		_draw_text(font, title_at, title, title_size, CockpitPalette.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)

	for hint in hints:
		var key: String = hint["key"]
		var text: String = hint["text"]
		var lit: bool = hint["lit"]
		var key_width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + KEY_PADDING.x * 2.0
		var press := 2.0 if lit else 0.0 # A lit cap sits lower: pressed in
		var cap := Rect2(x, baseline - font_size - KEY_PADDING.y + 2.0 + press, key_width, cap_height)

		draw_rect(Rect2(cap.position + Vector2(0.0, 2.0 - press), cap.size), CockpitPalette.SHADOW)
		draw_rect(cap, CockpitPalette.YELLOW_LIT if lit else CockpitPalette.YELLOW)
		draw_rect(cap, CockpitPalette.OUTLINE, false, 1.0)
		draw_string(font, Vector2(x + KEY_PADDING.x, baseline + press), key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CockpitPalette.INK_DARK)
		x += key_width + KEY_GAP

		_draw_text(font, Vector2(x, baseline), text, font_size, CockpitPalette.CREAM, HORIZONTAL_ALIGNMENT_LEFT)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + HINT_GAP


func _get_row_width(font: Font) -> float:
	var width := 0.0

	for hint in hints:
		var key: String = hint["key"]
		var text: String = hint["text"]
		width += font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + KEY_PADDING.x * 2.0 + KEY_GAP
		width += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + HINT_GAP

	return width - HINT_GAP


# With a dark outline, so it reads over space and over rock alike.
func _draw_text(font: Font, at: Vector2, text: String, text_size: int, color: Color, alignment: HorizontalAlignment) -> void:
	var width := size.x if alignment == HORIZONTAL_ALIGNMENT_CENTER else -1.0
	draw_string_outline(font, at, text, alignment, width, text_size, 4, CockpitPalette.SHADOW)
	draw_string(font, at, text, alignment, width, text_size, color)
