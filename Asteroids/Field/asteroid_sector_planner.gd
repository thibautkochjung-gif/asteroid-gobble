class_name AsteroidSectorPlanner
extends RefCounted

# Works out which asteroids a sector holds, as data (Spec), from the world seed and the sector's
# coordinates only: the same sector always gets the same rocks, whatever was loaded before.
# No nodes: the radar will be able to read sectors from here later.
# One planner per thread (it owns its noise). Planning a sector takes a few ms.
#
# Each sector rolls its own formations and lone rocks (its "origin" content). A formation centred
# in a sector can spill into the next one, so planning a sector looks at the 5 x 5 sectors around
# it. Two rocks must never overlap, even across a sector border: a rock is dropped when it
# overlaps a rock with a higher priority (the bigger one) among all the planned rocks, dropped or
# not. Both sectors on each side of a border see the same rocks, so they make the same choice.

const REACH_SECTORS: int = 2 # Sectors looked at on each side. Holds as long as a formation reaches less than one sector
const PLACEMENT_TRIES: int = 8 # Spots tried for a formation's rock before it settles on one that overlaps

var profile: AsteroidFieldProfile
var world_seed: int = 1
var cell_size: float = 4.0 # Asteroid cell size, px
var pinned: Array[PinnedFormation] = [] # Formations placed by hand (the starter cluster)
var clear_center := Vector2.ZERO # No rock within clear_radius of this point (the drop-off spot)
var clear_radius: float = 0.0

var _density: FastNoiseLite


# A rock to make. The field turns it into an AsteroidBlueprint, then an Asteroid.
class Spec:
	var id: int # Same rock, same id, every time the sector loads
	var position := Vector2.ZERO
	var rotation: float = 0.0
	var radius_in_cells: float = 1.0
	var bound: float = 0.0 # px, outer radius used for spacing
	var generation_seed: int = 1
	var ore_type: int = CellMaterials.Id.NICKEL_IRON
	var ore_ratio: float = 0.0
	var linear_velocity := Vector2.ZERO
	var angular_velocity: float = 0.0

	# Bigger rocks win. Same size: the id decides, so every sector agrees.
	func outranks(other: Spec) -> bool:
		return bound > other.bound or bound == other.bound and id > other.id


class PinnedFormation:
	var formation: AsteroidFormation
	var center := Vector2.ZERO
	var formation_seed: int = 1


func _init(field_profile: AsteroidFieldProfile, seed_value: int, rock_cell_size: float) -> void:
	profile = field_profile
	world_seed = seed_value
	cell_size = rock_cell_size
	_density = profile.make_density_noise(world_seed)


func get_density(point: Vector2) -> float:
	return profile.get_density(_density, point)


func get_sector(point: Vector2) -> Vector2i:
	return Vector2i((point / profile.sector_size).floor())


func get_sector_rect(sector: Vector2i) -> Rect2:
	return Rect2(Vector2(sector) * profile.sector_size, Vector2.ONE * profile.sector_size)


# Every rock whose centre lies in this sector.
func plan_sector(sector: Vector2i) -> Array[Spec]:
	var nearby: Array[Spec] = []

	for x in range(-REACH_SECTORS, REACH_SECTORS + 1):
		for y in range(-REACH_SECTORS, REACH_SECTORS + 1):
			nearby.append_array(_plan_origin(sector + Vector2i(x, y)))

	for i in pinned.size():
		var pin := pinned[i]
		var pin_sector := get_sector(pin.center)

		if absi(pin_sector.x - sector.x) <= REACH_SECTORS and absi(pin_sector.y - sector.y) <= REACH_SECTORS:
			nearby.append_array(_spawn_formation(pin.formation, pin.center, pin.formation_seed, Vector3i(-1000000, i, 0)))

	var rect := get_sector_rect(sector)
	var neighbours: Array[Spec] = []
	var kept: Array[Spec] = []

	# Only rocks around this sector can overlap one of its rocks.
	var around := rect.grow(profile.sector_size * 0.5)

	for spec in nearby:
		if around.has_point(spec.position):
			neighbours.append(spec)

	for spec in neighbours:
		if not rect.has_point(spec.position):
			continue

		if clear_radius > 0.0 and spec.position.distance_to(clear_center) < clear_radius + spec.bound:
			continue

		if not _is_crowded_out(spec, neighbours):
			kept.append(spec)

	return kept


func _is_crowded_out(spec: Spec, others: Array[Spec]) -> bool:
	for other in others:
		if other == spec or not other.outranks(spec):
			continue

		var reach := spec.bound + other.bound + profile.rock_gap

		if spec.position.distance_squared_to(other.position) < reach * reach:
			return true

	return false


# The formations and lone rocks rolled by this sector. They can reach into the next sectors.
func _plan_origin(sector: Vector2i) -> Array[Spec]:
	var specs: Array[Spec] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(sector.x, sector.y, world_seed))

	var rect := get_sector_rect(sector)
	var density := get_density(rect.get_center())

	var formation_count := _roll_count(rng, profile.formations_per_sector)

	for i in formation_count:
		var center := rect.position + Vector2(rng.randf(), rng.randf()) * profile.sector_size
		var formation := _pick_formation(rng)
		var formation_seed := rng.randi()

		# Kept with a chance equal to the density where it sits: formations thin out toward the
		# empty swathes smoothly, not at the sectors' edges.
		if formation == null or rng.randf() >= get_density(center):
			continue

		specs.append_array(_spawn_formation(formation, center, formation_seed, Vector3i(sector.x, sector.y, i)))

	var lone_expected := profile.lone_rocks_per_sector * density + profile.lone_rocks_in_empty_space * (1.0 - density)
	var lone_count := _roll_count(rng, lone_expected)
	var no_ores: Array[int] = []

	for j in lone_count:
		var position := rect.position + Vector2(rng.randf(), rng.randf()) * profile.sector_size
		var radius := _roll_size(rng, profile.min_lone_radius, profile.max_lone_radius, profile.lone_size_skew)
		var drift := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * profile.drift_jitter
		var id := hash(Vector4i(sector.x, sector.y, -1, j))
		specs.append(_make_spec(rng, position, radius, id, null, no_ores, drift))

	return specs


func _spawn_formation(formation: AsteroidFormation, center: Vector2, formation_seed: int, key: Vector3i) -> Array[Spec]:
	var specs: Array[Spec] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = formation_seed

	var area_radius := rng.randf_range(formation.min_area_radius, formation.max_area_radius)
	var stretch := sqrt(rng.randf_range(1.0, maxf(formation.max_area_stretch, 1.0)))
	var axis := rng.randf() * TAU
	var drift := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * formation.max_drift
	var ores := _pick_ores(formation, rng)
	var inner := 0.0

	if formation.has_core():
		var core_radius := rng.randf_range(formation.min_core_radius, formation.max_core_radius)
		var core := _make_spec(rng, center, core_radius, hash(Vector4i(key.x, key.y, key.z, -1)), formation, ores, drift)
		specs.append(core)
		inner = core.bound

	var count := rng.randi_range(formation.min_count, formation.max_count)

	for j in count:
		var radius := _roll_size(rng, formation.min_rock_radius, formation.max_rock_radius, formation.size_skew)
		var bound := _get_bound(radius)
		var position := center

		# A few spots are tried, so rocks of the same formation don't land on each other.
		# Overlaps with other formations are settled later, in plan_sector().
		for attempt in PLACEMENT_TRIES:
			# Uniform over the disc at concentration 1, bunched toward the middle above.
			var distance := inner + (area_radius - inner) * pow(rng.randf(), 0.5 * formation.concentration)
			var offset := Vector2.from_angle(rng.randf() * TAU) * distance
			position = center + Vector2(offset.x * stretch, offset.y / stretch).rotated(axis)

			if not _overlaps_any(position, bound, specs):
				break

		var id := hash(Vector4i(key.x, key.y, key.z, j))
		specs.append(_make_spec(rng, position, radius, id, formation, ores, drift))

	return specs


func _overlaps_any(position: Vector2, bound: float, specs: Array[Spec]) -> bool:
	for other in specs:
		var reach := bound + other.bound + profile.rock_gap

		if position.distance_squared_to(other.position) < reach * reach:
			return true

	return false


func _get_bound(radius: float) -> float:
	return maxf(radius * profile.bound_factor, 1.5) * cell_size


# formation: null for a lone rock. ores: the formation's shared ores, empty if it has none.
func _make_spec(rng: RandomNumberGenerator, position: Vector2, radius: float, id: int, formation: AsteroidFormation, ores: Array[int], drift: Vector2) -> Spec:
	var spec := Spec.new()
	spec.id = id
	spec.position = position
	spec.rotation = rng.randf() * TAU
	spec.radius_in_cells = radius
	spec.bound = _get_bound(radius)
	spec.generation_seed = rng.randi() | 1 # Never 0: 0 means "random" to an Asteroid

	var valuable: bool

	if ores.is_empty():
		spec.ore_type = CellMaterials.pick_ore_type(rng)
		valuable = rng.randf() < profile.lone_valuable_chance

		if valuable:
			spec.ore_ratio = rng.randf_range(profile.lone_min_ore_ratio, profile.lone_max_ore_ratio)
	else:
		spec.ore_type = CellMaterials.pick_ore_from(ores, rng)
		valuable = rng.randf() < formation.valuable_chance

		if valuable:
			spec.ore_ratio = rng.randf_range(formation.min_ore_ratio, formation.max_ore_ratio)

	var jitter := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * profile.drift_jitter
	spec.linear_velocity = drift + jitter

	var spin_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var spin := spin_sign * rng.randf_range(0.3, 1.0) * profile.max_spin / sqrt(maxf(radius, 1.0))

	# Whether it spins at all: rolled on the rock's own seed, so adding this roll didn't move
	# anything else in the sector.
	var spin_roll := RandomNumberGenerator.new()
	spin_roll.seed = hash(spec.generation_seed)
	spec.angular_velocity = spin if spin_roll.randf() < profile.spinning_chance else 0.0
	return spec


# The formation's shared ores: distinct, the common ones more likely. Empty if it has none.
func _pick_ores(formation: AsteroidFormation, rng: RandomNumberGenerator) -> Array[int]:
	var picked: Array[int] = []

	if not formation.has_shared_ores():
		return picked

	var left: Array[int] = CellMaterials.ORES.duplicate()
	var count := mini(rng.randi_range(formation.min_ore_types, formation.max_ore_types), left.size())

	for i in count:
		var ore := CellMaterials.pick_ore_from(left, rng)
		picked.append(ore)
		left.erase(ore)

	return picked


func _pick_formation(rng: RandomNumberGenerator) -> AsteroidFormation:
	var weights := PackedFloat32Array()

	for formation in profile.formations:
		weights.append(formation.weight)

	if weights.is_empty():
		rng.randf() # Same number of rolls either way
		return null

	return profile.formations[rng.rand_weighted(weights)]


# A whole number whose average is `expected`.
static func _roll_count(rng: RandomNumberGenerator, expected: float) -> int:
	var whole := floori(expected)
	return whole + (1 if rng.randf() < expected - whole else 0)


# From low to high on a log scale, small sizes more likely as skew grows.
static func _roll_size(rng: RandomNumberGenerator, low: float, high: float, skew: float) -> float:
	low = maxf(low, 1.0)
	return low * pow(maxf(high, low) / low, pow(rng.randf(), skew))
