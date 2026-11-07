class_name CarriedChunk
extends Node2D

# Stand-in for an asteroid chunk once it is inside the ship.
# It copies the chunk's cells (so it looks exactly like the chunk did when it crossed the doors),
# rides the conveyor to its target, and loses cells one by one as the smelter melts them.
# No physics: inside the ship, a chunk only needs to be drawn and moved.

var cells: Dictionary[Vector2i, int] = {} # Cell -> CellMaterials.Id
var revealed_ore: Dictionary[Vector2i, bool] = {}
var ore_type: int = CellMaterials.Id.NICKEL_IRON
var cell_size: float = 4.0
var hot_color: Color = Color(1.0, 0.45, 0.1)
var heat: float = 0.0 # 0..1, tints the cells toward hot_color
var pivot: Vector2 = Vector2.ZERO # Point of the cell grid (local px) that sits on this node's origin
var target: Vector2 = Vector2.ZERO # In the parent's space
var speed: float = 40.0 # px/s along the conveyor


static func create_from(asteroid: Asteroid) -> CarriedChunk:
	var chunk := CarriedChunk.new()
	chunk.cell_size = asteroid.cell_size
	chunk.ore_type = asteroid.ore_type
	chunk.pivot = asteroid.get_local_center()

	for cell in asteroid.cells:
		chunk.cells[cell] = asteroid.cells[cell]

	for cell in asteroid.revealed_ore:
		chunk.revealed_ore[cell] = true

	return chunk


func _physics_process(delta: float) -> void:
	if not has_arrived():
		position = position.move_toward(target, speed * delta)


func _draw() -> void:
	for cell in cells:
		var id := CellMaterials.get_display_id(cells[cell], revealed_ore.has(cell))
		var color := CellMaterials.get_material(id).color.lerp(hot_color, heat * 0.7)
		draw_rect(Rect2(Vector2(cell) * cell_size - pivot, Vector2(cell_size, cell_size)), color)


func has_arrived() -> bool:
	return position == target


func set_heat(value: float) -> void:
	if value == heat:
		return

	heat = value
	queue_redraw()


func get_cell_count() -> int:
	return cells.size()


# Melts from the outside in: removes the cell farthest from the chunk's current centre.
func remove_outermost_cell() -> void:
	if cells.is_empty():
		return

	var center := _get_center()
	var outermost: Vector2i = cells.keys()[0]
	var best_distance := -1.0

	for cell in cells:
		var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(center)

		if distance > best_distance:
			best_distance = distance
			outermost = cell

	cells.erase(outermost)
	revealed_ore.erase(outermost)
	queue_redraw()


# In cell units.
func _get_center() -> Vector2:
	var sum := Vector2.ZERO

	for cell in cells:
		sum += Vector2(cell) + Vector2(0.5, 0.5)

	return sum / cells.size()
