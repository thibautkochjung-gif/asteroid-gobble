class_name NetBundle
extends RigidBody2D

# Rocks caught in a net, closed: one solid body. Same trick as the rock bolter, for the same
# reason (joints between bodies are springy and jitter):
# - every rock moves under this body (reparent), frozen, its collisions off, out of the asteroid
#   group so the tools leave it alone. Godot writes a frozen body's physics position back onto it,
#   so _pin_rocks() puts each rock back on its spot every frame;
# - the rocks' collision rectangles are copied onto this body, with the rock as the shape owner:
#   whatever hits a rock hits the bundle. A demolition charge reads the owner and sticks to the
#   rock itself (DemolitionCharge._get_touched_rocks), so a bundled rock can still be blasted.
#   Its chunks go to space (Asteroid.space_parent) and the shapes are copied again;
# - the mass is the rocks' mass. Godot finds the centre of mass and the inertia from the shapes
#   (by area: every cell weighs the same, so that's right).
# The only way in or out of the hold: release_all() opens the net and the rocks drift free.
# The net is drawn over the rocks: a rope around their outline, a mesh across it. When it has just
# closed, the rope is drawn going from the open net's shape (the line it flew as) to the outline
# over close_time, and the mesh fades in: the body itself is solid from the first frame.

const MESH_SPACING: float = 12.0 # px between the net's strands
const NET_MARGIN: float = 3.0 # px between the rocks' outline and the rope around them
const CLOSING_POINTS: int = 48 # Points along the rope while it wraps around the rocks

@export var rope_color: Color = Color(0.83, 0.64, 0.16)
@export var mesh_color: Color = Color(0.83, 0.64, 0.16, 0.6)
@export var release_speed: float = 6.0 # px/s, rocks drift apart this fast when let go
@export var close_time: float = 0.7 # s for the drawn net to wrap around the rocks

var rocks: Array[Asteroid] = []

var _rock_transforms: Dictionary[Asteroid, Transform2D] = {} # Each rock's spot, in this body's space
var _owners: Dictionary[Asteroid, Array] = {} # Shape owners on this body, per rock
var _outline := PackedVector2Array() # The rope around the rocks, local
var _mesh: Array[PackedVector2Array] = [] # Strands across the outline, local
var _open_shape := PackedVector2Array() # The net as it flew, flattened into a loop, local. Empty: no closing to show
var _open_shift: float = 0.0 # Where along _open_shape the rope's first point starts, 0..1
var _close_age: float = 0.0


# Builds a bundle around these rocks, at their common centre of mass, keeping their total
# momentum (a perfectly inelastic catch, like the hangar's).
# open_edge: the net's rope as it flew, in global coordinates, for the closing animation.
static func wrap(caught: Array[Asteroid], space: Node2D, open_edge := PackedVector2Array()) -> NetBundle:
	var bundle := NetBundle.new()
	var total_mass := 0.0
	var center := Vector2.ZERO
	var momentum := Vector2.ZERO
	var spin := 0.0

	for rock in caught:
		total_mass += rock.mass
		center += rock.get_global_center() * rock.mass
		momentum += rock.linear_velocity * rock.mass
		spin += rock.angular_velocity * rock.mass

	center /= total_mass
	bundle.gravity_scale = 0.0
	bundle.can_sleep = false
	bundle.mass = total_mass
	space.add_child(bundle)
	bundle.global_position = center
	bundle.linear_velocity = momentum / total_mass
	bundle.angular_velocity = spin / total_mass * 0.5 # The net tangles them: some of the spin goes

	for rock in caught:
		bundle._weld(rock)

	bundle._rebuild_net()
	bundle._set_open_shape(open_edge)
	return bundle


func _process(delta: float) -> void:
	if _close_age < close_time:
		_close_age += delta
		queue_redraw()


func _physics_process(_delta: float) -> void:
	_pin_rocks()


# Radius of a circle around the body's origin that holds the net. For the prompts drawn above it.
func get_radius() -> float:
	var radius := 0.0

	for point in _outline:
		radius = maxf(radius, point.length())

	return radius


# Opens the net: every rock goes back to space with the bundle's motion at its spot, drifting
# away from the bundle's centre a little. The bundle goes away.
func release_all() -> void:
	var space := get_parent()

	for rock in rocks:
		if not is_instance_valid(rock):
			continue

		var center := rock.get_global_center()
		var away := (center - global_position).normalized()
		var velocity := SoftLink.velocity_at(self, center) + away * release_speed

		if rock.shapes_rebuilt.is_connected(_on_rock_shapes_rebuilt):
			rock.shapes_rebuilt.disconnect(_on_rock_shapes_rebuilt)

		rock.reparent(space, true)
		rock.space_parent = null
		rock.collision_layer = rock.get_meta(&"net_layer", 1)
		rock.collision_mask = rock.get_meta(&"net_mask", 1)
		rock.freeze = false
		rock.show_behind_parent = false
		rock.add_to_group(Asteroid.GROUP)
		rock.linear_velocity = velocity
		rock.angular_velocity = angular_velocity

	rocks.clear()
	queue_free()


func get_cell_count() -> int:
	var total := 0

	for rock in rocks:
		if is_instance_valid(rock):
			total += rock.cells.size()

	return total


func _weld(rock: Asteroid) -> void:
	rock.set_meta(&"net_layer", rock.collision_layer)
	rock.set_meta(&"net_mask", rock.collision_mask)
	rock.remove_from_group(Asteroid.GROUP)
	rock.was_cut = true # The field must not free it with its sector: it's ours now
	rock.space_parent = get_parent()
	rock.collision_layer = 0
	rock.collision_mask = 0
	rock.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	rock.freeze = true
	rock.show_behind_parent = true # The net is drawn by this body: over the rocks
	rock.reparent(self, true)
	rocks.append(rock)
	_rock_transforms[rock] = rock.transform
	rock.shapes_rebuilt.connect(_on_rock_shapes_rebuilt.bind(rock))
	_copy_shapes(rock)


func _copy_shapes(rock: Asteroid) -> void:
	for owner_id in _owners.get(rock, []):
		remove_shape_owner(owner_id)

	var owners: Array[int] = []
	var placement := _rock_transforms[rock]

	for rect in rock.get_collision_rects():
		var owner_id := create_shape_owner(rock)
		var rect_center := (Vector2(rect.position) + Vector2(rect.size) * 0.5) * rock.cell_size
		shape_owner_set_transform(owner_id, placement * Transform2D(0.0, rect_center))
		shape_owner_add_shape(owner_id, rock.get_rect_shape(rect.size))
		owners.append(owner_id)

	_owners[rock] = owners


func _pin_rocks() -> void:
	var lost := false

	for rock in rocks:
		if not is_instance_valid(rock) or rock.cells.is_empty():
			lost = true
			continue

		rock.transform = _rock_transforms[rock]

	if lost:
		_forget_lost_rocks()


func _forget_lost_rocks() -> void:
	var kept: Array[Asteroid] = []

	for rock in rocks:
		if is_instance_valid(rock) and not rock.cells.is_empty():
			kept.append(rock)
			continue

		for owner_id in _owners.get(rock, []):
			remove_shape_owner(owner_id)

		_owners.erase(rock)
		_rock_transforms.erase(rock)

	rocks = kept

	if rocks.is_empty():
		queue_free()
		return

	_update_mass()
	_rebuild_net()


# A rock was cut while in the net (a charge): copy its shapes again.
func _on_rock_shapes_rebuilt(rock: Asteroid) -> void:
	if not rocks.has(rock):
		return

	_copy_shapes(rock)
	_update_mass()
	_rebuild_net()


func _update_mass() -> void:
	var total := 0.0

	for rock in rocks:
		if is_instance_valid(rock):
			total += rock.cells.size() * rock.mass_per_cell

	mass = maxf(total, 0.01)


# --- Look


# The convex outline of every rock's rectangles, a little wider, and strands across it in two
# diagonal directions.
func _rebuild_net() -> void:
	var corners := PackedVector2Array()

	for rock in rocks:
		if not is_instance_valid(rock):
			continue

		var placement := _rock_transforms[rock]

		for rect in rock.get_collision_rects():
			var area := Rect2(Vector2(rect.position) * rock.cell_size, Vector2(rect.size) * rock.cell_size)
			corners.append(placement * area.position)
			corners.append(placement * Vector2(area.end.x, area.position.y))
			corners.append(placement * area.end)
			corners.append(placement * Vector2(area.position.x, area.end.y))

	_outline = PackedVector2Array()
	_mesh.clear()

	if corners.size() < 3:
		queue_redraw()
		return

	var hull := Geometry2D.convex_hull(corners)
	var grown := Geometry2D.offset_polygon(hull, NET_MARGIN)
	_outline = grown[0] if not grown.is_empty() else hull

	var bounds := Rect2(_outline[0], Vector2.ZERO)

	for point in _outline:
		bounds = bounds.expand(point)

	var reach := bounds.size.length()
	var middle := bounds.get_center()

	for direction in [Vector2(1.0, 1.0).normalized(), Vector2(1.0, -1.0).normalized()]:
		var across: Vector2 = direction.orthogonal()
		var offset := -reach * 0.5

		while offset <= reach * 0.5:
			var strand := PackedVector2Array([middle + across * offset - direction * reach, middle + across * offset + direction * reach])

			for piece in Geometry2D.intersect_polyline_with_polygon(strand, _outline):
				_mesh.append(piece)

			offset += MESH_SPACING

	queue_redraw()


func _draw() -> void:
	if _outline.size() < 3:
		return

	var progress := clampf(_close_age / close_time, 0.0, 1.0) if close_time > 0.0 else 1.0
	var mesh := mesh_color
	mesh.a *= smoothstep(0.45, 1.0, progress)

	if mesh.a > 0.0:
		for strand in _mesh:
			draw_polyline(strand, mesh, 1.0)

	var rope := _outline if progress >= 1.0 or _open_shape.is_empty() else _get_closing_rope(progress)
	var closed := rope.duplicate()
	closed.append(rope[0])
	draw_polyline(closed, Color(0.06, 0.055, 0.07), 3.0)
	draw_polyline(closed, rope_color, 1.5)


# The rope part way between the open net and the outline. Fast at first, settling at the end.
func _get_closing_rope(progress: float) -> PackedVector2Array:
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	var rope := PackedVector2Array()

	for i in CLOSING_POINTS:
		var t := float(i) / CLOSING_POINTS
		rope.append(_sample_loop(_open_shape, t + _open_shift).lerp(_sample_loop(_outline, t), eased))

	return rope


# The open net's rope, there and back again (a flat loop), run the way round and from the start
# point that line up best with the outline, so the rope doesn't twist as it wraps.
func _set_open_shape(open_edge: PackedVector2Array) -> void:
	_open_shape = PackedVector2Array()
	_close_age = close_time

	if open_edge.size() < 2 or _outline.size() < 3:
		return

	var loop := PackedVector2Array()

	for point in open_edge:
		loop.append(to_local(point))

	for i in range(open_edge.size() - 2, 0, -1):
		loop.append(to_local(open_edge[i]))

	var best_cost := INF
	var best := loop
	var best_shift := 0.0
	var outline_points := PackedVector2Array()

	for i in CLOSING_POINTS:
		outline_points.append(_sample_loop(_outline, float(i) / CLOSING_POINTS))

	for reverse in [false, true]:
		var turned := loop.duplicate()

		if reverse:
			turned.reverse()

		for step in 16:
			var shift := step / 16.0
			var cost := 0.0

			for i in CLOSING_POINTS:
				cost += _sample_loop(turned, float(i) / CLOSING_POINTS + shift).distance_squared_to(outline_points[i])

			if cost < best_cost:
				best_cost = cost
				best = turned
				best_shift = shift

	_open_shape = best
	_open_shift = best_shift
	_close_age = 0.0
	queue_redraw()


# The point at share t (0..1) of a closed loop's length.
static func _sample_loop(loop: PackedVector2Array, t: float) -> Vector2:
	var total := 0.0

	for i in loop.size():
		total += loop[i].distance_to(loop[(i + 1) % loop.size()])

	var target := fposmod(t, 1.0) * total

	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var length := a.distance_to(b)

		if target <= length and length > 0.0:
			return a.lerp(b, target / length)

		target -= length

	return loop[0]
