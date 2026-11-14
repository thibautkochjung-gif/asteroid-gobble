class_name VectorBar
extends Control

# A segmented bar: a dark track with a thin outline, filled with short blocks up to `ratio`.
# Height comes from custom_minimum_size.y (VectorStyle.make_bar sets it).

const SEGMENT: float = 7.0
const GAP: float = 3.0

var ratio: float = 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var color: Color = VectorStyle.ACCENT:
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(40.0, 10.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var outline := Rect2(Vector2.ZERO, size)
	draw_rect(outline, VectorStyle.TRACK)
	draw_rect(outline, VectorStyle.LINE, false, 1.0)

	var inner := outline.grow(-2.0)
	var filled := inner.size.x * ratio
	var x := 0.0

	while x < filled:
		var width := minf(SEGMENT, filled - x)
		draw_rect(Rect2(inner.position + Vector2(x, 0.0), Vector2(width, inner.size.y)), color)
		x += SEGMENT + GAP
