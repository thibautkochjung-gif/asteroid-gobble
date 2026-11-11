class_name SmelterRoom
extends Room

# Receives gobbled chunks from the hangar and melts them into ore for the ingot holds.
#
# The chamber is physical: chunks inside are rigid bodies (SmelterChunk) that collide with each
# other and with the chamber's walls, so the room holds what physically fits, and no more.
# A gentle push sends them toward the furnace (the back wall), which melts the rearmost cell of
# the pile, one at a time. An ore cell gives one unit of its ore. A rock cell takes as long and
# as much power, but only gives rock_trace_yield of the chunk's ore (its traces): the rest is waste. Every chunk in the chamber glows orange, brighter while the furnace runs.
#
# The chamber has its own physics world: a SubViewport, which owns a separate physics space.
# Its coordinates are this room's coordinates, and its walls are static, so nothing lags behind
# the ship and nothing outside (hull, asteroids, lasers) can touch what's inside. The SubViewport
# is never rendered: this room draws the chunks itself (_draw).
# What you'd feel inside the moving ship is added as forces: the ship accelerates, the pile slides
# the other way; the ship spins, chunks are flung outward. (The smaller rotation effects are left out.)
#
# How a chunk gets in: the hangar asks can_accept_chunk() (see Room). True when the chunk fits in the chamber and
# an entry spot just inside the front wall is free. Entry spots are tried across the chamber's
# width (centre first), so chunks pile up side by side instead of in a single file. The chunk then rides the conveyor
# (CarriedChunk, no physics) to that spot and becomes a SmelterChunk there. One chunk on the
# conveyor at a time, so two can't land on the same spot.
# Stalls when the ingot holds are full, and slows down when the generator runs dry.
#
# The chamber fills the room, inside its walls, minus one texel at the back for the furnace grate.
# So a bigger slot gives a bigger chamber: more chunks fit, and bigger ones.

const WALL_LAYER: int = 1
const CHUNK_LAYER: int = 2

@export_range(0.01, 100.0) var smelt_rate: float = 1.6 # Cells per second
@export var power_per_second: float = 4.0 # Drawn while melting
@export var conveyor_speed: float = 40.0 # px/s, from the hangar doors to the chamber's entry
@export var heat_up_time: float = 1.0
@export_range(0.0, 1.0) var rock_trace_yield: float = 0.1 # Ore units from a rock cell. An ore cell gives 1

@export_group("Chamber")
@export var wall_thickness: float = 8.0
@export var entry_margin: float = 2.0 # Gap between a new chunk and the front wall
@export var entry_step: float = 4.0 # Spacing of the entry spots tried across the chamber
@export var push_acceleration: float = 60.0 # px/s² toward the furnace
@export var damping: float = 3.0 # Calms chunks down (relative to the ship: the chamber moves with it)
@export var melt_reach: float = 3.0 # px. Cells whose back edge is this close to the furnace can melt
@export var mass_per_cell: float = 0.1 # Keep equal to Asteroid.mass_per_cell
@export var max_inertial_acceleration: float = 1500.0 # px/s². Ignores spikes (collisions jolt the ship)

@export_group("Visuals")
@export var cold_color: Color = Color(0.16, 0.08, 0.07)
@export var hot_color: Color = Color(1.0, 0.45, 0.1)
@export var core_color: Color = Color(1.0, 0.9, 0.6)
@export var chunk_hot_color: Color = Color(1.0, 0.5, 0.15)
@export var roller_color: Color = Color(0.67, 0.36, 0.18)

var chamber: Rect2 # Inside the walls, in this room's space. Back = -x. Set from the size in _ready
var chunks: Array[SmelterChunk] = []
var incoming: CarriedChunk # On the conveyor, heading for the entry spot
var heat: float = 0.0 # 0..1
var is_working: bool = false

var _melt_progress: float = 0.0 # 0..1 toward the next cell
var _interior: SubViewport
var _last_ship_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	var inner := get_inner_rect()
	chamber = Rect2(inner.position.x + TEXEL, inner.position.y, inner.size.x - TEXEL, inner.size.y)
	_build_interior()


func _physics_process(delta: float) -> void:
	_receive_arrived_chunk()
	_apply_forces(delta)
	is_working = _smelt(delta)
	_update_heat(delta)

	if not chunks.is_empty():
		queue_redraw()


func _draw_contents() -> void:
	_draw_rollers()
	_draw_furnace()

	var glow := 0.65 + 0.35 * heat

	for chunk in chunks:
		draw_set_transform_matrix(chunk.transform)

		for id in chunk.draw_rects:
			var color := CellMaterials.get_material(id).color.lerp(chunk_hot_color, glow)

			for rect: Rect2i in chunk.draw_rects[id]:
				draw_rect(Rect2(Vector2(rect.position) * chunk.cell_size, Vector2(rect.size) * chunk.cell_size), color)

	draw_set_transform_matrix(Transform2D.IDENTITY)


func get_cells() -> int:
	var total := 0

	for chunk in chunks:
		total += chunk.get_cell_count()

	if incoming != null:
		total += incoming.get_cell_count()

	return total


# For display only: how many cells would tile the chamber's floor. The real limit is physical.
func get_capacity_cells() -> int:
	return roundi(chamber.get_area() / 16.0)


func takes_chunks() -> bool:
	return true


# True if the chunk could go in an empty chamber, at its current angle. Ignores what's inside.
func fits_chunk(asteroid: Asteroid) -> bool:
	return _fits(_get_footprint(asteroid))


func can_accept_chunk(asteroid: Asteroid) -> bool:
	if incoming != null:
		return false

	return _find_entry(_get_footprint(asteroid)) != Vector2.INF


# Swaps the asteroid chunk for a CarriedChunk at the same place, then sends it down the conveyor
# to the entry spot. It keeps its orientation relative to the ship.
# Looks for the entry spot again: a spot on the edge of being free can flip between two checks.
func receive_chunk(asteroid: Asteroid) -> bool:
	var entry := _find_entry(_get_footprint(asteroid))

	if entry == Vector2.INF:
		return false

	var chunk := CarriedChunk.create_from(asteroid)
	chunk.speed = conveyor_speed
	chunk.target = entry
	add_child(chunk)
	chunk.global_position = asteroid.get_global_center()
	chunk.global_rotation = asteroid.global_rotation
	incoming = chunk

	asteroid.remove_from_group(Asteroid.GROUP) # No more laser hits or second capture this frame
	asteroid.queue_free()
	contents_changed.emit()
	return true


func get_fill_ratio() -> float:
	return heat


# Centre of the pile, each chunk weighted by its cell count. Room centre when empty.
func get_contents_center() -> Vector2:
	var weighted := Vector2.ZERO
	var total := 0

	for chunk in chunks:
		var cell_count := chunk.get_cell_count()
		weighted += chunk.get_center() * cell_count
		total += cell_count

	if total == 0:
		return Vector2.ZERO

	return weighted / total


func get_status_text() -> String:
	var state := "smelting" if is_working else "idle"
	return "%d cells, %s" % [get_cells(), state]


func clear_contents() -> void:
	for chunk in chunks:
		chunk.queue_free()

	chunks.clear()

	if incoming != null:
		incoming.queue_free()
		incoming = null

	_melt_progress = 0.0
	contents_changed.emit()


# --- Chamber


func _build_interior() -> void:
	_interior = SubViewport.new()
	_interior.size = Vector2i(2, 2)
	_interior.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_interior.disable_3d = true
	add_child(_interior)

	var walls := StaticBody2D.new()
	walls.collision_layer = WALL_LAYER
	walls.collision_mask = 0
	_interior.add_child(walls)

	var t := wall_thickness
	var sides: Array[Rect2] = [
		Rect2(chamber.position.x - t, chamber.position.y - t, chamber.size.x + 2.0 * t, t), # Left side (-y)
		Rect2(chamber.position.x - t, chamber.end.y, chamber.size.x + 2.0 * t, t), # Right side (+y)
		Rect2(chamber.position.x - t, chamber.position.y, t, chamber.size.y), # Back, the furnace
		Rect2(chamber.end.x, chamber.position.y, t, chamber.size.y), # Front
	]

	for side in sides:
		var shape := RectangleShape2D.new()
		shape.size = side.size
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = side.get_center()
		walls.add_child(collision)


# The chunk's bounding box in this room's space, relative to its centre (cells are drawn and
# carried around their centre). Uses the chunk's current orientation relative to the ship.
func _get_footprint(asteroid: Asteroid) -> Rect2:
	var rotation_in_room := asteroid.global_rotation - global_rotation
	var center := asteroid.get_local_center()
	var footprint := Rect2()
	var is_first := true

	for cell in asteroid.cells:
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var point := ((Vector2(cell) + corner) * asteroid.cell_size - center).rotated(rotation_in_room)

			if is_first:
				footprint = Rect2(point, Vector2.ZERO)
				is_first = false
			else:
				footprint = footprint.expand(point)

	return footprint


# Where the chunk's centre can go: front edge entry_margin behind the front wall, and the first
# free spot across the chamber, from the centre outward. Vector2.INF if none is free, or if the
# chunk doesn't fit in the chamber at all.
func _find_entry(footprint: Rect2) -> Vector2:
	if not _fits(footprint):
		return Vector2.INF

	var x := chamber.end.x - entry_margin - footprint.end.x
	var center_y := chamber.get_center().y - footprint.get_center().y
	var max_offset := (chamber.size.y - footprint.size.y) * 0.5
	var offset := 0.0

	while offset <= max_offset + 0.01:
		for side: float in [1.0, -1.0]:
			var center := Vector2(x, center_y + offset * side)

			if _is_space_free(Rect2(footprint.position + center, footprint.size)):
				return center

			if offset == 0.0:
				break

		offset = minf(offset + entry_step, max_offset) if offset < max_offset else max_offset + 1.0

	return Vector2.INF


func _fits(footprint: Rect2) -> bool:
	return footprint.size.x <= chamber.size.x - entry_margin and footprint.size.y <= chamber.size.y


# Asks the chamber's physics space whether any chunk overlaps this box.
func _is_space_free(rect: Rect2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = rect.size

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = CHUNK_LAYER

	return _interior.world_2d.direct_space_state.intersect_shape(query, 1).is_empty()


# The conveyor delivered its chunk: it becomes a body in the chamber, at the same place.
# The carried chunk is drawn around its centre (pivot); the body's origin is the cell grid's origin.
func _receive_arrived_chunk() -> void:
	if incoming == null or not incoming.has_arrived():
		return

	var body := SmelterChunk.new()
	body.cells = incoming.cells
	body.revealed_ore = incoming.revealed_ore
	body.ore_type = incoming.ore_type
	body.cell_size = incoming.cell_size
	body.mass_per_cell = mass_per_cell
	body.collision_layer = CHUNK_LAYER
	body.collision_mask = WALL_LAYER | CHUNK_LAYER
	body.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.linear_damp = damping
	body.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.angular_damp = damping
	body.transform = incoming.transform * Transform2D(0.0, -incoming.pivot)
	_interior.add_child(body)
	chunks.append(body)

	incoming.queue_free()
	incoming = null
	contents_changed.emit()


# Push toward the furnace + what the ship's motion makes the chunks feel:
# - the ship accelerates by a: everything inside feels -a (rotated into the room's space);
# - the ship spins at w: a chunk at distance r from the spin centre is flung outward by w² r.
# apply_central_force lasts one physics step, so this runs every frame.
func _apply_forces(delta: float) -> void:
	var ship: RigidBody2D = null

	if ship_rooms != null:
		ship = ship_rooms.ship

	if ship == null:
		return

	if chunks.is_empty():
		_last_ship_velocity = ship.linear_velocity
		return

	var ship_acceleration := (ship.linear_velocity - _last_ship_velocity) / delta
	_last_ship_velocity = ship.linear_velocity
	ship_acceleration = ship_acceleration.limit_length(max_inertial_acceleration)

	var local_acceleration := global_transform.basis_xform_inv(ship_acceleration)
	var spin := ship.angular_velocity
	var room_from_spin_center := ship.to_local(global_position) - ship.center_of_mass

	for chunk in chunks:
		var from_spin_center := room_from_spin_center + chunk.get_center()
		var felt := Vector2.LEFT * push_acceleration - local_acceleration + from_spin_center * spin * spin
		chunk.apply_central_force(felt * chunk.mass)


# --- Smelting


# Returns true while melting.
func _smelt(delta: float) -> bool:
	if chunks.is_empty() or ship_rooms == null:
		return false

	var target := _find_cell_in_furnace()

	if target.is_empty():
		return false

	var target_chunk: SmelterChunk = target["chunk"]

	if ship_rooms.get_free_ingot_units() < _get_yield(target_chunk, target["cell"]):
		return false # Ingot holds full

	_melt_progress += smelt_rate * delta * _draw_power(delta)

	if _melt_progress >= 1.0:
		_melt_progress -= 1.0
		_melt(target["chunk"], target["cell"])

	return true


# The rearmost cell of the pile, if it touches the furnace. Empty dictionary otherwise.
func _find_cell_in_furnace() -> Dictionary:
	var best := {}
	var best_x := chamber.position.x + melt_reach

	for chunk in chunks:
		for cell in chunk.cells:
			var back_edge := (chunk.transform * chunk.get_cell_center(cell)).x - chunk.cell_size * 0.5

			if back_edge <= best_x:
				best_x = back_edge
				best = { "chunk": chunk, "cell": cell }

	return best


func _melt(chunk: SmelterChunk, cell: Vector2i) -> void:
	ship_rooms.store_ingots(chunk.ore_type, _get_yield(chunk, cell))
	chunk.remove_cell(cell)

	if chunk.get_cell_count() == 0:
		chunks.erase(chunk)
		chunk.queue_free()

	contents_changed.emit()


# Ore units this cell gives once melted.
func _get_yield(chunk: SmelterChunk, cell: Vector2i) -> float:
	if CellMaterials.is_ore(chunk.cells[cell]):
		return 1.0

	return rock_trace_yield


# --- Visuals


func _update_heat(delta: float) -> void:
	var target_heat := 1.0 if is_working else 0.0
	var new_heat := move_toward(heat, target_heat, delta / heat_up_time)

	if new_heat != heat:
		heat = new_heat
		queue_redraw()


# Conveyor rollers along the front wall, where chunks come in.
func _draw_rollers() -> void:
	var y := chamber.position.y + TEXEL

	while y < chamber.end.y - TEXEL:
		draw_rect(Rect2(chamber.end.x - TEXEL * 2.0, y, TEXEL * 2.0, TEXEL), roller_color)
		y += TEXEL * 3.0


# The furnace grate along the back wall: dark when cold, glowing when hot.
func _draw_furnace() -> void:
	var grate := Rect2(chamber.position.x - 2.0, chamber.position.y, 2.0, chamber.size.y)
	draw_rect(grate, cold_color.lerp(hot_color, heat))

	if heat > 0.5:
		var core := Rect2(grate.position.x + 1.0, grate.position.y + 2.0, 1.0, grate.size.y - 4.0)
		draw_rect(core, hot_color.lerp(core_color, heat * 2.0 - 1.0))


# Returns the share of the needed power the generator could give, 0..1.
func _draw_power(delta: float) -> float:
	var power := ship_rooms.power
	var needed := power_per_second * delta

	if power == null or needed <= 0.0:
		return 1.0

	return power.draw_power(needed) / needed
