class_name SmelterChunk
extends RigidBody2D

# A chunk inside a smelter's chamber. It lives in the chamber's own physics world
# (see SmelterRoom), so its coordinates are the room's coordinates.
# Collision uses the same merged rectangles as Asteroid (Asteroid.merge_cells).
# Unlike an asteroid it never splits: when the furnace melts a cell, the rest stays one body even
# if it's no longer connected. It's a lump of rock being melted down, not a free-flying asteroid.
# It isn't drawn by itself (its world is never rendered): SmelterRoom draws it, from rects.

var cells: Dictionary[Vector2i, int] = {} # Cell -> CellMaterials.Id
var revealed_ore: Dictionary[Vector2i, bool] = {}
var ore_type: int = CellMaterials.Id.NICKEL_IRON # Rock cells hold traces of it
var cell_size: float = 4.0
var mass_per_cell: float = 0.1
var rects: Array[Rect2i] = [] # Cells merged into rectangles, in cell units. For collision
var draw_rects: Dictionary[int, Array] = {} # Display material id -> rectangles. For SmelterRoom's drawing

var _local_center: Vector2 = Vector2.ZERO
var _rect_shapes: Dictionary[Vector2i, RectangleShape2D] = {} # One resource per rectangle size, reused


func _ready() -> void:
	gravity_scale = 0.0
	can_sleep = false # The push and the ship's motion act on it every frame
	_rebuild()


func get_cell_count() -> int:
	return cells.size()


func remove_cell(cell: Vector2i) -> void:
	cells.erase(cell)
	revealed_ore.erase(cell)

	if not cells.is_empty():
		_rebuild()


# Centre of a cell, in this body's space.
func get_cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


# Centre of all cells, in the parent's space (the chamber's space).
func get_center() -> Vector2:
	return transform * _local_center


# One shape owner per rectangle, placed on the rectangle's centre so Godot computes the right
# centre of mass (same reason as in Asteroid._rebuild_shapes).
func _rebuild() -> void:
	rects = Asteroid.merge_cells(cells.keys())
	draw_rects = Asteroid.merge_cells_by_look(cells, revealed_ore)

	for owner_id in get_shape_owners():
		remove_shape_owner(owner_id)

	for rect in rects:
		var owner_id := create_shape_owner(self)
		var center := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * cell_size
		shape_owner_set_transform(owner_id, Transform2D(0.0, center))
		shape_owner_add_shape(owner_id, _get_rect_shape(rect.size))

	var sum := Vector2.ZERO

	for cell in cells:
		sum += get_cell_center(cell)

	_local_center = sum / cells.size()
	mass = cells.size() * mass_per_cell


func _get_rect_shape(size_in_cells: Vector2i) -> RectangleShape2D:
	if not _rect_shapes.has(size_in_cells):
		var shape := RectangleShape2D.new()
		shape.size = Vector2(size_in_cells) * cell_size
		_rect_shapes[size_in_cells] = shape

	return _rect_shapes[size_in_cells]
