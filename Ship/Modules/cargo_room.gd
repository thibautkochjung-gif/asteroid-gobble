class_name CargoRoom
extends Room

# Stores smelted ore in compact liquid form, each ore counted separately.
# Amounts are counted in ore units: one ore cell melts into one unit (a rock cell into a tenth or so).
# The space they take here is cells * compaction.
# Capacity comes from the room's size: volume_per_texel for every texel of floor.
# The liquid is loose: thrust pushes it to the back of the hold (-x), so that's where it pools.
# It's drawn that way, and that's where its weight counts for the ship's centre of mass.

@export var volume_per_texel: float = 0.03 # A 17x24 texel room (the old size) holds about 12
@export_range(0.01, 1.0) var compaction: float = 0.05 # Liquid ore takes 5% of the raw ore's space

@export_group("Visuals")
@export var liquid_color: Color = Color(0.8, 0.72, 0.56)
@export var surface_color: Color = Color(0.92, 0.86, 0.7)
@export var stripe_color: Color = Color(0.83, 0.64, 0.16)
@export var stripe_dark_color: Color = Color(0.12, 0.11, 0.11)

var capacity_volume: float = 0.0 # In cell volumes, after compaction. Set from the size in _ready
var stored_cells: float = 0.0 # All ores together
var stored_by_ore: Dictionary[int, float] = {} # CellMaterials.Id -> units


func _ready() -> void:
	super()
	capacity_volume = get_area_texels() * volume_per_texel


func get_capacity_cells() -> float:
	return capacity_volume / compaction


func get_free_cells() -> float:
	return maxf(get_capacity_cells() - stored_cells, 0.0)


func get_stored_volume() -> float:
	return stored_cells * compaction


# Returns how many units were actually stored.
func store(ore_id: int, cells: float) -> float:
	var accepted := minf(cells, get_free_cells())

	if accepted <= 0.0:
		return 0.0

	stored_cells += accepted
	stored_by_ore[ore_id] = stored_by_ore.get(ore_id, 0.0) + accepted
	contents_changed.emit()
	return accepted


# Takes ore out (the cargo canister). Returns how many units were taken.
func take(ore_id: int, cells: float) -> float:
	var taken := minf(cells, stored_by_ore.get(ore_id, 0.0))

	if taken <= 0.0:
		return 0.0

	stored_by_ore[ore_id] -= taken
	stored_cells = maxf(stored_cells - taken, 0.0)

	if stored_by_ore[ore_id] <= 0.001:
		stored_by_ore.erase(ore_id)

	contents_changed.emit()
	return taken


func get_fill_ratio() -> float:
	return get_stored_volume() / capacity_volume


# Middle of the pool, which grows from the back wall.
func get_contents_center() -> Vector2:
	var inner := get_inner_rect()
	var pool_length := inner.size.x * clampf(get_fill_ratio(), 0.0, 1.0)
	return Vector2(inner.position.x + pool_length * 0.5, 0.0)


func get_status_text() -> String:
	return "%d / %d cells (%.1f / %.1f vol)" % [stored_cells, get_capacity_cells(), get_stored_volume(), capacity_volume]


func clear_contents() -> void:
	stored_cells = 0.0
	stored_by_ore.clear()
	contents_changed.emit()


func _draw_contents() -> void:
	var inner := get_inner_rect()
	var pool_length := snap_texel(inner.size.x * clampf(get_fill_ratio(), 0.0, 1.0))

	if pool_length > 0.0:
		draw_rect(Rect2(inner.position, Vector2(pool_length, inner.size.y)), liquid_color)
		draw_rect(Rect2(inner.position.x + pool_length - TEXEL, inner.position.y, TEXEL, inner.size.y), surface_color)

	# Hazard stripe along the front wall, where the ore comes in
	var y := inner.position.y

	while y < inner.end.y:
		var color := stripe_color if int(y / (TEXEL * 2.0)) % 2 == 0 else stripe_dark_color
		draw_rect(Rect2(inner.end.x - TEXEL, y, TEXEL, minf(TEXEL * 2.0, inner.end.y - y)), color)
		y += TEXEL * 2.0
