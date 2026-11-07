class_name MapMarkers
extends Control

# Marks the props that want to be found (beacons, probes, flares, the cache, lost modules):
# a bracket and a label on screen, an arrow with the distance at the edge of the screen when off it.
# Each prop says what its label is (SpaceProp.get_marker_text): empty = no marker.
# Screen-space overlay: lives in the HUD's CanvasLayer, reads the camera through the viewport's
# canvas transform.

@export var ship: Node2D # Distances are measured from it
@export var edge_margin: float = 28.0 # px from the screen's edge
@export var font_size: int = 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var canvas := get_viewport().get_canvas_transform()
	var screen := get_viewport_rect()
	var inner := screen.grow(-edge_margin)
	var font := get_theme_default_font()

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		var prop := node as SpaceProp

		if prop == null:
			continue

		var text := prop.get_marker_text()

		if text.is_empty():
			continue

		var color := prop.get_marker_color()
		var at := canvas * prop.global_position

		if inner.has_point(at):
			_draw_bracket(at, color)
			draw_string(font, at + Vector2(10.0, -8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			continue

		var center := screen.get_center()
		var direction := (at - center).normalized()
		var edge := _clamp_to_rect(center, direction, inner)
		var distance := ship.global_position.distance_to(prop.global_position) if ship != null else 0.0
		_draw_arrow(edge, direction, color)

		var label := "%s  %d" % [text, roundi(distance)]
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var label_at := (edge - direction * 22.0 - label_size * 0.5).clamp(screen.position, screen.end - label_size)
		draw_string(font, label_at + Vector2(0.0, label_size.y * 0.75), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# Where a ray from `from` along `direction` leaves the rectangle.
func _clamp_to_rect(from: Vector2, direction: Vector2, rect: Rect2) -> Vector2:
	var t := INF

	if direction.x > 0.0:
		t = minf(t, (rect.end.x - from.x) / direction.x)
	elif direction.x < 0.0:
		t = minf(t, (rect.position.x - from.x) / direction.x)

	if direction.y > 0.0:
		t = minf(t, (rect.end.y - from.y) / direction.y)
	elif direction.y < 0.0:
		t = minf(t, (rect.position.y - from.y) / direction.y)

	return from + direction * t


func _draw_bracket(at: Vector2, color: Color) -> void:
	var half_size := 7.0
	var arm := 3.0

	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var point: Vector2 = at + corner * half_size
		draw_line(point, point - Vector2(corner.x * arm, 0.0), color, 1.5)
		draw_line(point, point - Vector2(0.0, corner.y * arm), color, 1.5)


func _draw_arrow(tip: Vector2, direction: Vector2, color: Color) -> void:
	var side := direction.orthogonal() * 6.0
	var back := tip - direction * 12.0
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), color)
