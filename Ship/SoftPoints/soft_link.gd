class_name SoftLink
extends RefCounted

# Spring links between two bodies (harpoon cable, clamp pads), and the helpers they share.
# Forces are accelerations times the pair's reduced mass, m1 m2 / (m1 + m2). So a link behaves the
# same between the ship and a tiny chunk as between two big rocks, and stays stable whatever the
# masses. A stiffness in force per px would be fine on a big rock and explode on a 3-cell chunk.
# A frozen body (welded to the ship, held by a buoy) can't be pushed: it counts as infinitely heavy.


# Velocity of a body's material at a global point: linear + the part due to its spin.
static func velocity_at(body: RigidBody2D, global_point: Vector2) -> Vector2:
	var asteroid := body as Asteroid

	if asteroid != null:
		return asteroid.get_velocity_at(global_point)

	var center := body.global_position

	if body.center_of_mass_mode == RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM:
		center = body.to_global(body.center_of_mass)

	var offset := global_point - center
	return body.linear_velocity + Vector2(-body.angular_velocity * offset.y, body.angular_velocity * offset.x)


static func reduced_mass(body_a: RigidBody2D, body_b: RigidBody2D) -> float:
	if body_a.freeze:
		return body_b.mass

	if body_b.freeze:
		return body_a.mass

	return body_a.mass * body_b.mass / (body_a.mass + body_b.mass)


# Godot wants the force's point as an offset from the body's origin, in global orientation.
static func apply_at(body: RigidBody2D, force: Vector2, global_point: Vector2) -> void:
	if body.freeze:
		return

	body.apply_force(force, global_point - body.global_position)


# Pulls point_b (on body_b) toward point_a (on body_a) until they are rest_length apart.
# is_rope: only pulls, never pushes, and only damps along the line (a slack cable does nothing).
# Otherwise it's a rod: it holds the distance both ways and damps all relative motion, which also
# stops the two points from sliding sideways. With rest_length 0 it pins the points together.
# stiffness in 1/s², damping in 1/s. Returns the force's magnitude (mass * px/s²), for limits.
static func apply_spring(body_a: RigidBody2D, point_a: Vector2, body_b: RigidBody2D, point_b: Vector2, rest_length: float, stiffness: float, damping: float, is_rope: bool) -> float:
	var delta := point_b - point_a
	var distance := delta.length()
	var direction := delta / distance if distance > 0.001 else Vector2.ZERO
	var stretch := distance - rest_length

	if is_rope and stretch <= 0.0:
		return 0.0

	var relative_velocity := velocity_at(body_b, point_b) - velocity_at(body_a, point_a)
	var acceleration: Vector2

	if is_rope:
		var closing := maxf(stiffness * stretch + damping * relative_velocity.dot(direction), 0.0)
		acceleration = direction * closing
	else:
		acceleration = direction * stiffness * stretch + relative_velocity * damping

	var force := acceleration * reduced_mass(body_a, body_b)
	apply_at(body_a, force, point_a)
	apply_at(body_b, -force, point_b)
	return force.length()


# Distance from a point to a segment, and where along the segment (0..1) the nearest point is.
# Returns Vector2(distance, t).
static func distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> Vector2:
	var segment := to - from
	var length_squared := segment.length_squared()

	if length_squared <= 0.0:
		return Vector2(point.distance_to(from), 0.0)

	var t := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return Vector2(point.distance_to(from + segment * t), t)
