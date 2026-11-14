class_name SmelterRoom
extends Room

# Receives gobbled chunks from the hangar, melts them, then refines the melt into ore for the
# ingot holds. Two steps:
# - Melting is fast. Chunks inside are rigid bodies (SmelterChunk) pushed toward the back, where
#   a molten pool sits. Cells touching the pool's surface melt into it, melt_rate cells a second.
# - Refining is slow, and it's the real work. The pool is refined at refine_rate cells a second;
#   what comes out goes to the ingot holds, the rest is waste. An ore cell gives one unit of its
#   ore. A rock cell takes as long, but only gives rock_trace_yield of the
#   chunk's ore (its traces).
# Molten metal takes less room than a solid chunk (liquid_volume of a cell's area): the pool fills
# the back of the chamber and its surface moves forward as it grows (the back wall moves with it).
# The pool can fill up to max_pool_share of the chamber's length (most of it: the rest is a strip
# by the front wall, where the conveyor feeds chunks in). Then melting stops and chunks wait in the
# chamber until refining has made room. Capacity is counted in molten cells (get_capacity_cells). Everything inside glows, brighter while the
# furnace runs.
#
# How melting looks: the side of a chunk facing the pool glows white-hot (heat_reach), and its
# edge crumbles. The furnace picks the cells it melts at random along that edge (sometimes one
# row deeper), so the chunk erodes unevenly instead of being eaten cell by cell. A melted cell
# isn't just removed: it slumps into a droplet that runs into the pool and makes a ripple.
# Droplets and ripples are visual only: the cell's ore is already in the pool.
#
# The chamber has its own physics world: a SubViewport, which owns a separate physics space.
# Its coordinates are this room's coordinates, and its walls are static, so nothing lags behind
# the ship and nothing outside (hull, asteroids, lasers) can touch what's inside. The SubViewport
# is never rendered: this room draws the chunks itself (_draw).
# What you'd feel inside the moving ship is added as forces: the ship accelerates, the pile slides
# the other way; the ship spins, chunks are flung outward. (The smaller rotation effects are left out.)
#
# How a chunk gets in: the hangar asks can_accept_chunk() (see Room). True when the chunk would
# fit in an empty chamber and the pool has room for it once melted, counting everything already
# inside and on the conveyor. It doesn't need free space in the chamber right now: melting is fast.
# The chunk rides the conveyor (CarriedChunk, no physics) to an entry spot just inside the front
# wall and becomes a SmelterChunk there. Entry spots are tried across the chamber's width (centre
# first), so chunks pile up side by side instead of in a single file.
# A chunk too long for the space left in front of the pool doesn't wait for the pool to go down:
# the conveyor feeds it straight into the pool through a free lane, and it melts as it goes in.
# Once what's left of it fits, it drops into the chamber like any other. Only when every lane is
# blocked by other chunks does it wait on the conveyor, just outside the front wall.
# One chunk on the conveyor at a time, so two can't land on the same spot.
# Refining stalls when the ingot holds are full.
#
# Variants share this script and only change its numbers (one scene each, see ShipRooms):
# - Smelter: the basic one.
# - Flash smelter: melts and refines twice as fast, but rock gives half the traces. Fixed on the
#   Meridian Harvester.
# - Reclaim smelter: same speed as the basic one, rock gives three times the traces.
#
# The chamber fills the room, inside its walls, minus one texel at the back for the furnace grate.
# So a bigger slot gives a bigger chamber: more chunks fit, and bigger ones, and a bigger pool.

const WALL_LAYER: int = 1
const CHUNK_LAYER: int = 2

@export_range(0.01, 200.0) var melt_rate: float = 37.5 # Cells per second, solid to molten
@export_range(0.01, 100.0) var refine_rate: float = 2.6 # Cells of melt per second, molten to ingots
@export var conveyor_speed: float = 40.0 # px/s, from the hangar doors to the chamber's entry
@export var heat_up_time: float = 1.0
@export_range(0.0, 1.0) var rock_trace_yield: float = 0.1 # Ore units from a rock cell. An ore cell gives 1
@export_range(0.05, 1.0) var liquid_volume: float = 0.5 # Room a melted cell takes, as a share of a solid one
@export_range(0.1, 0.95) var max_pool_share: float = 0.9 # Deepest the pool gets, as a share of the chamber's length

@export_group("Chamber")
@export var wall_thickness: float = 8.0
@export var entry_margin: float = 2.0 # Gap between a new chunk and the front wall
@export var entry_step: float = 4.0 # Spacing of the entry spots tried across the chamber
@export var push_acceleration: float = 60.0 # px/s² toward the furnace
@export var damping: float = 3.0 # Calms chunks down (relative to the ship: the chamber moves with it)
@export var melt_reach: float = 3.0 # px. Cells whose back edge is this close to the pool's surface can melt
@export var mass_per_cell: float = 0.1 # Keep equal to Asteroid.mass_per_cell
@export var max_inertial_acceleration: float = 1500.0 # px/s². Ignores spikes (collisions jolt the ship)

@export_group("Visuals")
@export var cold_color: Color = Color(0.16, 0.08, 0.07)
@export var hot_color: Color = Color(1.0, 0.45, 0.1)
@export var core_color: Color = Color(1.0, 0.9, 0.6)
@export var chunk_hot_color: Color = Color(1.0, 0.5, 0.15)
@export var roller_color: Color = Color(0.67, 0.36, 0.18)
@export var melt_cold_color: Color = Color(0.3, 0.12, 0.08) # The pool while the furnace is off
@export var melt_hot_color: Color = Color(1.0, 0.55, 0.15)
@export var melt_surface_color: Color = Color(1.0, 0.85, 0.5)

@export_group("Melting look")
@export var heat_reach: float = 12.0 # px. Cells closer than this to the pool heat up toward white
@export var drip_time: float = 0.35 # s. A melted cell shrinks into a droplet over this time
@export var drip_speed: float = 40.0 # px/s. How fast droplets run toward the pool
@export var splash_time: float = 0.4 # s. A ripple on the pool's surface where a droplet lands
@export var wave_speed: float = 3.0 # The pool's surface sways at this speed

var chamber: Rect2 # Inside the walls, in this room's space. Back = -x. Set from the size in _ready
var chunks: Array[SmelterChunk] = []
var incoming: CarriedChunk # On the conveyor, heading for the entry spot
var heat: float = 0.0 # 0..1
var is_working: bool = false

var _melt_progress: float = 0.0 # 0..1 toward the next cell
var _pool_volume: float = 0.0 # Molten cells waiting to be refined
var _pool_ore: Dictionary[int, float] = {} # CellMaterials.Id -> ore units in the pool
var _cell_area: float = 16.0 # px², of one cell. Taken from the chunks that come in
var _last_cell_count: int = 0 # contents_changed fires when get_cells() changes, not every frame
var _interior: SubViewport
var _furnace_wall: CollisionShape2D # The back wall. It sits on the pool's surface
var _drips: Array[Dictionary] = [] # { position, velocity, size, color, age, life }. Room space
var _splashes: Array[Dictionary] = [] # { y, age }
var _time: float = 0.0 # For the pool's waves and the crumbling edge
var _rng := RandomNumberGenerator.new()
var _is_feeding: bool = false # The incoming chunk is being fed into the pool from the conveyor
var _feed_progress: float = 0.0 # 0..1 toward the next cell of the incoming chunk
var _last_ship_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	var inner := get_inner_rect()
	chamber = Rect2(inner.position.x + TEXEL, inner.position.y, inner.size.x - TEXEL, inner.size.y)
	_build_interior()


func _physics_process(delta: float) -> void:
	var is_feeding := _update_incoming(delta)
	_apply_forces(delta)
	var is_melting := _melt_chunks(delta)
	var is_refining := _refine(delta)
	is_working = is_feeding or is_melting or is_refining
	_update_furnace_wall()
	_update_heat(delta)
	_update_drips(delta)
	_notify_if_count_changed()
	_time += delta

	if not chunks.is_empty() or _pool_volume > 0.0 or not _drips.is_empty() or not _splashes.is_empty():
		queue_redraw()


func _draw_contents() -> void:
	_draw_rollers()
	_draw_furnace()
	_draw_pool()

	var glow := 0.65 + 0.35 * heat
	var surface := _get_pool_surface()

	for chunk in chunks:
		_draw_chunk(chunk, glow, surface)

	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_drips()


func get_cells() -> int:
	var total := 0

	for chunk in chunks:
		total += chunk.get_cell_count()

	if incoming != null:
		total += incoming.get_cell_count()

	return total + roundi(_pool_volume)


# Ore units inside, solid and molten, as they'd come out once refined. CellMaterials.Id -> units.
func get_ore_inside() -> Dictionary[int, float]:
	var ore: Dictionary[int, float] = {}

	for chunk in chunks:
		for cell in chunk.cells:
			var material_id: int = chunk.cells[cell]

			if CellMaterials.is_ore(material_id):
				ore[material_id] = ore.get(material_id, 0.0) + 1.0
			else:
				ore[chunk.ore_type] = ore.get(chunk.ore_type, 0.0) + rock_trace_yield

	if incoming != null:
		for cell in incoming.cells:
			var material_id: int = incoming.cells[cell]

			if CellMaterials.is_ore(material_id):
				ore[material_id] = ore.get(material_id, 0.0) + 1.0
			else:
				ore[incoming.ore_type] = ore.get(incoming.ore_type, 0.0) + rock_trace_yield

	for ore_id in _pool_ore:
		ore[ore_id] = ore.get(ore_id, 0.0) + _pool_ore[ore_id]

	return ore


# 0..1. How full the molten pool is.
func get_pool_ratio() -> float:
	var capacity := _get_pool_capacity()

	if capacity <= 0.0:
		return 0.0

	return _pool_volume / capacity


# How many cells the smelter holds, once molten. The same limit can_accept_chunk() uses.
func get_capacity_cells() -> int:
	return floori(_get_pool_capacity())


func takes_chunks() -> bool:
	return true


# True if the chunk could go in an empty chamber, at its current angle. Ignores what's inside.
func fits_chunk(asteroid: Asteroid) -> bool:
	return _fits(_get_footprint(asteroid))


# Room is counted in liquid form: what's in the pool, plus everything solid inside and on the
# conveyor as if it were already melted.
func can_accept_chunk(asteroid: Asteroid) -> bool:
	if incoming != null or not fits_chunk(asteroid):
		return false

	var committed := _pool_volume + get_cells() - roundi(_pool_volume)
	return committed + asteroid.cells.size() <= _get_pool_capacity()


# Swaps the asteroid chunk for a CarriedChunk at the same place, then sends it down the conveyor
# to a free entry spot, or to the waiting spot if none is free. It keeps its orientation relative
# to the ship.
func receive_chunk(asteroid: Asteroid) -> bool:
	if not can_accept_chunk(asteroid):
		return false

	var footprint := _get_footprint(asteroid)
	var entry := _find_entry(footprint)

	if entry == Vector2.INF:
		entry = _get_waiting_spot(footprint)

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
	return "%d cells, melt %d%%, %s" % [get_cells(), roundi(get_pool_ratio() * 100.0), state]


func clear_contents() -> void:
	for chunk in chunks:
		chunk.queue_free()

	chunks.clear()

	if incoming != null:
		incoming.queue_free()
		incoming = null

	_is_feeding = false
	_feed_progress = 0.0
	_melt_progress = 0.0
	_pool_volume = 0.0
	_pool_ore.clear()
	_drips.clear()
	_splashes.clear()
	_update_furnace_wall()
	_notify_if_count_changed()


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

	_furnace_wall = walls.get_child(2)


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
# chunk doesn't fit between the pool's surface and the front wall right now.
func _find_entry(footprint: Rect2) -> Vector2:
	if not _fits(footprint):
		return Vector2.INF

	if footprint.size.x > chamber.end.x - _get_pool_surface() - entry_margin:
		return Vector2.INF # Wait for the pool to go down

	var x := chamber.end.x - entry_margin - footprint.end.x

	for y in _get_spot_ys(footprint):
		var center := Vector2(x, y)

		if _is_space_free(Rect2(footprint.position + center, footprint.size)):
			return center

	return Vector2.INF


# Where a chunk too long for the space in front of the pool can be fed in: a lane across the
# chamber, from the pool's surface to the front wall, with no chunk in it. Returns the chunk's
# centre with its back edge on the pool's surface, or Vector2.INF if every lane is blocked.
# Tries preferred_y first, so a chunk being fed stays in its lane.
func _find_feed_lane(footprint: Rect2, preferred_y: float) -> Vector2:
	var surface := _get_pool_surface()
	var x := surface - footprint.position.x
	var ys := _get_spot_ys(footprint)
	ys.push_front(preferred_y)

	for y in ys:
		var lane := Rect2(surface, footprint.position.y + y, chamber.end.x - surface, footprint.size.y)

		if lane.position.y >= chamber.position.y - 0.01 and lane.end.y <= chamber.end.y + 0.01 and _is_space_free(lane):
			return Vector2(x, y)

	return Vector2.INF


# Centre heights to try for a chunk, across the chamber's width: the middle first, then
# entry_step further out on each side in turn, up to the walls.
func _get_spot_ys(footprint: Rect2) -> Array[float]:
	var center_y := chamber.get_center().y - footprint.get_center().y
	var max_offset := (chamber.size.y - footprint.size.y) * 0.5
	var ys: Array[float] = [center_y]
	var offset := entry_step

	while offset < max_offset:
		ys.append(center_y + offset)
		ys.append(center_y - offset)
		offset += entry_step

	if max_offset > 0.01:
		ys.append(center_y + max_offset)
		ys.append(center_y - max_offset)

	return ys


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


# Where a chunk waits for an entry spot: on the conveyor, its back edge just outside the front wall.
func _get_waiting_spot(footprint: Rect2) -> Vector2:
	var x := chamber.end.x + TEXEL - footprint.position.x
	var y := chamber.get_center().y - footprint.get_center().y
	return Vector2(x, y)


# Same as _get_footprint, for a chunk already on the conveyor. Relative to the node's origin,
# which sits on the chunk's centre (pivot).
func _get_carried_footprint(chunk: CarriedChunk) -> Rect2:
	var footprint := Rect2()
	var is_first := true

	for cell in chunk.cells:
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var point := ((Vector2(cell) + corner) * chunk.cell_size - chunk.pivot).rotated(chunk.rotation)

			if is_first:
				footprint = Rect2(point, Vector2.ZERO)
				is_first = false
			else:
				footprint = footprint.expand(point)

	return footprint


# Steers the chunk on the conveyor once it gets where it was sent (the pile moves meanwhile):
# - a free entry spot: it goes there and drops into the chamber;
# - too long for the space in front of the pool: it's fed into the pool through a free lane;
# - everything blocked: it waits just outside the front wall.
# Returns true while feeding the pool.
func _update_incoming(delta: float) -> bool:
	if incoming == null:
		_is_feeding = false
		return false

	if not _is_feeding and not incoming.has_arrived():
		return false

	var footprint := _get_carried_footprint(incoming)
	var entry := _find_entry(footprint)

	if entry != Vector2.INF:
		_stop_feeding()

		if incoming.position.distance_to(entry) > 0.5:
			incoming.target = entry
		else:
			_drop_in_chamber()

		return false

	var lane := _find_feed_lane(footprint, incoming.position.y)

	if lane == Vector2.INF:
		_stop_feeding()
		incoming.target = _get_waiting_spot(footprint)
		return false

	_is_feeding = true
	incoming.target = lane
	incoming.set_heat(1.0)
	return _feed(delta)


func _stop_feeding() -> void:
	_is_feeding = false
	_feed_progress = 0.0

	if incoming != null:
		incoming.set_heat(0.0)


# Melts the cells of the chunk on the conveyor that reach the pool, at melt_rate. Same choice of
# cells as for the chunks in the chamber (see _find_cell_at_surface).
func _feed(delta: float) -> bool:
	if _is_pool_full() or _find_carried_cell_at_surface() == Vector2i.MAX:
		return false

	_feed_progress += melt_rate * delta

	while _feed_progress >= 1.0:
		_feed_progress -= 1.0
		var cell := _find_carried_cell_at_surface()

		if cell == Vector2i.MAX or _is_pool_full():
			_feed_progress = 0.0
			break

		_melt_carried(cell)

		if incoming == null:
			break

	return true


# Vector2i.MAX if no cell of the incoming chunk reaches the pool.
func _find_carried_cell_at_surface() -> Vector2i:
	var surface := _get_pool_surface()
	var candidates: Array[Vector2i] = []
	var is_touching := false

	for cell in incoming.cells:
		var back_edge := _get_carried_cell_center(cell).x - incoming.cell_size * 0.5

		if back_edge <= surface + melt_reach:
			is_touching = true

		if back_edge <= surface + melt_reach + incoming.cell_size:
			candidates.append(cell)

	if not is_touching:
		return Vector2i.MAX

	var first := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var second := candidates[_rng.randi_range(0, candidates.size() - 1)]
	return first if _get_carried_cell_center(first).x <= _get_carried_cell_center(second).x else second


# In this room's space.
func _get_carried_cell_center(cell: Vector2i) -> Vector2:
	return incoming.transform * ((Vector2(cell) + Vector2(0.5, 0.5)) * incoming.cell_size - incoming.pivot)


# Same as _melt, for a cell of the chunk on the conveyor. Frees the chunk once it's all melted.
func _melt_carried(cell: Vector2i) -> void:
	var material_id: int = incoming.cells[cell]
	var ore_id := material_id if CellMaterials.is_ore(material_id) else incoming.ore_type
	_pool_ore[ore_id] = _pool_ore.get(ore_id, 0.0) + _get_yield(material_id)
	_pool_volume += 1.0

	var look := CellMaterials.get_display_id(material_id, incoming.revealed_ore.has(cell))
	var color := CellMaterials.get_material(look).color.lerp(core_color, 0.7)
	_spawn_drip(_get_carried_cell_center(cell), incoming.cell_size, color)

	incoming.cells.erase(cell)
	incoming.revealed_ore.erase(cell)
	incoming.queue_redraw()

	if incoming.cells.is_empty():
		incoming.queue_free()
		incoming = null
		_stop_feeding()


# The carried chunk becomes a body in the chamber, at the same place.
# The carried chunk is drawn around its centre (pivot); the body's origin is the cell grid's origin.
func _drop_in_chamber() -> void:
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
	_cell_area = incoming.cell_size * incoming.cell_size
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


# --- Melting


# Melts the cells touching the pool's surface, rearmost first. Returns true while melting.
func _melt_chunks(delta: float) -> bool:
	if chunks.is_empty() or ship_rooms == null:
		_melt_progress = 0.0
		return false

	var target := _find_cell_at_surface()

	if target.is_empty() or _is_pool_full():
		return false

	_melt_progress += melt_rate * delta

	while _melt_progress >= 1.0:
		_melt_progress -= 1.0
		_melt(target["chunk"], target["cell"])
		target = _find_cell_at_surface()

		if target.is_empty() or _is_pool_full():
			_melt_progress = 0.0
			break

	return true


# A cell to melt, among those touching the pool's surface or one row behind them. Picks two at
# random and keeps the one closer to the pool: mostly the edge, sometimes a bit deeper, so the
# chunk erodes unevenly. Empty dictionary if nothing touches the pool.
func _find_cell_at_surface() -> Dictionary:
	var surface := _get_pool_surface()
	var candidates: Array[Dictionary] = []
	var is_touching := false

	for chunk in chunks:
		for cell in chunk.cells:
			var back_edge := (chunk.transform * chunk.get_cell_center(cell)).x - chunk.cell_size * 0.5

			if back_edge <= surface + melt_reach:
				is_touching = true

			if back_edge <= surface + melt_reach + chunk.cell_size:
				candidates.append({ "chunk": chunk, "cell": cell, "x": back_edge })

	if not is_touching:
		return {}

	var first: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var second: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
	return first if first["x"] <= second["x"] else second


# The cell joins the pool, with the ore it will give once refined.
func _melt(chunk: SmelterChunk, cell: Vector2i) -> void:
	var material_id: int = chunk.cells[cell]
	var ore_id := material_id if CellMaterials.is_ore(material_id) else chunk.ore_type
	_pool_ore[ore_id] = _pool_ore.get(ore_id, 0.0) + _get_yield(material_id)
	_pool_volume += 1.0

	var look := CellMaterials.get_display_id(material_id, chunk.revealed_ore.has(cell))
	var color := CellMaterials.get_material(look).color.lerp(core_color, 0.7)
	_spawn_drip(chunk.transform * chunk.get_cell_center(cell), chunk.cell_size, color)

	chunk.remove_cell(cell)

	if chunk.get_cell_count() == 0:
		chunks.erase(chunk)
		chunk.queue_free()


# Ore units a cell of this material gives once refined.
func _get_yield(material_id: int) -> float:
	if CellMaterials.is_ore(material_id):
		return 1.0

	return rock_trace_yield


# --- Refining


# Turns some of the pool into ingots, every ore in proportion. Returns true while refining.
# Stalls when the ingot holds can't take what would come out.
func _refine(delta: float) -> bool:
	if _pool_volume <= 0.0 or ship_rooms == null:
		return false

	var volume := minf(refine_rate * delta, _pool_volume)
	var ore_total := 0.0

	for ore_id in _pool_ore:
		ore_total += _pool_ore[ore_id]

	var ore_out := ore_total * volume / _pool_volume
	var free := ship_rooms.get_free_ingot_units()

	if ore_out > free:
		if free <= 0.0001:
			return false # Ingot holds full

		volume *= free / ore_out

	var share := volume / _pool_volume

	for ore_id in _pool_ore.keys():
		var units: float = _pool_ore[ore_id] * share
		ship_rooms.store_ingots(ore_id, units)
		_pool_ore[ore_id] -= units

	_pool_volume -= volume

	if _pool_volume < 0.0001:
		_pool_volume = 0.0
		_pool_ore.clear()

	return true


# --- Pool


func _get_pool_capacity() -> float:
	return chamber.size.x * max_pool_share * chamber.size.y / (_cell_area * liquid_volume)


func _is_pool_full() -> bool:
	return _pool_volume + 1.0 > _get_pool_capacity()


# px from the back of the chamber to the pool's surface.
func _get_pool_depth() -> float:
	return _pool_volume * _cell_area * liquid_volume / chamber.size.y


# x of the pool's surface, in this room's space.
func _get_pool_surface() -> float:
	return chamber.position.x + _get_pool_depth()


# The back wall rides on the pool's surface, so chunks rest on the melt, not under it.
# Chunks are pushed out of the way if it moves into them (it moves a fraction of a px per cell).
func _update_furnace_wall() -> void:
	if _furnace_wall == null:
		return

	var x := _get_pool_surface() - wall_thickness * 0.5

	if absf(_furnace_wall.position.x - x) > 0.01:
		_furnace_wall.position.x = x


func _notify_if_count_changed() -> void:
	var count := get_cells()

	if count != _last_cell_count:
		_last_cell_count = count
		contents_changed.emit()


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


# --- Melting look


# The chunk cell by cell, so each cell can glow according to how close it is to the pool.
# Cells right at the pool's edge flicker between whole and half-gone: the edge crumbles.
func _draw_chunk(chunk: SmelterChunk, glow: float, surface: float) -> void:
	draw_set_transform_matrix(chunk.transform)
	var cell_size := chunk.cell_size
	var crumble_step := int(_time * 10.0) # The crumbling pattern changes 10 times a second
	var half := Vector2.ONE * snap_texel(cell_size * 0.5)

	for cell in chunk.cells:
		var look := CellMaterials.get_display_id(chunk.cells[cell], chunk.revealed_ore.has(cell))
		var color := CellMaterials.get_material(look).color.lerp(chunk_hot_color, glow)
		var distance := (chunk.transform * chunk.get_cell_center(cell)).x - cell_size * 0.5 - surface
		var hot := clampf(1.0 - distance / heat_reach, 0.0, 1.0)
		color = color.lerp(core_color, hot * hot * (0.5 + 0.5 * heat))
		var rect := Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size)

		if hot > 0.75:
			var noise := float(hash([cell, chunk.get_instance_id(), crumble_step]) % 100) / 100.0

			if noise < (hot - 0.75) * 2.0:
				var corner_id := hash([cell, crumble_step]) % 4 # Which quarter of the cell is left
				var corner := Vector2(corner_id % 2, 1 if corner_id >= 2 else 0)
				rect = Rect2(rect.position + corner * half, half)

		draw_rect(rect, color)


# A melted cell becomes a droplet: it starts as the cell, shrinks and brightens, and runs toward
# the pool (-x). Sometimes a smaller spatter drop comes off it.
func _spawn_drip(at: Vector2, size: float, color: Color) -> void:
	var drift := _rng.randf_range(-1.0, 1.0) * drip_speed * 0.2
	var life := drip_time * _rng.randf_range(0.7, 1.3)
	_drips.append({ "position": at, "velocity": Vector2(-drip_speed, drift), "size": size, "color": color, "age": 0.0, "life": life })

	if _rng.randf() < 0.4:
		var spatter := Vector2(-drip_speed * 1.5, _rng.randf_range(-1.0, 1.0) * drip_speed)
		_drips.append({ "position": at, "velocity": spatter, "size": TEXEL, "color": melt_surface_color, "age": 0.0, "life": life * 0.6 })


# Droplets run into the pool. Each one that lands makes a ripple; old ripples fade.
func _update_drips(delta: float) -> void:
	var surface := _get_pool_surface()

	for i in range(_drips.size() - 1, -1, -1):
		var drip := _drips[i]
		var velocity: Vector2 = drip["velocity"]
		velocity.y *= 1.0 - minf(6.0 * delta, 1.0) # Sideways drift dies out
		var drip_position: Vector2 = drip["position"] + velocity * delta
		drip_position.y = clampf(drip_position.y, chamber.position.y + TEXEL, chamber.end.y - TEXEL)
		drip["velocity"] = velocity
		drip["position"] = drip_position
		drip["age"] += delta

		if drip_position.x <= surface or drip["age"] >= drip["life"]:
			_splashes.append({ "y": drip_position.y, "age": 0.0 })
			_drips.remove_at(i)

	for i in range(_splashes.size() - 1, -1, -1):
		_splashes[i]["age"] += delta

		if _splashes[i]["age"] >= splash_time:
			_splashes.remove_at(i)


# Drawn on the texel grid. Each droplet goes from its cell's colour to molten as it shrinks.
func _draw_drips() -> void:
	for drip in _drips:
		var t: float = drip["age"] / drip["life"]
		var size := maxf(snap_texel(lerpf(drip["size"], TEXEL, t)), TEXEL)
		var center: Vector2 = drip["position"]
		var top_left := Vector2(snap_texel(center.x - size * 0.5), snap_texel(center.y - size * 0.5))
		var color: Color = drip["color"].lerp(melt_surface_color, t)
		draw_rect(Rect2(top_left, Vector2.ONE * size), color)

		if t > 0.3:
			var trail := Color(melt_hot_color, 0.6)
			draw_rect(Rect2(top_left + Vector2(size, snap_texel(size * 0.5 - TEXEL * 0.5)), Vector2(TEXEL, TEXEL)), trail)


# The molten pool at the back of the chamber, one texel row at a time: its surface sways, bulges
# where droplets land, and bubbles show up in it while the furnace runs.
func _draw_pool() -> void:
	var depth := _get_pool_depth()

	if depth < TEXEL * 0.5 and _splashes.is_empty():
		return

	var body_color := melt_cold_color.lerp(melt_hot_color, heat)
	var surface_color := melt_cold_color.lerp(melt_surface_color, heat)
	var bubble_step := int(_time * 6.0)
	var y := chamber.position.y

	while y < chamber.end.y:
		var bulge := 0.0

		for splash in _splashes:
			var distance := absf(splash["y"] - y)

			if distance < TEXEL * 3.0:
				bulge += (1.0 - splash["age"] / splash_time) * (1.0 - distance / (TEXEL * 3.0)) * 2.0

		var wave := sin(_time * wave_speed + y * 0.35) * 0.6 * minf(depth / TEXEL, 1.0)
		var width := snap_texel(depth + (wave + bulge) * TEXEL)

		if width >= TEXEL:
			var row_height := minf(TEXEL, chamber.end.y - y)
			draw_rect(Rect2(chamber.position.x, y, width - TEXEL, row_height), body_color)
			draw_rect(Rect2(chamber.position.x + width - TEXEL, y, TEXEL, row_height), surface_color)

			if heat > 0.3 and width >= TEXEL * 3.0 and hash([y, bubble_step]) % 9 == 0:
				var bubble_x := chamber.position.x + snap_texel(float(hash([bubble_step, y]) % 1000) / 1000.0 * (width - TEXEL * 2.0))
				draw_rect(Rect2(bubble_x, y, TEXEL, row_height), core_color)

		y += TEXEL


# The furnace grate along the back wall: dark when cold, glowing when hot.
func _draw_furnace() -> void:
	var grate := Rect2(chamber.position.x - 2.0, chamber.position.y, 2.0, chamber.size.y)
	draw_rect(grate, cold_color.lerp(hot_color, heat))

	if heat > 0.5:
		var core := Rect2(grate.position.x + 1.0, grate.position.y + 2.0, 1.0, grate.size.y - 4.0)
		draw_rect(core, hot_color.lerp(core_color, heat * 2.0 - 1.0))
