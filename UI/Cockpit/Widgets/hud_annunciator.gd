@tool
class_name HudAnnunciator
extends Control

# A warning tile, sized to the opening of its socket in the panel art (74 x 36).
# Dark while all is well, so a lit tile always means something.

enum State { OFF, CAUTION, ALARM }

const BLINKS_PER_SECOND: float = 2.0

@export var state: State = State.OFF:
	set(value):
		if state == value:
			return

		state = value
		queue_redraw()
@export var text: String = "WARNING":
	set(value):
		if text == value:
			return

		text = value
		queue_redraw()
@export var font: Font
@export var font_size: int = 11

var _blink_time: float = 0.0
var _was_blink_on: bool = false # Redraw only when the blink flips, not every frame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if state != State.ALARM:
		return

	_blink_time += delta

	if _is_blink_on() != _was_blink_on:
		_was_blink_on = _is_blink_on()
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var face_color := CockpitPalette.TILE_OFF
	var text_color := CockpitPalette.TILE_OFF_TEXT
	var is_lit := state == State.CAUTION or state == State.ALARM and _is_blink_on()

	if is_lit:
		face_color = CockpitPalette.YELLOW if state == State.CAUTION else CockpitPalette.ALARM
		text_color = CockpitPalette.INK_DARK
		draw_rect(rect.grow(8.0), Color(face_color, 0.08))
		draw_rect(rect.grow(4.0), Color(face_color, 0.12))

	draw_rect(rect, face_color)
	var used_font := font if font != null else get_theme_default_font()
	HudText.draw_centered(self, used_font, text, rect.grow_individual(-4.0, 0.0, -4.0, 0.0), font_size, text_color)


func _is_blink_on() -> bool:
	return fmod(_blink_time * BLINKS_PER_SECOND, 1.0) < 0.6
