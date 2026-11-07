class_name BodyAnchor
extends RefCounted

# A point stuck on a body: a harpoon hook, a clamp pad's grip, a planted charge.
# On an asteroid, the point is tied to a cell. Asteroids get cut, and a chunk keeps its parent's
# cell coordinates and transform. So when the anchor's cell leaves with a chunk, the anchor finds
# that chunk and follows it. When the cell is destroyed (vaporized, smelted), the anchor is lost.
# On any other body (a prop), the point is simply fixed in the body's space.

const FOLLOW_DISTANCE: float = 24.0 # px. How far a chunk may have moved from the anchor's last spot

var body: RigidBody2D
var local_point: Vector2 # In the body's space
var cell: Vector2i
var has_cell: bool = false

var _last_global: Vector2


static func on_body(target: RigidBody2D, global_point: Vector2) -> BodyAnchor:
	var anchor := BodyAnchor.new()
	anchor.body = target
	anchor.local_point = target.to_local(global_point)
	anchor._last_global = global_point

	var asteroid := target as Asteroid

	if asteroid != null:
		anchor.cell = asteroid.get_cell_near(global_point)
		anchor.has_cell = asteroid.cells.has(anchor.cell)

	return anchor


# Call once per physics frame before reading the anchor. Returns false once it is lost.
func resolve(tree: SceneTree) -> bool:
	if not is_instance_valid(body):
		return false

	if not has_cell:
		_last_global = body.to_global(local_point)
		return true

	var asteroid := body as Asteroid

	if asteroid.cells.has(cell):
		_last_global = body.to_global(local_point)
		return true

	var chunk := _find_chunk_with_cell(tree)

	if chunk == null:
		return false

	body = chunk
	_last_global = body.to_global(local_point)
	return true


func get_global_position() -> Vector2:
	return _last_global


func get_velocity() -> Vector2:
	return SoftLink.velocity_at(body, _last_global)


func get_asteroid() -> Asteroid:
	return body as Asteroid


# Nearest asteroid that now holds the anchor's cell, close to where the cell last was.
func _find_chunk_with_cell(tree: SceneTree) -> Asteroid:
	var best: Asteroid = null
	var best_distance := FOLLOW_DISTANCE

	for node in tree.get_nodes_in_group(Asteroid.GROUP):
		var candidate := node as Asteroid

		if candidate == null or not candidate.cells.has(cell):
			continue

		var distance := candidate.get_cell_global_position(cell).distance_to(_last_global)

		if distance < best_distance:
			best_distance = distance
			best = candidate

	return best
