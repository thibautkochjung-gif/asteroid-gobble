@tool
class_name HudToggle
extends Control

# A toggle switch seen from above: a steel nut and a lever, up when on.
# Modules that can be jettisoned get a flip-up guard over the switch.
# Sized to the switch's recess in the panel art (26 x 28).

const NUT_RADIUS: float = 6.0
const BAT_WIDTH: float = 6.0
const BAT_LENGTH: float = 13.0

@export var is_on: bool = false:
	set(value):
		if is_on == value:
			return

		is_on = value
		queue_redraw()
@export var has_guard: bool = false:
	set(value):
		if has_guard == value:
			return

		has_guard = value
		queue_redraw()
@export var is_empty: bool = false: # No module on the mount: no lever
	set(value):
		if is_empty == value:
			return

		is_empty = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if is_empty:
		return

	var nut := Vector2(size.x / 2.0, 14.0 if is_on else 18.0)
	draw_circle(nut, NUT_RADIUS, CockpitPalette.OUTLINE)
	draw_circle(nut, NUT_RADIUS - 1.0, CockpitPalette.STEEL)
	draw_circle(nut - Vector2(1.5, 1.5), 2.0, Color(1.0, 1.0, 1.0, 0.35))

	var bat_top := nut.y - BAT_LENGTH if is_on else nut.y - 2.0
	var bat := Rect2(nut.x - BAT_WIDTH / 2.0, bat_top, BAT_WIDTH, BAT_LENGTH)
	draw_rect(Rect2(bat.position + Vector2(1.0, 2.0), bat.size), Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(bat, CockpitPalette.STEEL)
	draw_rect(Rect2(bat.position + Vector2(1.5, 0.0), Vector2(2.0, bat.size.y)), CockpitPalette.CREAM)
	draw_rect(bat, CockpitPalette.OUTLINE, false, 1.0)

	if has_guard:
		var guard := Rect2(-3.0, -3.0, size.x + 6.0, size.y + 6.0)
		draw_rect(guard, Color(CockpitPalette.YELLOW, 0.2))
		draw_rect(Rect2(guard.position + Vector2(2.0, 2.0), Vector2(guard.size.x - 4.0, 3.0)), Color(1.0, 1.0, 1.0, 0.22))
		draw_rect(guard, CockpitPalette.YELLOW, false, 2.0)
