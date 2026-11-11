@tool
class_name HudLever
extends Control

# The hangar door lever. The slot is in the panel art; this draws the rod and the yellow knob.
# open_amount: 0 = closed (knob down), 1 = open (knob up). Follows Hangar.open_amount, so it
# moves with the doors.

const KNOB_SIZE := Vector2(24.0, 16.0)
const KNOB_TOP: float = 4.0 # Knob's top edge when open
const KNOB_BOTTOM: float = 52.0 # ...and when closed
const PIVOT_Y: float = 38.0 # Middle of the slot

@export_range(0.0, 1.0) var open_amount: float = 0.0:
	set(value):
		if open_amount == value:
			return

		open_amount = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center_x := size.x / 2.0
	var knob_top := lerpf(KNOB_BOTTOM, KNOB_TOP, open_amount)
	var knob := Rect2(center_x - KNOB_SIZE.x / 2.0, knob_top, KNOB_SIZE.x, KNOB_SIZE.y)
	var rod_end := knob.get_center().y

	draw_line(Vector2(center_x, PIVOT_Y), Vector2(center_x, rod_end), CockpitPalette.STEEL, 6.0)
	draw_line(Vector2(center_x - 1.0, PIVOT_Y), Vector2(center_x - 1.0, rod_end), CockpitPalette.CREAM, 2.0)

	draw_rect(Rect2(knob.position + Vector2(2.0, 3.0), knob.size), Color(0.0, 0.0, 0.0, 0.5))
	draw_rect(knob, CockpitPalette.YELLOW)
	draw_rect(Rect2(knob.position.x, knob.end.y - 3.0, knob.size.x, 3.0), CockpitPalette.YELLOW_DARK)
	draw_rect(Rect2(knob.position + Vector2(3.0, 2.0), Vector2(knob.size.x - 6.0, 3.0)), Color(1.0, 1.0, 1.0, 0.4))
	draw_rect(knob, CockpitPalette.OUTLINE, false, 2.0)
