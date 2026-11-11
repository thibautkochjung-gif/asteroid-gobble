@tool
class_name HudLed
extends Control

# A round indicator light, centred in its rect. Display only: Cockpit sets the state.
# The dark socket around it is in the panel art.

enum State { OFF, READY, ACTIVE, ALARM }

const BLINKS_PER_SECOND: float = 2.5

@export var state: State = State.OFF:
	set(value):
		if state == value:
			return

		state = value
		queue_redraw()
@export var radius: float = 3.6

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
	var center := size / 2.0
	var color := _get_color()
	var is_lit := state == State.ACTIVE or state == State.ALARM and _is_blink_on()

	if is_lit:
		draw_circle(center, radius * 3.2, Color(color, 0.1))
		draw_circle(center, radius * 2.0, Color(color, 0.22))

	draw_circle(center, radius, color)

	var shine_alpha := 0.5 if is_lit else 0.15
	draw_circle(center - Vector2.ONE * radius * 0.35, radius * 0.35, Color(1.0, 1.0, 1.0, shine_alpha))


func _get_color() -> Color:
	match state:
		State.READY:
			return CockpitPalette.READY
		State.ACTIVE:
			return CockpitPalette.YELLOW_LIT
		State.ALARM:
			return CockpitPalette.ALARM if _is_blink_on() else CockpitPalette.LED_OFF

	return CockpitPalette.LED_OFF


func _is_blink_on() -> bool:
	return fmod(_blink_time * BLINKS_PER_SECOND, 1.0) < 0.5
