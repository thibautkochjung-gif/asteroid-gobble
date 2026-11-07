class_name Projectile
extends Node2D

# Flies straight (no drag in space). Each physics frame it tests the segment it just travelled
# against the asteroid cells, so a fast shot can't tunnel through a thin chunk.
# On impact it vaporizes a few cells at the hit point (a small crater), then knocks a few small
# chunks loose around it. Hardness matters: the crater budget is in soft-rock cells and each cell
# costs its hardness, and chunks break along soft rock, so tough patches tend to stay attached.

@export_group("Impact")
@export var min_vaporized_cells: int = 4 # Crater budget, in soft-rock cells
@export var max_vaporized_cells: int = 6
@export var min_chunks: int = 4
@export var max_chunks: int = 8
@export var min_chunk_cells: int = 2
@export var max_chunk_cells: int = 8
@export var blast_radius_cells: float = 4.5 # Chunks start from cells this close to the hit cell. Wide enough for max_chunks
@export var chunk_speed: float = 90.0 # px/s, relative to the asteroid
@export var spread_degrees: float = 45.0 # Around the surface's outward direction. Keep under 90: chunks then always fly away from the rock

var velocity: Vector2 = Vector2.ZERO # Set by the launcher
var lifetime: float = 2.0 # Set by the launcher


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var hits := Asteroid.find_hits_on_ray(get_tree(), from, to, 1)

	if not hits.is_empty():
		_explode(hits[0])
		queue_free()
		return

	global_position = to
	lifetime -= delta

	if lifetime <= 0.0:
		queue_free()


func _explode(hit: Dictionary) -> void:
	var asteroid: Asteroid = hit["asteroid"]
	var impact_cell: Vector2i = hit["cell"]

	# Crater: the hit cell and connected ones around it, soft ones first, while the budget lasts.
	# The hit cell always goes. Positions and colours are read before removal.
	var budget := float(randi_range(min_vaporized_cells, max_vaporized_cells))
	var crater: Array[Vector2i] = []

	for cell in asteroid.grow_part(impact_cell, max_vaporized_cells, true):
		var hardness := asteroid.get_hardness(cell)

		if hardness > budget and not crater.is_empty():
			break

		budget -= hardness
		crater.append(cell)

	var vaporized_points := PackedVector2Array()

	for cell in crater:
		vaporized_points.append(asteroid.get_cell_global_position(cell))

	var cloud_velocity := asteroid.get_velocity_at(vaporized_points[0])
	var dust_color := asteroid.get_cell_color(impact_cell)

	for cell in crater:
		asteroid.remove_cell(cell)

	Fx.spawn_vaporize(vaporized_points, velocity.normalized(), dust_color, cloud_velocity)

	for _i in randi_range(min_chunks, max_chunks):
		var seeds := asteroid.get_cells_near(impact_cell, blast_radius_cells)

		if seeds.is_empty():
			break

		var part := asteroid.grow_part(asteroid.pick_soft_cell(seeds), randi_range(min_chunk_cells, max_chunk_cells), true)
		var is_whole_asteroid := part.size() >= asteroid.cells.size()
		var outward := asteroid.get_outward_direction(part)
		var direction := outward.rotated(deg_to_rad(randf_range(-spread_degrees, spread_degrees)))
		var part_velocity := asteroid.get_velocity_at(asteroid.get_part_global_center(part))
		asteroid.detach_cells(part, part_velocity + direction * chunk_speed)

		if is_whole_asteroid:
			break
