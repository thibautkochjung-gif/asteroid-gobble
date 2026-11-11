@tool
class_name HudTapeText
extends Control

# Felt-pen writing on a strip of masking tape. The tape is in the panel art: size and rotate this
# node to match it (set pivot_offset to the centre). The text shrinks to fit long module names.

const MIN_READABLE_SIZE: int = 9

@export var text: String = "LABEL":
	set(value):
		if text == value:
			return

		text = value
		queue_redraw()
@export var font: Font
@export var font_size: int = 11
@export var color: Color = CockpitPalette.MARKER_INK


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var used_font := font if font != null else get_theme_default_font()
	var rect := Rect2(Vector2(3.0, 0.0), size - Vector2(6.0, 0.0))
	HudText.draw_centered(self, used_font, _shorten(used_font, rect.size.x), rect, font_size, color)


# Tape is short: a name that won't fit at a readable size keeps only its longest word
# ("HARPOON WINCH" becomes "HARPOON"), the way someone with a felt pen would write it.
func _shorten(used_font: Font, width: float) -> String:
	if used_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_READABLE_SIZE).x <= width:
		return text

	var longest := ""

	for word in text.split(" ", false):
		if word.length() > longest.length():
			longest = word

	return longest
