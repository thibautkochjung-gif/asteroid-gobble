class_name AsteroidBlueprint
extends RefCounted

# Everything a new asteroid is made of, as plain data: its cells, its ore, its band, its painted
# look and its collision rectangles. Built away from the scene tree, so build() can run on a
# WorkerThreadPool thread: it only touches its own dictionaries, noise and images.
# The Asteroid takes it in _ready() and only has to make the textures and the collision shapes.
#
# Everything random comes from generation_seed: the same blueprint always gives the same rock.
# A giant (radius 150 cells, ~72 000 cells) takes a few seconds to build in GDScript, mostly
# painting the look. That is why the AsteroidField builds blueprints on worker threads.

# Inputs: set them before build(). The defaults match Asteroid's exports.
var generation_seed: int = 0
var radius_in_cells: float = 24.0
var shape_roughness: float = 0.35
var min_elongation: float = 1.0
var max_elongation: float = 1.35
var tough_ratio: float = 0.5
var rock_noise_frequency: float = 0.08
var visible_depth: int = 5
var ore_type: int = CellMaterials.Id.NICKEL_IRON
var ore_ratio: float = 0.0 # Share of the cells that are ore. 0 = no ore cells, only traces in the rock
var min_ore_clusters: int = 2
var max_ore_clusters: int = 4
# Rocks bigger than a medium one get more ore clusters and a bigger ore share. Up to that size,
# nothing changes. size factor = radius_in_cells / ore_reference_radius.
var ore_reference_radius: float = 24.0 # Cells. A medium rock
var ore_cluster_growth: float = 0.75 # Cluster count × size factor ^ this. Giant (×6): ~4× the clusters
var ore_share_growth: float = 0.3 # Ore share × size factor ^ this. Giant: ~1.7× the share
var max_ore_share: float = 0.25 # Ceiling on the share, whatever the size
var craters_per_100_cells: float = 0.0
var min_crater_radius: float = 2.5
var max_crater_radius: float = 6.0
var crater_floor_shade: float = 0.86
var crater_rim_shade: float = 0.62

# Outputs: filled by build().
var cells: Dictionary[Vector2i, int] = {}
var look_seed: int = 0
var revealed_ore: Dictionary[Vector2i, bool] = {}
var band: Dictionary[Vector2i, bool] = {}
var look: AsteroidLook # Painted, without GPU resources: the Asteroid makes those on the main thread
var rects: Array[Rect2i] = []

var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = generation_seed
	look_seed = _rng.randi()
	_generate_shape()

	if cells.is_empty():
		cells[Vector2i.ZERO] = CellMaterials.Id.SOFT_ROCK # A pebble too small for the disc test

	_assign_rock()

	if ore_ratio > 0.0:
		_place_ore_clusters()

	band = find_band(cells, visible_depth)

	for cell in band:
		if cells[cell] == ore_type:
			revealed_ore[cell] = true

	look = AsteroidLook.new(cells.keys(), look_seed)
	look.paint_all(cells, revealed_ore, _make_craters(), crater_floor_shade, crater_rim_shade)
	look.fill_cells(cells, band)
	rects = Asteroid.merge_cells(cells.keys())


# The cells within `depth` layers of open space. Layer 1 is the surface (cells with an empty
# side), layer 2 the cells touching layer 1, and so on. Static: chunks use it in Asteroid too.
static func find_band(materials: Dictionary[Vector2i, int], depth: int) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	var layer_cells: Array[Vector2i] = []

	for cell in materials:
		for offset in Asteroid.NEIGHBOURS:
			if not materials.has(cell + offset):
				found[cell] = true
				layer_cells.append(cell)
				break

	var layer := 1

	while layer < depth and not layer_cells.is_empty():
		var next_layer: Array[Vector2i] = []

		for cell in layer_cells:
			for offset in Asteroid.NEIGHBOURS:
				var neighbour := cell + offset

				if materials.has(neighbour) and not found.has(neighbour):
					found[neighbour] = true
					next_layer.append(neighbour)

		layer_cells = next_layer
		layer += 1

	return found


# A lumpy disc, stretched along a random axis: small asteroids are rarely round.
# The stretch keeps the area about the same: longer one way, thinner the other.
func _generate_shape() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()

	var stretch := sqrt(_rng.randf_range(min_elongation, max_elongation))
	var axis := _rng.randf() * TAU
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
	noise.seed = _rng.randi()
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


# Clusters of the asteroid's ore, anywhere in the rock, centre included. Big rocks get more
# clusters, each bigger, and a bigger share of ore overall (see ore_cluster_growth).
# Each cluster grows from a random cell in random directions: a compact, irregular lump.
# Clusters can overlap; overlapping ones merge into a bigger vein.
func _place_ore_clusters() -> void:
	var all_cells: Array[Vector2i] = []
	all_cells.assign(cells.keys())

	# Same rolls as before for small and medium rocks: they come out exactly as they used to.
	var size_factor := maxf(radius_in_cells / ore_reference_radius, 1.0)
	var share := minf(ore_ratio * pow(size_factor, ore_share_growth), max_ore_share)
	var ore_target := roundi(cells.size() * share)
	var cluster_count := roundi(_rng.randi_range(min_ore_clusters, max_ore_clusters) * pow(size_factor, ore_cluster_growth))
	var placed := 0

	for i in cluster_count:
		var clusters_left := cluster_count - i
		var size := ceili(float(ore_target - placed) / clusters_left * _rng.randf_range(0.5, 1.5))

		if clusters_left == 1:
			size = ore_target - placed

		var start := all_cells[_rng.randi_range(0, all_cells.size() - 1)]

		for cell in _grow(start, size):
			if cells[cell] != ore_type:
				cells[cell] = ore_type
				placed += 1


# Up to `count` cells connected to `start` by a side, grown in random directions.
func _grow(start: Vector2i, count: int) -> Array[Vector2i]:
	var part: Array[Vector2i] = []
	var taken: Dictionary[Vector2i, bool] = { start: true }
	var frontier: Array[Vector2i] = [start]

	while part.size() < count and not frontier.is_empty():
		var cell: Vector2i = frontier.pop_at(_rng.randi_range(0, frontier.size() - 1))
		part.append(cell)

		for offset in Asteroid.NEIGHBOURS:
			var neighbour := cell + offset

			if cells.has(neighbour) and not taken.has(neighbour):
				taken[neighbour] = true
				frontier.append(neighbour)

	return part


# Craters in texels: x, y = centre, z = radius. Placed anywhere; only the core shows them.
func _make_craters() -> Array[Vector3]:
	var craters: Array[Vector3] = []
	var count := roundi(cells.size() * craters_per_100_cells / 100.0)

	if count == 0:
		return craters

	var all_cells := cells.keys()

	for i in count:
		var cell: Vector2i = all_cells[_rng.randi_range(0, all_cells.size() - 1)]
		var center := (Vector2(cell) + Vector2(_rng.randf(), _rng.randf())) * AsteroidLook.TEXELS_PER_CELL
		craters.append(Vector3(center.x, center.y, _rng.randf_range(min_crater_radius, max_crater_radius)))

	return craters
