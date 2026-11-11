class_name OreBinRoom
extends Room

# Stores raw cells, one by one, as the grinder leaves them: the player can't smelt yet, so ore
# goes home unrefined. Raw ore sells for the same as smelted ore; it just takes far more room.
#
# Cells get in two ways: the hangar hands over single-cell chunks (receive_chunk), and the grinder
# mills small chunks straight into the bin (store_cell).
# Each cell remembers its material and, for rock, the ore of the asteroid it came from: a rock cell
# is worth rock_trace_yield of that ore, like in the smelter.
#
# Capacity is a grid: one cell per cell_size square of floor, inside the walls. The cells stack up
# from the back wall (-x), column by column, so the drawing shows exactly what's inside.

@export var cell_size: float = 4.0 # Keep equal to Asteroid.cell_size
@export_range(0.0, 1.0) var rock_trace_yield: float = 0.1 # Keep equal to SmelterRoom.rock_trace_yield

@export_group("Visuals")
@export var grate_color: Color = Color(0.2, 0.2, 0.23)
@export var stripe_color: Color = Color(0.83, 0.64, 0.16)
@export var stripe_dark_color: Color = Color(0.12, 0.11, 0.11)

# One entry per cell, in the order they came in. x = CellMaterials.Id, y = the ore it counts as
# (the material itself for an ore cell, the asteroid's ore for a rock cell).
var contents: Array[Vector2i] = []

var _columns: int = 0 # Along x, from the back wall
var _rows: int = 0 # Across the room


func _ready() -> void:
	super()
	var inner := _get_bin_rect()
	_columns = floori(inner.size.x / cell_size)
	_rows = floori(inner.size.y / cell_size)


func get_capacity_cells() -> int:
	return _columns * _rows


func get_cell_count() -> int:
	return contents.size()


func get_free_cells() -> int:
	return maxi(get_capacity_cells() - contents.size(), 0)


# Returns false if the bin is full.
func store_cell(material_id: int, ore_type: int) -> bool:
	if get_free_cells() <= 0:
		return false

	var counts_as := material_id if CellMaterials.is_ore(material_id) else ore_type
	contents.append(Vector2i(material_id, counts_as))
	contents_changed.emit()
	return true


# Takes up to max_cells out, the last ones in first (the ore canister). Returns them.
func take_cells(max_cells: int) -> Array[Vector2i]:
	var taken: Array[Vector2i] = []

	while taken.size() < max_cells and not contents.is_empty():
		taken.append(contents.pop_back())

	if not taken.is_empty():
		contents_changed.emit()

	return taken


# What the cells are worth once sold: CellMaterials.Id of the ore -> units.
func get_ore_value() -> Dictionary[int, float]:
	var value: Dictionary[int, float] = {}

	for entry in contents:
		var units := 1.0 if CellMaterials.is_ore(entry.x) else rock_trace_yield
		value[entry.y] = value.get(entry.y, 0.0) + units

	return value


# CellMaterials.Id -> cells. For the menus.
func get_cells_by_material() -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {}

	for entry in contents:
		counts[entry.x] = counts.get(entry.x, 0) + 1

	return counts


func get_fill_ratio() -> float:
	if get_capacity_cells() == 0:
		return 0.0

	return float(contents.size()) / get_capacity_cells()


# Middle of the filled columns, which grow from the back wall.
func get_contents_center() -> Vector2:
	var inner := _get_bin_rect()
	var filled_columns := ceilf(float(contents.size()) / maxi(_rows, 1))
	return Vector2(inner.position.x + filled_columns * cell_size * 0.5, 0.0)


func get_status_text() -> String:
	return "%d / %d cells" % [contents.size(), get_capacity_cells()]


func clear_contents() -> void:
	contents.clear()
	contents_changed.emit()


# --- Taking chunks from the hold: single cells only. The grinder brings everything else down to that.


func takes_chunks() -> bool:
	return true


func fits_chunk(chunk: Asteroid) -> bool:
	return chunk.cells.size() == 1


func can_accept_chunk(chunk: Asteroid) -> bool:
	return fits_chunk(chunk) and get_free_cells() > 0


func receive_chunk(chunk: Asteroid) -> bool:
	if not can_accept_chunk(chunk):
		return false

	var cell: Vector2i = chunk.cells.keys()[0]

	if not store_cell(chunk.cells[cell], chunk.ore_type):
		return false

	chunk.remove_from_group(Asteroid.GROUP) # No more laser hits or second capture this frame
	chunk.queue_free()
	return true


# --- Drawing


# Inside the walls, minus the hazard stripe along the front wall.
func _get_bin_rect() -> Rect2:
	var inner := get_inner_rect()
	inner.size.x -= TEXEL
	return inner


func _draw_contents() -> void:
	var inner := _get_bin_rect()
	draw_rect(inner, grate_color)

	for i in contents.size():
		@warning_ignore("integer_division")
		var column := i / _rows
		var row := i % _rows
		var corner := inner.position + Vector2(column, row) * cell_size
		var color := CellMaterials.get_material(contents[i].x).color
		draw_rect(Rect2(corner, Vector2(cell_size, cell_size)), color)
		draw_rect(Rect2(corner + Vector2(cell_size - TEXEL, cell_size - TEXEL), Vector2(TEXEL, TEXEL)), color.darkened(0.25)) # A shaded corner, so neighbours read as separate cells

	# Hazard stripe along the front wall, where the cells come in
	var full_inner := get_inner_rect()
	var y := full_inner.position.y

	while y < full_inner.end.y:
		var color := stripe_color if int(y / (TEXEL * 2.0)) % 2 == 0 else stripe_dark_color
		draw_rect(Rect2(full_inner.end.x - TEXEL, y, TEXEL, minf(TEXEL * 2.0, full_inner.end.y - y)), color)
		y += TEXEL * 2.0
