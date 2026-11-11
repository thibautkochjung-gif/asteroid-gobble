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
#
# Generation lives in AsteroidBlueprint, seeded by generation_seed: the same seed always gives
# the same rock. The AsteroidField builds blueprints on worker threads and hands them over
# (blueprint). A hand-placed asteroid builds its own in _ready(), from its exports.
#
# Cuts are incremental: after a cut, only the cells around it are looked at (band, broken-off
# parts, collision rectangles). A giant holds ~72 000 cells; looping over all of them after every
# laser shot took close to two seconds.

signal shapes_rebuilt # After every rebuild of the collision rectangles (a cut, a split). The rock bolter copies them

const GROUP: StringName = &"asteroids"
const HEAT_GROUP: StringName = &"heat_scanned" # Rocks with heat_cells. ScanOverlay draws them
const NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ROW_KEY_OFFSET: int = 1 << 20 # Cell coordinates stay well within ±a million
const ROW_KEY_STRIDE: int = 1 << 22

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
var heat_cells: Dictionary[Vector2i, bool] = {} # Ore cells a basic scanner picked up: shown as a blurry heat map (ScanOverlay), not exactly
var scanned_cells: Dictionary[Vector2i, bool] = {} # Cells a scanner's sweep has crossed, ore or not. Chunks keep them
var scan_found_ore: bool = false # A scanner's sweep has crossed an ore cell of this rock
var ore_type: int = CellMaterials.Id.NICKEL_IRON # Rolled at generation, inherited by chunks
var look_seed: int = 0 # Flecks, facets and cracks. Inherited by chunks
var inherited_look: AsteroidLook # Set by the parent before add_child() when this is a chunk
var damage: Dictionary[Vector2i, float] = {} # Cell -> share of the work needed to destroy it, 0..1
var generation_seed: int = 0 # 0 = random. Set it for a rock that comes out the same every time
var blueprint: AsteroidBlueprint # Set before add_child() by the AsteroidField: already built, on a thread
var field_id: int = -1 # Set by the AsteroidField: which planned rock this is. -1 = hand placed or a chunk
var was_cut: bool = false # True once a cell left this body. The AsteroidField keeps cut rocks loaded
var space_parent: Node # Where cut-off chunks go. Null = this body's parent. Set while the body rides on something (bolted to a ship by a RockBolter, held by a CacheBuoy): chunks go to space, not into the ship
var draw_offset: Vector2 = Vector2.ZERO: # Visual only (px): the physics body doesn't move. The Grinder shakes the chunk it works on with it
	set(value):
		if value == draw_offset:
			return

		draw_offset = value
		queue_redraw()

var _rects: Array[Rect2i] = [] # All cells merged into rectangles, in cell units. Used for collision
var _band: Dictionary[Vector2i, bool] = {} # Cells within visible_depth layers of open space. The others are the core
var _look: AsteroidLook
var _rect_shapes: Dictionary[Vector2i, RectangleShape2D] = {} # One resource per rectangle size, reused
var _changes_pending: bool = false
var _damage_memory_left: Dictionary[Vector2i, float] = {} # Cell -> seconds before it forgets its damage
var _rng := RandomNumberGenerator.new()
var _removed: Array[Vector2i] = [] # Cells gone since the last _apply_cell_changes()
var _cell_sum := Vector2.ZERO # Sum of the cell centres, in cell units. Kept up to date: the centre without a loop
var _bound_center := Vector2.ZERO # Cell units. The centre _bound_radius was measured from. Fixed: cells only go away
var _ore_count: int = 0 # Ore cells left, seen or not
var _bound_radius: float = 0.0 # px, from the centre to the farthest cell at creation. Cells only go away, so it stays an upper bound


func _ready() -> void:
	add_to_group(GROUP)

	if not heat_cells.is_empty():
		add_to_group(HEAT_GROUP) # A chunk of a heat-scanned rock

	if cells.is_empty() and blueprint == null:
		blueprint = make_blueprint()
		blueprint.build()

	if blueprint != null:
		_take_blueprint()
	else:
		_set_up_from_cells()

	_look.create_gpu_resources()
	_look.set_shades(outline_color, core_shade, edge_shade)
	material = _look.material

	refresh_counts()
	_apply_shapes()
	_update_mass()
	queue_redraw()
	set_process(not damage.is_empty()) # Only runs while some cell remembers damage


# A blueprint from this asteroid's exports. Rolls the ore here, from generation_seed.
func make_blueprint() -> AsteroidBlueprint:
	var plan := AsteroidBlueprint.new()
	plan.generation_seed = generation_seed if generation_seed != 0 else randi()

	var rolls := RandomNumberGenerator.new()
	rolls.seed = hash(plan.generation_seed + 1)
	plan.ore_type = CellMaterials.pick_ore_type(rolls)

	if force_valuable or rolls.randf() < valuable_chance:
		plan.ore_ratio = rolls.randf_range(min_ore_ratio, max_ore_ratio)

	plan.radius_in_cells = radius_in_cells
	plan.shape_roughness = shape_roughness
	plan.min_elongation = min_elongation
	plan.max_elongation = max_elongation
	plan.tough_ratio = tough_ratio
	plan.rock_noise_frequency = rock_noise_frequency
	plan.visible_depth = visible_depth
	plan.min_ore_clusters = min_ore_clusters
	plan.max_ore_clusters = max_ore_clusters
	plan.craters_per_100_cells = craters_per_100_cells
	plan.min_crater_radius = min_crater_radius
	plan.max_crater_radius = max_crater_radius
	plan.crater_floor_shade = crater_floor_shade
	plan.crater_rim_shade = crater_rim_shade
	return plan


# Recounts the centre and the ore from scratch. Call it after changing `cells` by hand (tests).
func refresh_counts() -> void:
	_cell_sum = Vector2.ZERO
	_ore_count = 0

	for cell in cells:
		_cell_sum += Vector2(cell) + Vector2(0.5, 0.5)

		if cells[cell] == ore_type:
			_ore_count += 1

	var center := _cell_sum / cells.size()
	var farthest := 0.0
	_bound_center = center

	for rect in _rects:
		for corner in [Vector2(rect.position), Vector2(rect.end), Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			farthest = maxf(farthest, center.distance_to(corner))

	_bound_radius = farthest * cell_size


func _take_blueprint() -> void:
	cells = blueprint.cells
	ore_type = blueprint.ore_type
	look_seed = blueprint.look_seed
	revealed_ore = blueprint.revealed_ore
	visible_depth = blueprint.visible_depth
	_band = blueprint.band
	_look = blueprint.look
	_rects = blueprint.rects
	blueprint = null # Done with it


# A chunk: the parent filled `cells` and handed over its look. Everything here is chunk-sized.
func _set_up_from_cells() -> void:
	_band = AsteroidBlueprint.find_band(cells, visible_depth)
	var newly_revealed: Array[Vector2i] = []

	for cell in _band:
		if cells[cell] == ore_type and not revealed_ore.has(cell):
			revealed_ore[cell] = true
			newly_revealed.append(cell)

	_look = AsteroidLook.new(cells.keys(), look_seed)

	if inherited_look == null:
		_look.paint_all(cells, revealed_ore, [], crater_floor_shade, crater_rim_shade)
	else:
		_look.copy_from(inherited_look)
		_look.repaint(newly_revealed, cells, revealed_ore)
		inherited_look = null # Done with it: don't keep the parent's image alive

	_look.fill_cells(cells, _band)
	_rects = merge_cells(cells.keys())


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
	draw_set_transform(draw_offset)
	draw_texture_rect(_look.get_texture(), _look.get_draw_rect(cell_size), false)


func remove_cell(cell: Vector2i) -> void:
	if not cells.has(cell):
		return

	_erase_cell(cell)

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
	return _ore_count > 0


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


# Ore cells left in this body, seen or not. For the precision scanner's estimate.
func get_ore_cell_count() -> int:
	return _ore_count


# Reveals the ore cells among these, however deep. For the precision scanner.
# Returns how many cells were revealed just now.
func reveal_ore_cells(cell_list: Array[Vector2i]) -> int:
	var newly_revealed: Array[Vector2i] = []

	for cell in cell_list:
		if cells.get(cell, -1) != ore_type or revealed_ore.has(cell):
			continue

		revealed_ore[cell] = true
		heat_cells.erase(cell) # Seen for real now: no need for the blur
		newly_revealed.append(cell)

	if not newly_revealed.is_empty():
		_look.repaint(newly_revealed, cells, revealed_ore)

	return newly_revealed.size()


# Records the cells a scanner's sweep crossed. The scanners use it for how much of the rock they've
# covered, and whether they've met ore yet.
func mark_scanned(cell_list: Array[Vector2i]) -> void:
	for cell in cell_list:
		if not cells.has(cell):
			continue

		scanned_cells[cell] = true

		if cells[cell] == ore_type:
			scan_found_ore = true


# Share of the cells a scanner's sweep has crossed, 0..1.
func get_scan_coverage() -> float:
	if cells.is_empty():
		return 0.0

	return float(scanned_cells.size()) / cells.size()


# Marks the ore cells among these as picked up by a basic scanner: ScanOverlay shows them as a
# blurry heat map. Stays for good, and chunks keep it. Returns how many cells were added.
func add_heat(cell_list: Array[Vector2i]) -> int:
	var added := 0

	for cell in cell_list:
		if cells.get(cell, -1) != ore_type or revealed_ore.has(cell) or heat_cells.has(cell):
			continue

		heat_cells[cell] = true
		added += 1

	if added > 0:
		add_to_group(HEAT_GROUP)

	return added


# Removes the cells along a crack (a splitter's wedge, a lance's blast) and splits the rock along
# it right away, instead of waiting for the deferred pass: the caller needs the pieces now, to
# push them apart. This body keeps the biggest piece.
# Returns the new pieces (not this body). Empty if the crack didn't cut the rock through.
func split_along(crack: Array[Vector2i]) -> Array[Asteroid]:
	for cell in crack:
		if cells.has(cell):
			_erase_cell(cell)

	if cells.is_empty():
		queue_free()
		return []

	return _apply_cell_changes()


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
# From a running sum: no loop, cheap enough to call every frame on a giant.
func get_global_center() -> Vector2:
	if cells.is_empty():
		return global_position

	return to_global(_cell_sum / cells.size() * cell_size)


# Radius (px) of a circle around get_global_center() that holds every cell.
func get_bound_radius() -> float:
	return _bound_radius


# True if some cell may lie within `distance` of a global point. Cheap: a circle test.
func may_be_near(global_point: Vector2, distance: float) -> bool:
	var reach := _bound_radius + distance
	return get_global_center().distance_squared_to(global_point) <= reach * reach


# True if some cell may lie on the segment. Cheap: a circle test.
func may_cross(segment_start: Vector2, segment_end: Vector2) -> bool:
	var center := get_global_center()
	var closest := Geometry2D.get_closest_point_to_segment(center, segment_start, segment_end)
	return closest.distance_squared_to(center) <= _bound_radius * _bound_radius


# Asteroids that may hold a cell within `distance` of a global point (a circle test, no cells).
# Use it before anything that walks cells or rectangles: with a field, there are hundreds of rocks.
static func find_near(tree: SceneTree, global_point: Vector2, distance: float) -> Array[Asteroid]:
	var found: Array[Asteroid] = []

	for node in tree.get_nodes_in_group(GROUP):
		var asteroid := node as Asteroid

		if asteroid != null and asteroid.may_be_near(global_point, distance):
			found.append(asteroid)

	return found


func get_local_center() -> Vector2:
	return to_local(get_global_center())


# Returns the filled cells crossed by the segment, nearest first. max_count > 0 stops after that
# many (1 = just the first cell hit: most callers only need that).
# Only the part of the segment inside the rock's bounding circle is walked.
# Each hit: { "asteroid", "cell", "distance" (entry, px), "exit" (px) }
func get_cells_on_ray(ray_start: Vector2, ray_end: Vector2, max_count: int = 0) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []

	if cells.is_empty():
		return hits

	var to_local_space := global_transform.affine_inverse()
	var start := to_local_space * ray_start / cell_size # In "cell units"
	var end := to_local_space * ray_end / cell_size
	var length := start.distance_to(end)

	if length == 0.0:
		return hits

	var direction := (end - start) / length

	# Clip to the bounding circle, around the centre it was measured from (+ 1 cell, for safety)
	var radius := _bound_radius / cell_size + 1.0
	var to_start := start - _bound_center
	var b := direction.dot(to_start)
	var discriminant := b * b - (to_start.length_squared() - radius * radius)

	if discriminant < 0.0:
		return hits

	var root := sqrt(discriminant)
	var t_enter := maxf(-b - root, 0.0)
	var t_exit := minf(-b + root, length)

	if t_enter >= t_exit:
		return hits

	var origin := start + direction * t_enter
	var cell := Vector2i(floori(origin.x), floori(origin.y))

	var step_x := 1 if direction.x > 0.0 else -1
	var step_y := 1 if direction.y > 0.0 else -1
	var next_x := cell.x + 1 if step_x > 0 else cell.x
	var next_y := cell.y + 1 if step_y > 0 else cell.y
	var t_max_x := t_enter + (next_x - origin.x) / direction.x if direction.x != 0.0 else INF
	var t_max_y := t_enter + (next_y - origin.y) / direction.y if direction.y != 0.0 else INF
	var t_delta_x := absf(1.0 / direction.x) if direction.x != 0.0 else INF
	var t_delta_y := absf(1.0 / direction.y) if direction.y != 0.0 else INF

	var t := t_enter
	while t < t_exit:
		var t_next := minf(t_max_x, t_max_y)

		if cells.has(cell):
			hits.append({
				"asteroid": self,
				"cell": cell,
				"distance": t * cell_size,
				"exit": minf(t_next, length) * cell_size,
			})

			if max_count > 0 and hits.size() >= max_count:
				return hits

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
	var all: Array[Asteroid] = []
	all.assign(tree.get_nodes_in_group(GROUP))
	return find_hits_on_ray_among(all, ray_start, ray_end, max_count)


# Same, among these asteroids only (say, the ones find_near() returned a moment ago). For rays
# cast every frame: walking the whole field each time is what costs.
static func find_hits_on_ray_among(asteroids: Array[Asteroid], ray_start: Vector2, ray_end: Vector2, max_count: int) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []

	for asteroid in asteroids:
		if not is_instance_valid(asteroid) or not asteroid.may_cross(ray_start, ray_end):
			continue

		# Each rock's first max_count cells are enough: the overall first max_count are among them
		hits.append_array(asteroid.get_cells_on_ray(ray_start, ray_end, max_count))

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
		var index := _pick_soft_index(frontier) if prefer_soft else _rng.randi_range(0, frontier.size() - 1)
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
	chunk.angular_velocity = angular_velocity + _rng.randf_range(-detach_spin, detach_spin)

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


# Index of a random candidate, soft ones much more likely (weight 1 / hardness²).
func _pick_soft_index(candidates: Array[Vector2i]) -> int:
	var weights := PackedFloat32Array()

	for cell in candidates:
		var hardness := get_hardness(cell)
		weights.append(1.0 / (hardness * hardness))

	return _rng.rand_weighted(weights)


func _update_mass() -> void:
	mass = cells.size() * mass_per_cell


# Everything that follows from the cells gone since last time (_removed), worked out around them only.
# Returns the chunks that broke off (split_along uses them).
func _apply_cell_changes() -> Array[Asteroid]:
	_changes_pending = false

	if cells.is_empty():
		_removed.clear()
		return []

	var broken_off := _split_disconnected_parts() # Adds the cells of broken-off parts to _removed
	var newly_banded := _grow_band()
	var newly_revealed: Array[Vector2i] = []

	for cell in newly_banded:
		if cells[cell] == ore_type and not revealed_ore.has(cell):
			revealed_ore[cell] = true
			newly_revealed.append(cell)

	_look.repaint(newly_revealed, cells, revealed_ore)
	_look.patch_cells(_removed + newly_banded, cells, _band)
	_remerge_rects()
	_apply_shapes()
	_update_mass()
	_removed.clear()
	return broken_off


# A cut opens the rock: cells near the hole may now be within visible_depth layers of open space.
# The band only grows (a cut never fills space), so a short search from the hole's edge is enough.
# Returns the cells that just joined the band.
func _grow_band() -> Array[Vector2i]:
	var added: Array[Vector2i] = []
	var reached: Dictionary[Vector2i, bool] = {}
	var layer_cells: Array[Vector2i] = []

	for cell in _removed:
		_band.erase(cell)

		for offset in NEIGHBOURS:
			var neighbour := cell + offset

			if cells.has(neighbour) and not reached.has(neighbour):
				reached[neighbour] = true
				layer_cells.append(neighbour)

	var layer := 1

	while not layer_cells.is_empty():
		for cell in layer_cells:
			if not _band.has(cell):
				_band[cell] = true
				added.append(cell)

		if layer >= visible_depth:
			break

		var next_layer: Array[Vector2i] = []

		for cell in layer_cells:
			for offset in NEIGHBOURS:
				var neighbour := cell + offset

				if cells.has(neighbour) and not reached.has(neighbour):
					reached[neighbour] = true
					next_layer.append(neighbour)

		layer_cells = next_layer
		layer += 1

	return added


# Rectangles never overlap, so each removed cell belonged to exactly one. Only those rectangles
# are merged again, from the cells they still hold. The others stay as they are.
# The result can hold a few more rectangles than a full merge would: it can't join a new
# rectangle with an untouched one. Cheap compared with merging tens of thousands of cells.
func _remerge_rects() -> void:
	var removed_by_row: Dictionary[int, Array] = {}

	for cell in _removed:
		if not removed_by_row.has(cell.y):
			removed_by_row[cell.y] = []

		removed_by_row[cell.y].append(cell.x)

	var kept: Array[Rect2i] = []
	var loose: Array[Vector2i] = []

	for rect in _rects:
		if not _rect_lost_cells(rect, removed_by_row):
			kept.append(rect)
			continue

		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)

				if cells.has(cell):
					loose.append(cell)

	if not loose.is_empty():
		kept.append_array(merge_cells(loose))

	_rects = kept


static func _rect_lost_cells(rect: Rect2i, removed_by_row: Dictionary[int, Array]) -> bool:
	for y in range(rect.position.y, rect.end.y):
		if not removed_by_row.has(y):
			continue

		for x in removed_by_row[y]:
			if x >= rect.position.x and x < rect.end.x:
				return true

	return false


# Replaces every collision shape with one rectangle per merged rectangle.
# Each rectangle gets its own shape owner, whose transform puts the shape on the rectangle's centre.
# This matters: Godot computes the centre of mass (and inertia) from the shapes' origins,
# weighted by area. Shapes with their geometry offset from their origin give a wrong centre of mass.
func _apply_shapes() -> void:
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
	var sorted := _sort_in_rows(cell_list)

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


# Returns the chunks it made.
func _split_disconnected_parts() -> Array[Asteroid]:
	var chunks: Array[Asteroid] = []
	var parts := _find_broken_off_parts()

	if parts.is_empty():
		return chunks

	var parent_center := get_global_center() # Before the parts leave

	for part: Array[Vector2i] in parts:
		if part.size() >= min_chunk_cells:
			chunks.append(_spawn_chunk(part, parent_center))
		else:
			_erase_cells(part)

	return chunks


# A cut can break the rock in pieces. Only the cells around the cut can tell: a search starts
# from each of them, all side by side, one cell per turn. Searches that meet are in the same piece
# and merge. A search that runs out of cells has walked a whole piece. Once a single search is
# still running, the rest of the rock is one piece: no need to walk it.
# The pieces run out in order of size, smallest first, so the one left is the biggest: it stays
# in this body. Returns the pieces that leave.
func _find_broken_off_parts() -> Array[Array]:
	var parts: Array[Array] = []
	var starts: Array[Vector2i] = []
	var seen: Dictionary[Vector2i, int] = {} # Cell -> the search that reached it first

	for cell in _removed:
		for offset in NEIGHBOURS:
			var neighbour := cell + offset

			if cells.has(neighbour) and not seen.has(neighbour):
				seen[neighbour] = starts.size()
				starts.append(neighbour)

	if starts.size() < 2:
		return parts

	var merged_into: Array[int] = [] # Search -> the search it merged into (itself if it didn't)
	var frontiers: Array[Array] = []
	var walked: Array[Array] = []

	for i in starts.size():
		merged_into.append(i)
		frontiers.append([starts[i]])
		walked.append([starts[i]])

	var running := starts.size()
	var finished: Array[int] = []

	while running > 1:
		for i in starts.size():
			if merged_into[i] != i or frontiers[i].is_empty():
				continue

			var cell: Vector2i = frontiers[i].pop_back()

			for offset in NEIGHBOURS:
				var neighbour := cell + offset

				if not cells.has(neighbour):
					continue

				if not seen.has(neighbour):
					seen[neighbour] = i
					frontiers[i].append(neighbour)
					walked[i].append(neighbour)
					continue

				var other := _find_search(merged_into, seen[neighbour])

				if other != i:
					merged_into[other] = i
					frontiers[i].append_array(frontiers[other])
					walked[i].append_array(walked[other])
					frontiers[other].clear()
					walked[other].clear()
					running -= 1

			if frontiers[i].is_empty():
				finished.append(i)
				running -= 1

			if running <= 1:
				break

	if running == 0:
		# Every piece was walked to the end: the biggest stays.
		var biggest := finished[0]

		for i in finished:
			if walked[i].size() > walked[biggest].size():
				biggest = i

		finished.erase(biggest)

	for i in finished:
		var part: Array[Vector2i] = []
		part.assign(walked[i])
		parts.append(part)

	return parts


static func _find_search(merged_into: Array[int], search: int) -> int:
	while merged_into[search] != search:
		search = merged_into[search]

	return search


# The chunk copies this body's transform and keeps the same cell coordinates,
# so every cell stays exactly where it was on screen.
func _spawn_chunk(part: Array[Vector2i], parent_center: Vector2) -> Asteroid:
	# Same local coordinates and same transform: the chunk's centre can be computed from here.
	var offset := _get_global_center(part) - parent_center
	var chunk := _cut_out(part)
	var spin_velocity := Vector2(-angular_velocity * offset.y, angular_velocity * offset.x)
	var kick := offset.normalized() * split_kick

	chunk.linear_velocity = linear_velocity + spin_velocity + kick
	chunk.angular_velocity = angular_velocity
	return chunk


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

		if heat_cells.has(cell):
			chunk.heat_cells[cell] = true

		if scanned_cells.has(cell):
			chunk.scanned_cells[cell] = true

			if cells[cell] == ore_type:
				chunk.scan_found_ore = true

		if damage.has(cell):
			chunk.damage[cell] = damage[cell]
			chunk._damage_memory_left[cell] = _damage_memory_left[cell]

	_erase_cells(part)
	space.add_child(chunk)
	return chunk


func _erase_cells(part: Array[Vector2i]) -> void:
	for cell in part:
		_erase_cell(cell)


# Every removal goes through here: it keeps the centre and the ore count up to date, and lists
# the cell for the next _apply_cell_changes().
func _erase_cell(cell: Vector2i) -> void:
	if cells[cell] == ore_type:
		_ore_count -= 1

	_cell_sum -= Vector2(cell) + Vector2(0.5, 0.5)
	cells.erase(cell)
	revealed_ore.erase(cell)
	heat_cells.erase(cell)
	scanned_cells.erase(cell)
	_forget_damage(cell)
	_removed.append(cell)
	was_cut = true


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


# Cells sorted row by row, left to right. Packs each cell in one integer and lets the engine sort
# them: ten times faster than sort_custom() on a giant.
static func _sort_in_rows(cell_list: Array) -> Array[Vector2i]:
	var keys := PackedInt64Array()
	keys.resize(cell_list.size())
	var i := 0

	for cell: Vector2i in cell_list:
		keys[i] = (cell.y + ROW_KEY_OFFSET) * ROW_KEY_STRIDE + cell.x + ROW_KEY_OFFSET
		i += 1

	keys.sort()

	var sorted: Array[Vector2i] = []
	sorted.resize(keys.size())

	for j in keys.size():
		var key := keys[j]
		sorted[j] = Vector2i(key % ROW_KEY_STRIDE - ROW_KEY_OFFSET, key / ROW_KEY_STRIDE - ROW_KEY_OFFSET)

	return sorted
