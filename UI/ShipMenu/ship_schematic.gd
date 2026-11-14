class_name ShipSchematic
extends Control

# The ship from above, nose up, in vector lines: the hull from its collision shapes
# (HudLoadout.get_hull_polygons) and a square on each part, coloured by its health.
# Drawn once per refresh: the menu pauses the game, nothing moves while it's open.

const MARGIN: float = 14.0
const MARK_SIZE: float = 8.0

var ship: RigidBody2D
var ship_damage: ShipDamage


func _init() -> void:
	custom_minimum_size = Vector2(220.0, 280.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(new_ship: RigidBody2D, new_ship_damage: ShipDamage) -> void:
	ship = new_ship
	ship_damage = new_ship_damage
	queue_redraw()


func _draw() -> void:
	if ship == null:
		return

	var polygons := HudLoadout.get_hull_polygons(ship)

	if polygons.is_empty():
		return

	# Nose up: the ship's +x becomes the screen's -y.
	var bounds := Rect2(_turn(polygons[0][0]), Vector2.ZERO)

	for polygon in polygons:
		for point in polygon:
			bounds = bounds.expand(_turn(point))

	var available := Rect2(Vector2.ONE * MARGIN, size - Vector2.ONE * MARGIN * 2.0)
	var scale_factor := minf(available.size.x / bounds.size.x, available.size.y / bounds.size.y)
	var origin := available.position + (available.size - bounds.size * scale_factor) / 2.0 - bounds.position * scale_factor

	for polygon in polygons:
		var points := PackedVector2Array()

		for point in polygon:
			points.append(origin + _turn(point) * scale_factor)

		draw_colored_polygon(points, Color(VectorStyle.ACCENT, 0.05))
		points.append(points[0])
		draw_polyline(points, VectorStyle.ACCENT, 1.5)

	if ship_damage == null:
		return

	for part in ship_damage.get_parts():
		var color := VectorStyle.get_health_color(ShipDamage.get_health(part).get_ratio())

		for point in ShipDamage.get_damage_points(part):
			var at := origin + _turn(ship.to_local(point)) * scale_factor
			var mark := Rect2(at - Vector2.ONE * MARK_SIZE / 2.0, Vector2.ONE * MARK_SIZE)
			draw_rect(mark, Color(color, 0.3))
			draw_rect(mark, color, false, 1.5)


func _turn(point: Vector2) -> Vector2:
	return Vector2(point.y, -point.x)
