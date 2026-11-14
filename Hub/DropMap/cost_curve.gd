class_name CostCurve
extends Control

# A small chart of one part of the drop fee: a curve over its range, and a marker where the
# current drop point sits on it. Used twice on the undock screen (line fare, transfer).

const SAMPLES: int = 40
const PAD := Vector2(10.0, 8.0)

var title: String = ""
var curve: Callable # float (x) -> float (y)
var x_max: float = 1.0
var y_min: float = 0.0
var y_max: float = 1.0
var color := CockpitPalette.YELLOW_LIT
var left_text: String = "0"
var right_text: String = ""
var top_text: String = ""
var marker_x: float = 0.0
var marker_text: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 84.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_marker(x: float, text: String) -> void:
	marker_x = x
	marker_text = text
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.09))
	draw_rect(Rect2(Vector2.ZERO, size), CockpitPalette.OUTLINE, false, 2.0)
	draw_string(font, PAD + Vector2(0.0, 11.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HubStyle.DIM)

	var plot := Rect2(PAD + Vector2(0.0, 18.0), size - PAD * 2.0 - Vector2(0.0, 32.0))
	draw_line(plot.position, Vector2(plot.position.x, plot.end.y), CockpitPalette.STEEL_DARK, 1.0)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, CockpitPalette.STEEL_DARK, 1.0)

	var points := PackedVector2Array()

	for i in SAMPLES + 1:
		var x := x_max * i / SAMPLES
		points.append(_to_plot(plot, x, curve.call(x)))

	draw_polyline(points, color, 2.0, true)

	var marker := _to_plot(plot, clampf(marker_x, 0.0, x_max), curve.call(clampf(marker_x, 0.0, x_max)))
	draw_dashed_line(marker, Vector2(marker.x, plot.end.y), HubStyle.TEXT, 1.0, 3.0)
	draw_circle(marker, 4.0, CockpitPalette.ALARM)
	draw_circle(marker, 4.0, CockpitPalette.OUTLINE, false, 1.0)

	# Marker text on the side with room for it.
	var text_size := font.get_string_size(marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var text_x := marker.x + 6.0 if marker.x + 6.0 + text_size.x < plot.end.x else marker.x - 6.0 - text_size.x
	draw_string(font, Vector2(text_x, maxf(marker.y - 4.0, plot.position.y + 10.0)), marker_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HubStyle.TEXT)

	var bottom := size.y - PAD.y
	draw_string(font, Vector2(plot.position.x, bottom), left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HubStyle.DIM)
	draw_string(font, Vector2(plot.end.x - font.get_string_size(right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, bottom), right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HubStyle.DIM)
	draw_string(font, Vector2(plot.end.x - font.get_string_size(top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, PAD.y + 11.0), top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HubStyle.DIM)


func _to_plot(plot: Rect2, x: float, y: float) -> Vector2:
	var u := x / x_max
	var v := inverse_lerp(y_min, y_max, y)
	return Vector2(plot.position.x + u * plot.size.x, plot.end.y - v * plot.size.y)
