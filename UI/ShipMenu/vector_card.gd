class_name VectorCard
extends PanelContainer

# A panel with cyan brackets on its corners. Put content in `body`.

const BRACKET: float = 9.0

var body := VBoxContainer.new()


func _init() -> void:
	body.add_theme_constant_override("separation", 8)
	add_child(body)


func _draw() -> void:
	var corners := [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]

	for corner: Vector2 in corners:
		var x_dir := 1.0 if corner.x == 0.0 else -1.0
		var y_dir := 1.0 if corner.y == 0.0 else -1.0
		var points := PackedVector2Array([corner + Vector2(0.0, BRACKET * y_dir), corner, corner + Vector2(BRACKET * x_dir, 0.0)])
		draw_polyline(points, VectorStyle.ACCENT, 2.0)
