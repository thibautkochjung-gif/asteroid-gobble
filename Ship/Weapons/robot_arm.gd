class_name RobotArm
extends Node2D

# Articulated arm (shoulder, elbow, wrist) shared by the arm weapons (drill, grabber).
# It only knows how to move: the weapon decides where to reach, and calls move() once per
# physics frame. This node sits on the weapon's origin, which is the shoulder.
#
# Pose: where the tip is (aim angle + tip distance from the shoulder) and which way the head points
# (head_angle). The wrist sits head_length behind the tip, along the head; two-bone inverse
# kinematics places the elbow (see _solve_elbow).
# The head normally points along the aim line. With max_wrist_bend_degrees above 0, it may tilt
# off it: that's how the tip reaches points close to the shoulder, or around an obstacle.
# Freedom: any pose, as long as the elbow, forearm and head stay clear of the ship's collision shapes.
# The elbow can bend to either side, but only switches side when the arm is straight, like a real arm.
# With prefer_outer_elbow, it keeps to the side away from the ship's centreline whenever it can.
# Angles are local to the shoulder: 0 = straight ahead.
#
# Hitbox: the links and the back of the head are collision shapes added to the ship's own body
# (shape owners). Asteroids bump into the arm like into the hull. They're moved once per physics
# frame, and only if the pose changed: moving a body's shapes makes the physics server redo work.
#
# Performance: move() remembers its last call. Same starting pose, same goal, same hull: the
# answer is the same, so it's reused instead of searched again. That's the usual case for an arm
# at rest, or a drill pressed against one spot.
#
# Expected children: UpperArm, Forearm (link sprites starting on their joint), ElbowJoint,
# WristJoint, Head (with a Muzzle marker at the tip), Base.

@export var max_reach: float = 72.0 # Shoulder to tip, px. About a third of the hull
@export var rest_tip_distance: float = 66.0 # Shoulder to tip when idle
@export var rest_outward_degrees: float = 20.0 # Idle aim, from straight ahead toward the outside
@export var min_wrist_distance: float = 4.0 # Closest the wrist gets to the shoulder (fully folded)
@export var swing_speed_degrees: float = 90.0 # Per second
@export var extend_speed: float = 60.0 # px/s, how fast the tip moves along the aim line
@export var max_wrist_bend_degrees: float = 0.0 # How far the head may tilt off the aim line. 0 = rigid wrist
@export var wrist_speed_degrees: float = 120.0 # Per second
@export var hull_clearance: float = 6.0 # Gap kept between the arm's centre line and the hull
@export var link_thickness: float = 10.0 # Hitbox width of the links
@export var flip_max_bend_degrees: float = 4.0 # The elbow may switch side only when bent less than this
@export var prefer_outer_elbow: bool = false # Keep the elbow on the outer side (away from the hangar mouth)
@export var head_hitbox: PackedVector2Array = PackedVector2Array() # In head space. Leave the business end out
@export var avoid_hull: bool = true # Refuse poses that overlap the ship's collision shapes (hull, doors)
@export var has_hitbox: bool = true # Add the arm's shapes to the ship's body, so asteroids bump into it

const WRIST_STEP_DEGREES: float = 10.0 # Tilts tested when looking for a head angle
const OUTER_ELBOW_MARGIN: float = 6.0 # px. The outer side must be clearly outer to switch to it
const FLIP_GIVE_UP_TIME: float = 2.0 # A switch that can't happen (can't straighten) is dropped after this

var angle: float = 0.0 # Current aim (shoulder to tip), local
var tip_distance: float = 0.0 # Current shoulder-to-tip distance
var head_angle: float = 0.0 # Current head direction, local
var speed_scale: float = 1.0 # Set by the weapon: a damaged arm moves slower. 0 = stuck

var _ship: RigidBody2D
var _elbow_sign: float = -1.0 # Which side the elbow bends to
var _flip_pending: bool = false # A blocked path needs the elbow on its other side
var _flip_time: float = 0.0 # How long the pending switch has been tried
var _side: float = -1.0 # Side of the hull the shoulder is on: -1 = left (negative y), +1 = right
var _outward_angle: float = -PI * 0.5 # Local. From the ship's centre through the shoulder: the swing never passes through the opposite direction
var _head_length: float = 0.0
var _upper_length: float = 0.0 # Read from the link sprites, so the art and the IK always agree
var _forearm_length: float = 0.0
var _hull_shapes: Array[Dictionary] = [] # { "node": CollisionShape2D, "polygon": inflated outline }
var _hull_polygons: Array[PackedVector2Array] = [] # Same outlines in this node's space, this frame
var _hitbox_owners: Array[int] = [] # Upper arm, forearm, head (if head_hitbox is set)
var _hitbox_pose := Vector4(NAN, NAN, NAN, NAN) # Pose the hitbox was last placed for (angle, head, tip, elbow side)
var _hull_key: Array = [] # Shape transforms (null = disabled) the outlines were built from
var _hull_version: int = 0 # Goes up when the hull outlines change (a door moved)
var _move_key: Array = [] # Last move()'s inputs, starting pose included
var _move_result: Array = [] # ...and the pose it ended on

@onready var upper_arm: Sprite2D = $UpperArm
@onready var forearm: Sprite2D = $Forearm
@onready var elbow_joint: Sprite2D = $ElbowJoint
@onready var wrist_joint: Sprite2D = $WristJoint
@onready var head: Node2D = $Head
@onready var muzzle: Marker2D = $Head/Muzzle


func _ready() -> void:
	_head_length = muzzle.position.x
	_upper_length = _get_link_length(upper_arm)
	_forearm_length = _get_link_length(forearm)
	angle = get_rest_angle()
	head_angle = angle
	tip_distance = rest_tip_distance
	_update_pose_nodes()


# Children process after their parent: by now the weapon has moved the arm for this frame.
func _physics_process(_delta: float) -> void:
	_apply_hitbox()


func _exit_tree() -> void:
	if is_instance_valid(_ship):
		for owner_id in _hitbox_owners:
			_ship.remove_shape_owner(owner_id)

	_hitbox_owners.clear()


# Called by the weapon once it knows its ship (after its own _ready).
func setup(ship: RigidBody2D) -> void:
	_ship = ship

	if _ship == null:
		return

	var shoulder := _ship.to_local(global_position)
	_side = 1.0 if shoulder.y > 0.0 else -1.0
	_elbow_sign = _side

	# Pointing straight at the ship's centre is the one direction the arm never swings through.
	# Straight sideways (the old rule) broke for shoulders far out on a wide hull: a goal just
	# behind "straight inward" sent the arm all the way round the back, over the hull.
	var away_from_ship := global_position - _ship.global_position
	_outward_angle = _side * PI * 0.5

	if shoulder.length() > 1.0:
		_outward_angle = global_transform.basis_xform_inv(away_from_ship).angle()
	angle = get_rest_angle()
	head_angle = angle
	_collect_hull_shapes()

	if has_hitbox:
		_create_hitbox()

	refresh_hull()

	var bend_sign := _find_elbow_sign(angle, tip_distance, head_angle)

	if bend_sign != 0.0:
		_elbow_sign = bend_sign

	_update_pose_nodes()
	_apply_hitbox()


# Call once per physics frame, before any can_reach() or move(): the hangar doors move.
# Rebuilds the outlines only if a shape moved or was switched on or off.
func refresh_hull() -> void:
	# No outlines = every pose counts as clear (the reach limits still apply).
	if _ship == null or not avoid_hull:
		if not _hull_polygons.is_empty():
			_hull_polygons.clear()
			_hull_version += 1

		return

	var key: Array = []

	for entry in _hull_shapes:
		var collision: CollisionShape2D = entry["node"]
		key.append(null if collision.disabled else collision.transform)

	if key == _hull_key:
		return

	_hull_key = key
	_hull_version += 1
	_hull_polygons.clear()

	# Through the parents, not the global transforms: exact, so it doesn't jitter as the ship flies
	var ship_to_arm := get_relative_transform_to_parent(_ship).affine_inverse()

	for i in _hull_shapes.size():
		if key[i] == null:
			continue

		var polygon: PackedVector2Array = _hull_shapes[i]["polygon"]
		_hull_polygons.append(ship_to_arm * (key[i] as Transform2D) * polygon)


# One step toward the goal pose: tip at goal_angle / goal_tip_distance. goal_head is the head
# direction wanted there (NAN = let the arm choose: in line with the aim if possible).
# Angles are interpolated around the outward direction (ship's centre to shoulder), so the arm always swings around the
# outside of the ship, never through it. A step that would hit the hull isn't taken: if the
# combined step (swing + wrist + reach) is blocked, simpler steps are tried in turn (see below),
# so the arm works its way around obstacles like the open hangar doors instead of freezing.
# The elbow can't jump to its other side: both elbow poses only meet when the arm is straight.
# So when the current side is blocked and the other isn't, the arm first straightens (head in line),
# switches side while straight (no visible jump), then carries on.
func move(delta: float, goal_angle: float, goal_tip_distance: float, wanted_head: float = NAN) -> void:
	delta *= speed_scale

	# NAN never equals itself: a stand-in keeps the key comparable
	var key: Array = [angle, head_angle, tip_distance, _elbow_sign, goal_angle, goal_tip_distance, 1.0e9 if is_nan(wanted_head) else wanted_head, delta, _hull_version]
	var can_reuse := not _flip_pending

	if can_reuse and key == _move_key:
		angle = _move_result[0]
		head_angle = _move_result[1]
		tip_distance = _move_result[2]
		_elbow_sign = _move_result[3]
		_flip_pending = _move_result[4]
		_flip_time = 0.0
		_update_pose_nodes()
		return

	_move_key = key if can_reuse else []
	_search_move(delta, goal_angle, goal_tip_distance, wanted_head)

	if not _move_key.is_empty():
		_move_result = [angle, head_angle, tip_distance, _elbow_sign, _flip_pending]


func _search_move(delta: float, goal_angle: float, goal_tip_distance: float, wanted_head: float) -> void:

	var goal_tip := clampf(goal_tip_distance, get_min_tip_distance(), _get_straight_tip_distance())
	var goal_head := _choose_head_angle(goal_angle, goal_tip, wanted_head)
	var wanted_sign := _elbow_sign

	if not is_nan(goal_head):
		var bend_sign := _find_elbow_sign(goal_angle, goal_tip, goal_head)

		if bend_sign != 0.0:
			wanted_sign = bend_sign
	else:
		goal_head = goal_angle

	if _flip_pending:
		_flip_time += delta

		if _flip_time > FLIP_GIVE_UP_TIME:
			_flip_pending = false
		else:
			wanted_sign = -_elbow_sign

	var outward_angle := _outward_angle
	var theta := wrapf(angle - outward_angle, -PI, PI)
	var goal_theta := wrapf(goal_angle - outward_angle, -PI, PI)
	var new_angle := outward_angle + move_toward(theta, goal_theta, deg_to_rad(swing_speed_degrees) * delta)

	if wanted_sign != _elbow_sign:
		goal_head = new_angle
		goal_tip = _get_straight_tip_distance()

	var new_head := _turn_head_toward(goal_head, new_angle, delta)
	var new_tip := clampf(move_toward(tip_distance, goal_tip, extend_speed * delta), get_min_tip_distance(), _get_straight_tip_distance())
	var swing_relaxed := _turn_head_toward(new_angle, new_angle, delta)
	var relaxed := _turn_head_toward(angle, angle, delta)

	# x = aim angle, y = head angle, z = tip distance. First clear one wins.
	var steps: Array[Vector3] = [
		Vector3(new_angle, new_head, new_tip), # Everything at once
		Vector3(new_angle, new_head, tip_distance), # Swing and turn the wrist, don't reach
		Vector3(new_angle, swing_relaxed, tip_distance), # Swing, wrist easing back in line
		Vector3(angle, new_head, new_tip), # Turn the wrist and reach, don't swing
		Vector3(angle, new_head, tip_distance), # Wrist only
		Vector3(angle, head_angle, new_tip), # Reach only
		Vector3(angle, relaxed, tip_distance), # Ease the wrist back in line: often gets out of a tight spot
	]

	# Already overlapping the hull (a hangar door swung into the arm, say): any move is allowed.
	var is_stuck := not _is_pose_clear(angle, tip_distance, head_angle, _elbow_sign)
	var has_moved := false

	for step in steps:
		if is_stuck or _is_pose_clear(step.x, step.z, step.y, _elbow_sign):
			has_moved = not step.is_equal_approx(Vector3(angle, head_angle, tip_distance))
			angle = step.x
			head_angle = step.y
			tip_distance = step.z
			break

	# Blocked: the arm wanted to move but nothing works on this side, while the full step would work
	# with the elbow on the other side. Remember to switch (straighten first), until it's done.
	# (Not moving because the goal is reached doesn't count: at rest, that would loop forever.)
	var wants_to_move := not Vector3(new_angle, new_head, new_tip).is_equal_approx(Vector3(angle, head_angle, tip_distance))
	var is_blocked := wants_to_move and not has_moved

	if is_blocked and not _flip_pending and wanted_sign == _elbow_sign and _is_pose_clear(new_angle, new_tip, new_head, -_elbow_sign):
		_flip_pending = true
		_flip_time = 0.0

	if wanted_sign != _elbow_sign and _is_straight() and _is_pose_clear(angle, tip_distance, head_angle, wanted_sign):
		_elbow_sign = wanted_sign
		_flip_pending = false

	_update_pose_nodes()


# Pulls the tip back to this distance if it's further (something is in the way).
# Meant for a rigid wrist (head on the aim line): moving back along that line can't hit the hull.
func limit_tip(distance: float) -> void:
	if distance >= tip_distance:
		return

	tip_distance = maxf(distance, get_min_tip_distance())
	_update_pose_nodes()


# True if the arm can put its tip there without touching the hull (some head angle, some elbow side).
func can_reach(local_angle: float, distance: float) -> bool:
	var tip := clampf(distance, get_min_tip_distance(), max_reach)
	return not is_nan(_choose_head_angle(local_angle, tip))


# True if the arm can put its tip there with the head pointing exactly at head (local angle):
# within max_reach, within the wrist's bend, with the wrist inside the links' reach and clear of the hull.
func can_hold(local_angle: float, distance: float, head: float) -> bool:
	if distance < get_min_tip_distance() or distance > max_reach:
		return false

	if absf(angle_difference(local_angle, head)) > deg_to_rad(max_wrist_bend_degrees) + 0.001:
		return false

	return _find_elbow_sign(local_angle, distance, head) != 0.0


# Tests aim directions all around the shoulder. Along each one, the first cell of a candidate
# asteroid counts if the arm can put its tip there without going through the hull.
# The nearest wins, with a penalty for turning far from the current aim, so the arm sticks to
# the spot it's working on instead of hopping between two equally close ones.
# Looking along real lines (instead of at each asteroid's closest point) finds any reachable part
# of an asteroid, even when its closest point is hidden behind the hull.
# Returns { "asteroid", "angle", "distance" }, or an empty dictionary.
func find_reachable(candidates: Array[Asteroid], search_length: float, directions: int, turn_cost: float) -> Dictionary:
	var best := {}
	var best_score := INF

	for i in directions:
		var scan_angle := TAU * i / directions
		var ray_end := global_position + get_global_direction(scan_angle) * search_length

		for asteroid in candidates:
			if not asteroid.may_cross(global_position, ray_end):
				continue

			var hits := asteroid.get_cells_on_ray(global_position, ray_end, 1)

			if hits.is_empty():
				continue

			var distance: float = hits[0]["distance"]
			var score := distance + absf(wrapf(scan_angle - angle, -PI, PI)) * turn_cost

			if score >= best_score or not can_reach(scan_angle, distance):
				continue

			best_score = score
			best = { "asteroid": asteroid, "angle": scan_angle, "distance": distance }

	return best


func get_rest_angle() -> float:
	return _side * deg_to_rad(rest_outward_degrees)


# Folded in the rest pose, wrist in line: the weapon can skip the arm's work until it needs it again.
func is_at_rest() -> bool:
	var is_folded := is_equal_approx(angle, get_rest_angle()) and is_equal_approx(tip_distance, rest_tip_distance)
	return is_folded and is_equal_approx(head_angle, angle) and not _flip_pending


# With a rigid wrist the head must fit between the shoulder and the tip. A bending wrist can
# fold the head back, so the tip can come much closer.
func get_min_tip_distance() -> float:
	if max_wrist_bend_degrees <= 0.0:
		return _head_length + min_wrist_distance

	return min_wrist_distance + 8.0


func get_direction() -> Vector2:
	return get_global_direction(angle)


func get_head_direction() -> Vector2:
	return get_global_direction(head_angle)


func get_global_direction(local_angle: float) -> Vector2:
	return global_transform.basis_xform(Vector2.from_angle(local_angle)).normalized()


func get_tip_position() -> Vector2:
	return global_position + get_direction() * tip_distance


func get_wrist_position() -> Vector2:
	return get_tip_position() - get_head_direction() * _head_length


# Where the wear marks go (DamageMarks), in global coordinates: the elbow and the wrist, so they follow the arm.
func get_damage_points() -> PackedVector2Array:
	return PackedVector2Array([elbow_joint.global_position, wrist_joint.global_position])


# Shortest distance from a global point to the arm: shoulder, elbow, wrist, tip.
func get_hit_distance(global_point: Vector2) -> float:
	var joints := PackedVector2Array([global_position, elbow_joint.global_position, wrist_joint.global_position, get_tip_position()])
	var best := INF

	for i in joints.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(global_point, joints[i], joints[i + 1])
		best = minf(best, closest.distance_to(global_point))

	return best


# --- Pose


# Head angle for a tip pose, within max_wrist_bend_degrees of the aim. Tries the wanted head
# angle first (or, if it's out of the wrist's range, the closest tilt the wrist allows), then
# tilts further and further from it. Without a wanted angle, starts in line with the aim.
# NAN if no tilt works.
func _choose_head_angle(tip_angle: float, tip: float, wanted_head: float = NAN) -> float:
	var max_tilt := deg_to_rad(max_wrist_bend_degrees)
	var preferred := 0.0

	if not is_nan(wanted_head):
		preferred = clampf(angle_difference(tip_angle, wanted_head), -max_tilt, max_tilt)

	var tilts: Array[float] = []
	var tilt := -max_tilt

	while tilt <= max_tilt + 0.001:
		tilts.append(tilt)
		tilt += deg_to_rad(WRIST_STEP_DEGREES)

	tilts.append(preferred)
	tilts.sort_custom(func(a: float, b: float) -> bool:
		return absf(a - preferred) < absf(b - preferred)
	)

	for candidate in tilts:
		if _find_elbow_sign(tip_angle, tip, tip_angle + candidate) != 0.0:
			return tip_angle + candidate

	return NAN


# Turns the head toward goal_head at wrist speed. With a rigid wrist, it simply follows the aim.
func _turn_head_toward(goal_head: float, new_angle: float, delta: float) -> float:
	if max_wrist_bend_degrees <= 0.0:
		return new_angle

	var max_turn := deg_to_rad(wrist_speed_degrees) * delta
	var turned := head_angle + clampf(angle_difference(head_angle, goal_head), -max_turn, max_turn)
	var max_tilt := deg_to_rad(max_wrist_bend_degrees)

	return new_angle + clampf(angle_difference(new_angle, turned), -max_tilt, max_tilt)


# The elbow side that keeps this pose clear of the hull. 0 = none.
# Current side first, unless prefer_outer_elbow and the other side is clearly further out.
func _find_elbow_sign(pose_angle: float, pose_tip: float, pose_head: float) -> float:
	var first := _elbow_sign

	if prefer_outer_elbow:
		var wrist := Vector2.from_angle(pose_angle) * pose_tip - Vector2.from_angle(pose_head) * _head_length
		var current_out := _solve_elbow(wrist, _elbow_sign).y * _side
		var other_out := _solve_elbow(wrist, -_elbow_sign).y * _side

		if other_out > current_out + OUTER_ELBOW_MARGIN:
			first = -_elbow_sign

	for bend_sign: float in [first, -first]:
		if _is_pose_clear(pose_angle, pose_tip, pose_head, bend_sign):
			return bend_sign

	return 0.0


# The wrist must be within the links' reach. Then the elbow, the forearm and the head's centre line
# are checked against the hull outlines (already inflated by hull_clearance). The upper arm isn't
# checked: it starts on the hull, at the shoulder, and with the elbow outside it can only cross the
# hull's edge.
func _is_pose_clear(pose_angle: float, pose_tip: float, pose_head: float, bend_sign: float) -> bool:
	var tip := Vector2.from_angle(pose_angle) * pose_tip
	var wrist := tip - Vector2.from_angle(pose_head) * _head_length
	var wrist_distance := wrist.length()

	if wrist_distance < min_wrist_distance - 0.01 or wrist_distance > _upper_length + _forearm_length:
		return false

	var elbow := _solve_elbow(wrist, bend_sign)
	var polyline := PackedVector2Array([elbow, wrist, tip])

	for polygon in _hull_polygons:
		if not Geometry2D.intersect_polyline_with_polygon(polyline, polygon).is_empty():
			return false

	return true


func _get_wrist_local() -> Vector2:
	return Vector2.from_angle(angle) * tip_distance - Vector2.from_angle(head_angle) * _head_length


func _is_straight() -> bool:
	return _get_bend(_get_wrist_local().length()) <= deg_to_rad(flip_max_bend_degrees)


# Fully stretched, head in line. Only used to switch the elbow's side: max_reach keeps the arm
# bent otherwise.
func _get_straight_tip_distance() -> float:
	return _head_length + _upper_length + _forearm_length - 0.05


# A link sprite starts on its joint and is exactly one link long.
func _get_link_length(link: Sprite2D) -> float:
	return link.texture.get_width() * link.scale.x


# Two-bone IK. The shoulder, elbow and wrist make a triangle whose three sides we know:
# the two link lengths and the shoulder-wrist distance. The law of cosines gives the angle
# between the shoulder-wrist line and the upper arm; bend_sign says to which side it's turned.
func _solve_elbow(wrist: Vector2, bend_sign: float) -> Vector2:
	var bend := _get_bend(wrist.length())
	return Vector2.from_angle(wrist.angle() + bend * bend_sign) * _upper_length


# Angle between the shoulder-wrist line and the upper arm, for a given shoulder-wrist distance.
# 0 = arm straight.
func _get_bend(wrist_distance: float) -> float:
	var min_reach := absf(_upper_length - _forearm_length) + 0.01
	var max_reach_links := _upper_length + _forearm_length - 0.01
	var reach := clampf(wrist_distance, min_reach, max_reach_links)
	var a := _upper_length
	var b := _forearm_length
	var cos_bend := (a * a + reach * reach - b * b) / (2.0 * a * reach)

	return acos(clampf(cos_bend, -1.0, 1.0))


# Sprites follow the current pose. The hitbox follows in _apply_hitbox(), once per physics frame.
func _update_pose_nodes() -> void:
	var wrist := _get_wrist_local()
	var elbow := _solve_elbow(wrist, _elbow_sign)

	upper_arm.rotation = elbow.angle()
	forearm.position = elbow
	forearm.rotation = (wrist - elbow).angle()
	elbow_joint.position = elbow
	wrist_joint.position = wrist
	head.position = wrist
	head.rotation = head_angle


func _apply_hitbox() -> void:
	var pose := Vector4(angle, head_angle, tip_distance, _elbow_sign)

	if pose == _hitbox_pose:
		return

	_hitbox_pose = pose
	var wrist := _get_wrist_local()
	_update_hitbox(_solve_elbow(wrist, _elbow_sign), wrist)


# --- Hull and hitbox


# Outlines of the ship's own collision shapes, inflated so the arm keeps some clearance.
# Shapes are kept (not baked) because the hangar doors move: positions are read every frame.
func _collect_hull_shapes() -> void:
	for child in _ship.get_children():
		var collision := child as CollisionShape2D

		if collision == null or collision.shape == null:
			continue

		var outline := _get_shape_outline(collision.shape)

		if outline.is_empty():
			continue

		var inflated := Geometry2D.offset_polygon(outline, hull_clearance)

		if not inflated.is_empty():
			_hull_shapes.append({ "node": collision, "polygon": inflated[0] })


# Only the shape types the hull uses today. Others are ignored (the arm could pass through them).
func _get_shape_outline(shape: Shape2D) -> PackedVector2Array:
	if shape is ConvexPolygonShape2D:
		return (shape as ConvexPolygonShape2D).points

	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5
		return PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])

	return PackedVector2Array()


# Shape owners on the ship's body: the links are rectangles centred between their joints,
# the head uses head_hitbox (set per weapon in its scene).
func _create_hitbox() -> void:
	var upper_shape := RectangleShape2D.new()
	upper_shape.size = Vector2(_upper_length, link_thickness)

	var forearm_shape := RectangleShape2D.new()
	forearm_shape.size = Vector2(_forearm_length, link_thickness)

	var shapes: Array[Shape2D] = [upper_shape, forearm_shape]

	if head_hitbox.size() >= 3:
		var head_shape := ConvexPolygonShape2D.new()
		head_shape.points = head_hitbox
		shapes.append(head_shape)

	for shape in shapes:
		var owner_id := _ship.create_shape_owner(self)
		_ship.shape_owner_add_shape(owner_id, shape)
		_hitbox_owners.append(owner_id)


func _update_hitbox(elbow: Vector2, wrist: Vector2) -> void:
	if _hitbox_owners.is_empty():
		return

	var arm_to_ship := get_relative_transform_to_parent(_ship)
	var upper := Transform2D(elbow.angle(), elbow * 0.5)
	var lower := Transform2D((wrist - elbow).angle(), (elbow + wrist) * 0.5)
	var head_transform := Transform2D(head_angle, wrist)

	_ship.shape_owner_set_transform(_hitbox_owners[0], arm_to_ship * upper)
	_ship.shape_owner_set_transform(_hitbox_owners[1], arm_to_ship * lower)

	if _hitbox_owners.size() > 2:
		_ship.shape_owner_set_transform(_hitbox_owners[2], arm_to_ship * head_transform)
