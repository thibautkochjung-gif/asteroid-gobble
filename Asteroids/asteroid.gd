class_name Asteroid
extends RigidBody2D

# Cells are plain data: a dictionary from cell coordinates to a material id (CellMaterials.Id).
# Collision uses a few dozen merged rectangles, registered on the body through a shape owner:
# no child nodes. One node or one shape per cell made every moving asteroid update thousands of
# transforms and broadphase entries each frame.
#
# Composition: about half the cells are tough rock, the rest soft rock, in patches and seams.
# Some asteroids (valuable_chance) also hold clusters of one ore. Every asteroid has an ore_type,
# even without ore cells: its rock carries traces of that ore, which the smelter recovers.
# Ore can only be seen within visible_depth layers of open space (the "band"). Deeper ore is drawn
# as tough rock until cuts bring open space close enough. Once seen, it stays seen, in chunks too.
# The cells deeper than the band are the core: drawn darker, as a fog of war.
#
# Damage: the drill and the plasma gun wear cells down over time (add_damage). A cell keeps its
# damage for damage_memory_time after its last hit, so a tool that slips off and comes back
# picks up where it left off. Chunks keep the damage of the cells they take.
#
# Drawing lives in AsteroidLook and asteroid.gdshader. This script only tells them what changed.

signal shapes_rebuilt # After every rebuild of the collision rectangles (a cut, a split). The tether copies them

const GROUP: StringName = &"asteroids"
const NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

@export var cell_size: float = 4.0
@export var radius_in_cells: int = 24
@export_range(0.0, 1.0) var shape_roughness: float = 0.35
@export var mass_per_cell: float = 0.1
@export var split_kick: float = 20.0 # px/s, pushes new chunks away from the parent
@export var min_chunk_cells: int = 1 # Smaller parts vanish instead of becoming chunks
@export var detach_spin: float = 2.0 # rad/s, random extra spin given to detached debris
@export var damage_memory_time: float = 30.0 # s. A damaged cell forgets its damage this long after its last hit

@export_group("Composition")
@export_range(0.0, 1.0) var valuable_chance: float = 0.3 # Share of asteroids that hold ore clusters
@export var force_valuable: bool = false # For testing: this asteroid always holds ore
@export_range(0.0, 1.0) var tough_ratio: float = 0.5
@export var rock_noise_frequency: float = 0.08 # Lower = bigger patches of tough and soft rock
@export_range(0.0, 1.0) var min_ore_ratio: float = 0.04 # Share of the cells that are ore, when there is ore
@export_range(0.0, 1.0) var max_ore_ratio: float = 0.08
@export var min_ore_clusters: int = 2
@export var max_ore_clusters: int = 4
@export var visible_depth: int = 5 # Layers of cells, counted from open space, in which ore can be seen

@export_group("Look")
@export var min_elongation: float = 1.0 # Length / width of the generated shape
@export var max_elongation: float = 1.35
@export var craters_per_100_cells: float = 0.0 # 0 = no craters. Craters only show in the core
@export var min_crater_radius: float = 2.5 # In texels (2 px)
@export var max_crater_radius: float = 6.0
@export_range(0.0, 1.0) var crater_floor_shade: float = 0.86
@export_range(0.0, 1.0) var crater_rim_shade: float = 0.62
@export_range(0.0, 1.0) var core_shade: float = 0.6 # Brightness of the core, the cells deeper than the band
@export_range(0.0, 1.0) var edge_shade: float = 0.72 # Brightness of the texels along open space
@export var outline_color: Color = Color(0.06, 0.055, 0.07) # Same as the ship's

var cells: Dictionary[Vector2i, int] = {} # Cell -> CellMaterials.Id. Filled by the parent before add_child() when this is a chunk
var revealed_ore: Dictionary[Vector2i, bool] = {} # Ore cells the player has seen
var ore_type: int = CellMaterials.Id.NICKEL_IRON # Rolled at generation, inherited by chunks
var look_seed: int = 0 # Flecks, facets and cracks. Inherited by chunks
var inherited_look: AsteroidLook # Set by the parent before add_child() when this is a chunk
var damage: Dictionary[Vector2i, float] = {} # Cell -> share of the work needed to destroy it, 0..1
var space_parent: Node # Where cut-off chunks go. Null = this body's parent. Set while the body rides on something (welded to a ship by a Tether, held by a CacheBuoy): chunks go to space, not into the ship

var _rects: Array[Rect2i] = [] # All cells merged into rectangles, in cell units. Used for collision
var _band: Dictionary[Vector2i, bool] = {} # Cells within visible_depth layers of open space. The others are the core
var _look: AsteroidLook
var _rect_shapes: Dictionary[Vector2i, RectangleShape2D] = {} # One resource per rectangle size, reused
var _changes_pending: bool = false
var _damage_memory_left: Dictionary[Vector2i, float] = {} # Cell -> seconds before it forgets its damage
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)

	if cells.is_empty():
		_generate()

	var newly_revealed := _update_band()
	_look = AsteroidLook.new(cells.keys(), look_seed)

	if inherited_look == null:
		_look.paint_all(cells, revealed_ore, _make_craters(), crater_floor_shade, crater_rim_shade)
	else:
		_look.copy_from(inherited_look)
		_look.repaint(newly_revealed, cells, revealed_ore)
		inherited_look = null # Done with it: don't keep the parent's image alive

	_look.update_cells(cells, _band)
	_look.set_shades(outline_color, core_shade, edge_shade)
	material = _look.material

	_rebuild_shapes()
	_update_mass()
	queue_redraw()
	set_process(not damage.is_empty()) # Only runs while some cell remembers damage


# Counts down the damage memory. Runs only while some cell is damaged.
func _process(delta: float) -> void:
	for cell in _damage_memory_left.keys():
		_damage_memory_left[cell] -= delta

		if _damage_memory_left[cell] <= 0.0:
			_forget_damage(cell)

	if damage.is_empty():
		set_process(false)


# One rectangle over the whole grid. The shader decides what each texel shows.
# The textures change, not the drawing: no queue_redraw() needed after a cut.
func _draw() -> void:
	draw_texture_rect(_look.get_texture(), _look.get_draw_rect(cell_size), false)


func remove_cell(cell: Vector2i) -> void:
	if not cells.has(cell):
		return

	cells.erase(cell)
	revealed_ore.erase(cell)
	_forget_damage(cell)

	if cells.is_empty():
		queue_free()
		return

	_request_changes()


# Adds to a cell's damage (1 = destroyed) and restarts its memory.
# Returns true once the cell is destroyed. The caller decides what that means: the plasma gun
# vaporizes it, the drill breaks it off.
func add_damage(cell: Vector2i, amount: float) -> bool:
	if not cells.has(cell):
		return false

	damage[cell] = get_damage(cell) + amount
	_damage_memory_left[cell] = damage_memory_time
	set_process(true)
	return damage[cell] >= 1.0


func get_damage(cell: Vector2i) -> float:
	return damage.get(cell, 0.0)


func get_cell_global_position(cell: Vector2i) -> Vector2:
	return to_global((Vector2(cell) + Vector2(0.5, 0.5)) * cell_size)


func get_cell_material(cell: Vector2i) -> CellMaterial:
	return CellMaterials.get_material(cells[cell])


func get_hardness(cell: Vector2i) -> float:
	return get_cell_material(cell).hardness


# What the player sees at this cell: buried ore looks like tough rock.
func get_display_id(cell: Vector2i) -> int:
	return CellMaterials.get_display_id(cells[cell], revealed_ore.has(cell))


func get_cell_color(cell: Vector2i) -> Color:
	return CellMaterials.get_material(get_display_id(cell)).color


# True if this body still holds ore cells, seen or not. For the scanner and the radar, later,
# and the magnetic clamp (it only grips rocks with ore inside).
func has_ore_cells() -> bool:
	for cell in cells:
		if cells[cell] == ore_type:
			return true

	return false


# A random cell among the candidates, soft ones much more likely (weight 1 / hardness²).
func pick_soft_cell(candidates: Array[Vector2i]) -> Vector2i:
	return candidates[_pick_soft_index(candidates)]


# Reveals every ore cell within radius (px) of a global point, however deep. For the survey probe.
# Returns how many cells were revealed just now.
func reveal_ore_near(global_point: Vector2, radius: float) -> int:
	var center := to_local(global_point) / cell_size
	var radius_cells := radius / cell_size
	var newly_revealed: Array[Vector2i] = []

	for cell in cells:
		if cells[cell] != ore_type or revealed_ore.has(cell):
			continue

		if (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(center) <= radius_cells * radius_cells:
			revealed_ore[cell] = true
			newly_revealed.append(cell)

	if not newly_revealed.is_empty():
		_look.repaint(newly_revealed, cells, revealed_ore)

	return newly_revealed.size()


# The cell at a global point, or the nearest one around it (within 2 cells). For anchors: a point
# on the surface (get_closest_point) sits on a cell's edge, and rounding can land just outside.
# May return a cell that isn't in `cells` if there's none around: check with cells.has().
func get_cell_near(global_point: Vector2) -> Vector2i:
	var local := to_local(global_point) / cell_size
	var guess := Vector2i(floori(local.x), floori(local.y))

	if cells.has(guess):
		return guess

	var best := guess
	var best_distance := INF

	for x in range(-2, 3):
		for y in range(-2, 3):
			var cell := guess + Vector2i(x, y)

			if not cells.has(cell):
				continue

			var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(local)

			if distance < best_distance:
				best_distance = distance
				best = cell

	return best


# The merged rectangles the collision is made of, in cell units.
func get_collision_rects() -> Array[Rect2i]:
	return _rects


# The shape used for a rectangle of this size (shared between rectangles of the same size).
func get_rect_shape(size_in_cells: Vector2i) -> RectangleShape2D:
	return _get_rect_shape(size_in_cells)


# Centre of all current cells. A chunk's origin is its parent's old origin, not its centre.
func get_global_center() -> Vector2:
	return _get_global_center(cells.keys())


func get_local_center() -> Vector2:
	return to_local(get_global_center())


# Returns every filled cell crossed by the segment, nearest first.
# Each hit: { "asteroid", "cell", "distance" (entry, px), "exit" (px) }
func get_cells_on_ray(ray_start: Vector2, ray_end: Vector2) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var to_local_space := global_transform.affine_inverse()
	var start := to_local_space * ray_start / cell_size # In "cell units"
	var end := to_local_space * ray_end / cell_size
	var length := start.distance_to(end)

	if length == 0.0:
		return hits

	var direction := (end - start) / length
	var cell := Vector2i(floori(start.x), floori(start.y))

	var step_x := 1 if direction.x > 0.0 else -1
	var step_y := 1 if direction.y > 0.0 else -1
	var next_x := cell.x + 1 if step_x > 0 else cell.x
	var next_y := cell.y + 1 if step_y > 0 else cell.y
	var t_max_x := (next_x - start.x) / direction.x if direction.x != 0.0 else INF
	var t_max_y := (next_y - start.y) / direction.y if direction.y != 0.0 else INF
	var t_delta_x := absf(1.0 / direction.x) if direction.x != 0.0 else INF
	var t_delta_y := absf(1.0 / direction.y) if direction.y != 0.0 else INF

	var t := 0.0
	while t < length:
		var t_next := minf(t_max_x, t_max_y)

		if cells.has(cell):
			hits.append({
				"asteroid": self,
				"cell": cell,
				"distance": t * cell_size,
				"exit": minf(t_next, length) * cell_size,
			})

		if t_max_x < t_max_y:
			cell.x += step_x
			t_max_x += t_delta_x
		else:
			cell.y += step_y
			t_max_y += t_delta_y

		t = t_next

	return hits


# Every filled cell of every asteroid crossed by the segment, nearest first, at most max_count.
static func find_hits_on_ray(tree: SceneTree, ray_start: Vector2, ray_end: Vector2, max_count: int) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []

	for node in tree.get_nodes_in_group(GROUP):
		var asteroid := node as Asteroid

		if asteroid == null:
			continue

		hits.append_array(asteroid.get_cells_on_ray(ray_start, ray_end))

	hits.sort_custom(_is_closer)
	return hits.slice(0, max_count)


# Point of this asteroid nearest to a global point. Uses the merged rectangles, not the cells:
# a few dozen checks instead of thousands.
func get_closest_point(global_point: Vector2) -> Vector2:
	var local_point := to_local(global_point) / cell_size
	var best := local_point
	var best_distance := INF

	for rect in _rects:
		var area := Rect2(rect)
		var candidate := local_point.clamp(area.position, area.end)
		var distance := candidate.distance_squared_to(local_point)

		if distance < best_distance:
			best_distance = distance
			best = candidate

	return to_global(best * cell_size)


# Direction from the rock toward open space at this group of cells (global, normalized).
# The solid cells around the group (the group itself excluded) lie on the rock's side: their
# offsets add up to a vector pointing into the rock, so the opposite way is out. That works on
# the outer surface and inside a crater or a drill hole alike.
# If the neighbourhood is balanced (a lone chunk), falls back to "away from the asteroid's centre".
# Call it before detaching the group: it needs the cells still in place.
func get_outward_direction(part: Array[Vector2i], radius: int = 5) -> Vector2:
	var in_part: Dictionary[Vector2i, bool] = {}
	var center := Vector2.ZERO

	for cell in part:
		in_part[cell] = true
		center += Vector2(cell)

	center /= part.size()

	var origin := Vector2i(roundi(center.x), roundi(center.y))
	var into_rock := Vector2.ZERO

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var cell := origin + Vector2i(x, y)

			if not cells.has(cell) or in_part.has(cell):
				continue

			var offset := Vector2(cell) - center

			if offset.length() <= radius:
				into_rock += offset

	var outward := -into_rock

	if outward.length_squared() < 0.01:
		outward = (center + Vector2(0.5, 0.5)) * cell_size - get_local_center()

	if outward.length_squared() < 0.01:
		outward = Vector2.RIGHT

	return global_transform.basis_xform(outward).normalized()


func get_part_global_center(part: Array[Vector2i]) -> Vector2:
	return _get_global_center(part)


# Velocity of this body's material at a global point: linear + spin.
func get_velocity_at(global_point: Vector2) -> Vector2:
	var offset := global_point - get_global_center()
	return linear_velocity + Vector2(-angular_velocity * offset.y, angular_velocity * offset.x)


func get_cells_near(center: Vector2i, radius: float) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var r := ceili(radius)

	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			var cell := center + Vector2i(x, y)

			if cells.has(cell) and Vector2(x, y).length() <= radius:
				found.append(cell)

	return found


# Up to `count` cells connected to `start` by a side, grown in random directions. Includes start.
# prefer_soft: the growth favours soft cells (weight 1 / hardness²), so breaks follow the soft
# seams and tough patches tend to stay attached.
func grow_part(start: Vector2i, count: int, prefer_soft: bool = false) -> Array[Vector2i]:
	var part: Array[Vector2i] = []

	if not cells.has(start):
		return part

	var taken: Dictionary[Vector2i, bool] = { start: true }
	var frontier: Array[Vector2i] = [start]

	while part.size() < count and not frontier.is_empty():
		var index := _pick_soft_index(frontier) if prefer_soft else randi_range(0, frontier.size() - 1)
		var cell: Vector2i = frontier.pop_at(index)
		part.append(cell)

		for offset in NEIGHBOURS:
			var neighbour := cell + offset

			if cells.has(neighbour) and not taken.has(neighbour):
				taken[neighbour] = true
				frontier.append(neighbour)

	return part


# Cuts `part` out of this asteroid and throws it as a new chunk at `velocity`.
# If `part` is the whole asteroid, the asteroid itself takes the velocity.
# Returns the new chunk, or null if no chunk was made.
func detach_cells(part: Array[Vector2i], velocity: Vector2) -> Asteroid:
	if part.is_empty():
		return null

	if part.size() >= cells.size():
		linear_velocity = velocity
		return null

	var chunk := _cut_out(part)
	chunk.linear_velocity = velocity
	chunk.angular_velocity = angular_velocity + randf_range(-detach_spin, detach_spin)

	# Same deferred pass as remove_cell(): split what the cut disconnected, rebuild shapes and mass.
	_request_changes()
	return chunk


# Cuts this body into two halves with the same number of cells (give or take one), across its
# longest axis, so both halves come out compact. The second half becomes a new chunk.
# The halves get pushed apart at separation_speed, each in its own direction. No cell is lost.
# Returns the new chunk, or null if there's nothing to cut (a single cell).
func split_in_halves(separation_speed: float) -> Asteroid:
	if cells.size() < 2:
		return null

	var axis := _get_long_axis()
	var sorted: Array[Vector2i] = []
	sorted.assign(cells.keys())
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).dot(axis) < Vector2(b).dot(axis))

	var far_half := sorted.slice(floori(sorted.size() * 0.5))
	var push := global_transform.basis_xform(axis).normalized() * separation_speed * 0.5
	var spin := angular_velocity
	var half := detach_cells(far_half, linear_velocity + push)

	if half == null:
		return null

	half.angular_velocity = spin # No random extra spin: the halves sit in the hold
	linear_velocity -= push

	# Across the long axis, an odd shape can leave a half in pieces. Its deferred pass splits it.
	half._request_changes()
	return half


# Several cells can change in the same frame (laser penetration, a chunk breaking off):
# split, rebuild the shapes and update the mass once, after all of them.
# Deferred calls run before the next physics step, so the collision is never stale in physics.
func _request_changes() -> void:
	if not _changes_pending:
		_changes_pending = true
		_apply_cell_changes.call_deferred()


# Direction (in this body's space, normalized) along which the cells spread the most.
# It's the main axis of their spread: angle = atan2(2 Sxy, Sxx - Syy) / 2, from the covariance.
func _get_long_axis() -> Vector2:
	var center := Vector2.ZERO

	for cell in cells:
		center += Vector2(cell)

	center /= cells.size()

	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0

	for cell in cells:
		var offset := Vector2(cell) - center
		sxx += offset.x * offset.x
		sxy += offset.x * offset.y
		syy += offset.y * offset.y

	return Vector2.from_angle(0.5 * atan2(2.0 * sxy, sxx - syy))


func _generate() -> void:
	look_seed = randi()
	_generate_shape()
	_assign_rock()
	ore_type = CellMaterials.pick_ore_type()

	if force_valuable or randf() < valuable_chance:
		_place_ore_clusters()


# A lumpy disc, stretched along a random axis: small asteroids are rarely round.
# The stretch keeps the area about the same: longer one way, thinner the other.
func _generate_shape() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()

	var stretch := sqrt(randf_range(min_elongation, max_elongation))
	var axis := randf() * TAU
	var reach := ceili(radius_in_cells * stretch * (1.0 + shape_roughness))

	for x in range(-reach, reach):
		for y in range(-reach, reach):
			var center := Vector2(x, y) + Vector2(0.5, 0.5)
			var along_axis := center.rotated(-axis)
			var unstretched := Vector2(along_axis.x / stretch, along_axis.y * stretch)
			var edge_direction := unstretched.normalized()
			var wobble := noise.get_noise_2d(edge_direction.x * 100.0, edge_direction.y * 100.0)
			var limit := radius_in_cells * (1.0 + wobble * shape_roughness)

			if unstretched.length() <= limit:
				cells[Vector2i(x, y)] = CellMaterials.Id.SOFT_ROCK


# Tough or soft, from a noise field: patches and seams rather than salt and pepper.
# The cut-off is the noise value that splits the cells at tough_ratio, so the share is exact
# whatever the noise looks like on this asteroid.
func _assign_rock() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = rock_noise_frequency

	var values := PackedFloat32Array()

	for cell in cells:
		values.append(noise.get_noise_2dv(Vector2(cell)))

	var tough_count := roundi(values.size() * tough_ratio)

	if tough_count == 0:
		return

	var sorted := values.duplicate()
	sorted.sort()
	var cut_off := sorted[sorted.size() - tough_count]
	var i := 0

	for cell in cells:
		if values[i] >= cut_off:
			cells[cell] = CellMaterials.Id.TOUGH_ROCK

		i += 1


# Clusters of the asteroid's ore, anywhere in the rock, centre included.
# Each cluster grows from a random cell in random directions (grow_part): a compact, irregular lump.
# Clusters can overlap; overlapping ones merge into a bigger vein.
func _place_ore_clusters() -> void:
	var all_cells: Array[Vector2i] = []
	all_cells.assign(cells.keys())

	var ore_target := roundi(cells.size() * randf_range(min_ore_ratio, max_ore_ratio))
	var cluster_count := randi_range(min_ore_clusters, max_ore_clusters)
	var placed := 0

	for i in cluster_count:
		var clusters_left := cluster_count - i
		var size := ceili(float(ore_target - placed) / clusters_left * randf_range(0.5, 1.5))

		if clusters_left == 1:
			size = ore_target - placed

		for cell in grow_part(all_cells.pick_random(), size):
			if cells[cell] != ore_type:
				cells[cell] = ore_type
				placed += 1


# Finds the band: the cells within visible_depth layers of open space. Layer 1 is the surface
# (cells with an empty side), layer 2 the cells touching layer 1, and so on. Open space includes
# craters and drill holes, so cutting into the rock moves the band inward.
# Ore in the band gets revealed. Returns the ore cells revealed just now, to repaint them.
func _update_band() -> Array[Vector2i]:
	_band.clear()
	var layer_cells: Array[Vector2i] = []

	for cell in cells:
		for offset in NEIGHBOURS:
			if not cells.has(cell + offset):
				_band[cell] = true
				layer_cells.append(cell)
				break

	var layer := 1

	while layer < visible_depth and not layer_cells.is_empty():
		var next_layer: Array[Vector2i] = []

		for cell in layer_cells:
			for offset in NEIGHBOURS:
				var neighbour := cell + offset

				if cells.has(neighbour) and not _band.has(neighbour):
					_band[neighbour] = true
					next_layer.append(neighbour)

		layer_cells = next_layer
		layer += 1

	var newly_revealed: Array[Vector2i] = []

	for cell in _band:
		if cells[cell] == ore_type and not revealed_ore.has(cell):
			revealed_ore[cell] = true
			newly_revealed.append(cell)

	return newly_revealed


# Craters in texels: x, y = centre, z = radius. Placed anywhere; only the core shows them.
func _make_craters() -> Array[Vector3]:
	var craters: Array[Vector3] = []
	var all_cells := cells.keys()
	var count := roundi(cells.size() * craters_per_100_cells / 100.0)

	for i in count:
		var cell: Vector2i = all_cells.pick_random()
		var center := (Vector2(cell) + Vector2(randf(), randf())) * AsteroidLook.TEXELS_PER_CELL
		craters.append(Vector3(center.x, center.y, randf_range(min_crater_radius, max_crater_radius)))

	return craters


# Index of a random candidate, soft ones much more likely (weight 1 / hardness²).
func _pick_soft_index(candidates: Array[Vector2i]) -> int:
	var weights := PackedFloat32Array()

	for cell in candidates:
		var hardness := get_hardness(cell)
		weights.append(1.0 / (hardness * hardness))

	return _rng.rand_weighted(weights)


func _update_mass() -> void:
	mass = cells.size() * mass_per_cell


func _apply_cell_changes() -> void:
	_changes_pending = false

	if cells.is_empty():
		return

	_split_disconnected_parts()
	var newly_revealed := _update_band()
	_look.repaint(newly_revealed, cells, revealed_ore)
	_look.update_cells(cells, _band)
	_rebuild_shapes()
	_update_mass()


# Replaces every collision shape with one rectangle per merged rectangle.
# Each rectangle gets its own shape owner, whose transform puts the shape on the rectangle's centre.
# This matters: Godot computes the centre of mass (and inertia) from the shapes' origins,
# weighted by area. Shapes with their geometry offset from their origin give a wrong centre of mass.
func _rebuild_shapes() -> void:
	_rects = merge_cells(cells.keys())

	for owner_id in get_shape_owners():
		remove_shape_owner(owner_id)

	for rect in _rects:
		var owner_id := create_shape_owner(self)
		var center := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * cell_size
		shape_owner_set_transform(owner_id, Transform2D(0.0, center))
		shape_owner_add_shape(owner_id, _get_rect_shape(rect.size))

	shapes_rebuilt.emit()


func _get_rect_shape(size_in_cells: Vector2i) -> RectangleShape2D:
	if not _rect_shapes.has(size_in_cells):
		var shape := RectangleShape2D.new()
		shape.size = Vector2(size_in_cells) * cell_size
		_rect_shapes[size_in_cells] = shape

	return _rect_shapes[size_in_cells]


# Merges cells into rectangles: horizontal runs first, then a run grows downward
# while the next row has a run with exactly the same start and width.
# A round asteroid of ~1800 cells becomes roughly 50-100 rectangles.
# Static so SmelterChunk (cells inside the smelter) can use it too.
# Untyped Array on purpose: accepts both Array[Vector2i] and cells.keys().
static func merge_cells(cell_list: Array) -> Array[Rect2i]:
	var sorted: Array[Vector2i] = []
	sorted.assign(cell_list)
	sorted.sort_custom(_is_before_in_rows)

	var rects: Array[Rect2i] = []
	var open: Dictionary[Vector2i, int] = {} # (start x, width) -> rect ending on the previous row
	var next_open: Dictionary[Vector2i, int] = {}
	var row := sorted[0].y - 2
	var i := 0

	while i < sorted.size():
		var start := sorted[i]
		var width := 1

		while i + width < sorted.size() and sorted[i + width] == start + Vector2i(width, 0):
			width += 1

		i += width

		if start.y != row:
			if start.y == row + 1:
				open = next_open
			else:
				open = {}

			next_open = {}
			row = start.y

		var run_key := Vector2i(start.x, width)
		var index: int

		if open.has(run_key):
			index = open[run_key]
			open.erase(run_key)
			var grown := rects[index]
			grown.size.y += 1
			rects[index] = grown
		else:
			index = rects.size()
			rects.append(Rect2i(start.x, start.y, width, 1))

		next_open[run_key] = index

	return rects


# Cells grouped by how they look (CellMaterials.get_display_id), each group merged into rectangles.
# Display material id -> Array[Rect2i]. Static: SmelterChunk uses it (chunks in the smelter are drawn flat).
static func merge_cells_by_look(materials: Dictionary[Vector2i, int], revealed: Dictionary[Vector2i, bool]) -> Dictionary[int, Array]:
	var groups: Dictionary[int, Array] = {}

	for cell in materials:
		var id := CellMaterials.get_display_id(materials[cell], revealed.has(cell))

		if not groups.has(id):
			groups[id] = []

		groups[id].append(cell)

	var merged: Dictionary[int, Array] = {}

	for id in groups:
		merged[id] = merge_cells(groups[id])

	return merged


func _split_disconnected_parts() -> void:
	var parts := _find_connected_parts()

	if parts.size() < 2:
		return

	parts.sort_custom(_is_bigger_part)
	var parent_center := _get_global_center(cells.keys())

	# parts[0] is the biggest: it stays in this body. Every other part leaves.
	for i in range(1, parts.size()):
		var part: Array[Vector2i] = parts[i]

		if part.size() >= min_chunk_cells:
			_spawn_chunk(part, parent_center)
		else:
			_erase_cells(part)


# Flood fill: groups cells that touch by a side (not by a corner).
func _find_connected_parts() -> Array[Array]:
	var parts: Array[Array] = []
	var visited: Dictionary[Vector2i, bool] = {}

	for start in cells:
		if visited.has(start):
			continue

		var part: Array[Vector2i] = []
		var to_visit: Array[Vector2i] = [start]
		visited[start] = true

		while not to_visit.is_empty():
			var cell: Vector2i = to_visit.pop_back()
			part.append(cell)

			for offset in NEIGHBOURS:
				var neighbour := cell + offset

				if cells.has(neighbour) and not visited.has(neighbour):
					visited[neighbour] = true
					to_visit.append(neighbour)

		parts.append(part)

	return parts


# The chunk copies this body's transform and keeps the same cell coordinates,
# so every cell stays exactly where it was on screen.
func _spawn_chunk(part: Array[Vector2i], parent_center: Vector2) -> void:
	# Same local coordinates and same transform: the chunk's centre can be computed from here.
	var offset := _get_global_center(part) - parent_center
	var chunk := _cut_out(part)
	var spin_velocity := Vector2(-angular_velocity * offset.y, angular_velocity * offset.x)
	var kick := offset.normalized() * split_kick

	chunk.linear_velocity = linear_velocity + spin_velocity + kick
	chunk.angular_velocity = angular_velocity


# Moves these cells (their materials, and which ore has been seen) out of this body into a new
# chunk, exactly where they were. The caller gives the chunk its velocity.
func _cut_out(part: Array[Vector2i]) -> Asteroid:
	var chunk: Asteroid = load(scene_file_path).instantiate()
	chunk.cell_size = cell_size
	chunk.mass_per_cell = mass_per_cell
	chunk.visible_depth = visible_depth
	chunk.ore_type = ore_type
	chunk.look_seed = look_seed
	chunk.inherited_look = _look
	chunk.core_shade = core_shade
	chunk.edge_shade = edge_shade
	chunk.outline_color = outline_color

	var space: Node = space_parent if is_instance_valid(space_parent) else get_parent()
	var space_2d := space as Node2D

	if space == get_parent():
		chunk.transform = transform # Same parent node, so local transform = same place
	elif space_2d != null:
		chunk.transform = space_2d.global_transform.affine_inverse() * global_transform
	else:
		chunk.transform = global_transform

	for cell in part:
		chunk.cells[cell] = cells[cell]

		if revealed_ore.has(cell):
			chunk.revealed_ore[cell] = true

		if damage.has(cell):
			chunk.damage[cell] = damage[cell]
			chunk._damage_memory_left[cell] = _damage_memory_left[cell]

	_erase_cells(part)
	space.add_child(chunk)
	return chunk


func _erase_cells(part: Array[Vector2i]) -> void:
	for cell in part:
		cells.erase(cell)
		revealed_ore.erase(cell)
		_forget_damage(cell)


func _forget_damage(cell: Vector2i) -> void:
	damage.erase(cell)
	_damage_memory_left.erase(cell)


# Untyped Array on purpose: accepts both Array[Vector2i] and cells.keys().
func _get_global_center(cell_list: Array) -> Vector2:
	var sum := Vector2.ZERO

	for cell in cell_list:
		sum += Vector2(cell) + Vector2(0.5, 0.5)

	return to_global(sum / cell_list.size() * cell_size)


static func _is_closer(a: Dictionary, b: Dictionary) -> bool:
	return a["distance"] < b["distance"]


static func _is_bigger_part(a: Array, b: Array) -> bool:
	return a.size() > b.size()


static func _is_before_in_rows(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or a.y == b.y and a.x < b.x
