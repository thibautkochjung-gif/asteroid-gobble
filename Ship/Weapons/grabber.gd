class_name Grabber
extends HardpointWeapon

# Claw on an articulated arm (see RobotArm for how the arm moves).
# The fire button turns it on or off.
# While on, it reaches for the nearest reachable small chunk (at most max_chunk_cells cells),
# grabs it and deposits it at the hangar mouth: the wrist turns the claw to point into the hangar,
# brings the chunk just outside the door line, and lets go with a gentle push inward.
# Two stages, so the claw doesn't sweep through the doors on the way: it carries the chunk with
# the claw in line with the arm to a staging point just in front of the mouth, turning the claw
# toward the hangar over the last stretch, then moves straight in along the hangar's axis.
# It only goes in and lets go when the hangar doors are fully open: until then it waits at the
# staging point, chunk in claw. The elbow stays on the outer side (RobotArm.prefer_outer_elbow), so the arm is
# never between the chunk and the hangar.
# The wrist bends (see RobotArm.max_wrist_bend_degrees), so the claw can come around to chunks close
# to the hull, and turn to face the hangar from a side hardpoint.
#
# The grabber's arm has no hitbox and doesn't avoid the hull (see grabber.tscn, Arm node): it can't
# get stuck on the hangar doors. While a chunk is targeted, the ship's body also ignores collisions
# with it, so the hull doesn't knock it away just before the claw closes.
#
# Release point: picked among points on arcs in front of the mouth, inside the funnel the open
# doors form, so a chunk thrown from there toward the mouth can't hit a door leaf. The arm takes
# whichever it can reach (an open door leaf can block some of them), closest to the chunk.
#
# A carried chunk is frozen (kinematic) with its collisions off: it follows the claw exactly and
# can't bump into the hull on the way. It also leaves the asteroid group, so lasers, drills and the
# hangar ignore it until it's thrown.

enum State { SEEKING, CARRYING, COOLDOWN }

@export_group("Targeting")
@export var max_chunk_cells: int = 15 # Bigger asteroids are the drill's job
@export var search_margin: float = 40.0 # Also targets chunks this far beyond the arm's reach
@export var retarget_interval: float = 0.1 # Chunks drift: rescan often
@export var scan_directions: int = 72 # Aim directions tested around the shoulder (72 = every 5°)
@export var turn_cost: float = 8.0 # px of extra distance per radian of turning, when comparing chunks

@export_group("Grab")
@export var grip_point: Vector2 = Vector2(22.0, 0.0) # Claw space (from the wrist): between the jaws' tips
@export var grab_radius: float = 4.0 # The chunk's surface must come this close to the grip point
@export var snap_time: float = 0.12 # How long the chunk takes to settle between the jaws

@export_group("Deposit")
@export var deposit_gap: float = 6.0 # Chunk centre this far outside the door line when let go
@export var wait_distance: float = 8.0 # Staging point: this much further out than the deposit point
@export var staging_tolerance: float = 6.0 # How close to the staging point counts as there
@export var head_turn_distance: float = 30.0 # The claw turns toward the hangar within this distance of its goal
@export var release_tolerance: float = 4.0 # How close the chunk must get to the deposit point
@export var head_tolerance_degrees: float = 15.0 # How well the claw must face the hangar to let go
@export var aim_depth: float = 10.0 # The push aims this far inside the door line
@export var throw_speed: float = 25.0 # px/s into the hangar, relative to the ship
@export var cooldown_time: float = 0.4 # Pause after a throw
@export var ignore_time: float = 2.0 # A released chunk can't be grabbed again for this long

var is_running: bool = false
var state: State = State.SEEKING
var target: Asteroid
var carried: Asteroid

var _retarget_timer: float = 0.0
var _cooldown: float = 0.0
var _grip: Transform2D # The carried chunk's transform, in claw space, once settled
var _grip_start: Transform2D # Same, at the moment of the grab
var _snap_progress: float = 0.0
var _last_head_angle: float = 0.0
var _is_staged: bool = false # Reached the staging point with this chunk
var _carried_layer: int = 0
var _carried_mask: int = 0
var _ignored: Dictionary[int, float] = {} # Chunk instance id -> seconds left

@onready var arm: RobotArm = $Arm
@onready var claw_sprite: Sprite2D = $Arm/Head/Sprite # Frame 0 open, 1 closed


func _ready() -> void:
	arm.setup(ship)


func get_cooldown_ratio() -> float:
	if cooldown_time <= 0.0:
		return 0.0

	return clampf(_cooldown / cooldown_time, 0.0, 1.0)


func get_hit_distance(global_point: Vector2) -> float:
	return arm.get_hit_distance(global_point)


func get_damage_points() -> PackedVector2Array:
	return arm.get_damage_points()


# Swapped out while carrying: let go, or the chunk would stay frozen without collisions forever.
func _exit_tree() -> void:
	if is_instance_valid(carried):
		_release(carried.linear_velocity)

	_set_target(null)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		is_running = not is_running


func _physics_process(delta: float) -> void:
	arm.speed_scale = get_performance() # Damaged: the arm moves slower. Broken: it's stuck
	arm.refresh_hull()
	_tick_ignored(delta)

	match state:
		State.SEEKING:
			_seek(delta)
		State.CARRYING:
			_carry(delta)
		State.COOLDOWN:
			_cooldown -= delta
			_rest(delta)

			if _cooldown <= 0.0:
				state = State.SEEKING

	claw_sprite.frame = 1 if state == State.CARRYING else 0


# --- Seeking


func _seek(delta: float) -> void:
	if not is_running or hangar == null:
		_set_target(null)
		_rest(delta)
		return

	_update_target(delta)

	if not is_instance_valid(target):
		_rest(delta)
		return

	# Chunks drift: aim at where the target's nearest point is now, not where the scan saw it.
	# The tip goes a little past that point, so the grip point (between the jaws, behind the tip)
	# lands on the chunk's edge: the jaws close around it.
	var nearest := to_local(target.get_closest_point(global_position))
	var reach_in := arm.muzzle.position.x - grip_point.x
	arm.move(delta, nearest.angle(), nearest.length() + reach_in)

	if _is_in_jaws(target):
		_grab(target)


# The chunk's surface is right at the grip point, between the jaws.
func _is_in_jaws(chunk: Asteroid) -> bool:
	var grip := arm.head.to_global(grip_point)
	return chunk.get_closest_point(grip).distance_to(grip) <= grab_radius


# Keeps the ship's collision exception on the current target only.
func _set_target(new_target: Asteroid) -> void:
	if new_target == target:
		return

	if is_instance_valid(target) and target != carried and ship != null:
		ship.remove_collision_exception_with(target)

	target = new_target

	if is_instance_valid(target) and ship != null:
		ship.add_collision_exception_with(target)


func _update_target(delta: float) -> void:
	_retarget_timer -= delta

	if _retarget_timer > 0.0 and is_instance_valid(target):
		return

	_retarget_timer = retarget_interval

	var search_length := arm.max_reach + search_margin
	var candidates: Array[Asteroid] = []

	for asteroid in Asteroid.find_near(get_tree(), global_position, search_length):
		if _is_grabbable(asteroid, search_length):
			candidates.append(asteroid)

	var found := arm.find_reachable(candidates, search_length, scan_directions, turn_cost)

	if found.is_empty():
		_set_target(null)
	else:
		_set_target(found["asteroid"])


# Small, not just thrown, not already in the hangar's intake, and close enough.
func _is_grabbable(asteroid: Asteroid, search_length: float) -> bool:
	if asteroid.cells.is_empty() or asteroid.cells.size() > max_chunk_cells:
		return false

	if asteroid.freeze: # Welded to the ship (RockBolter), or already held
		return false

	if _ignored.has(asteroid.get_instance_id()):
		return false

	if hangar.intake.overlaps_body(asteroid):
		return false

	return global_position.distance_to(asteroid.get_closest_point(global_position)) <= search_length


# --- Carrying


func _grab(chunk: Asteroid) -> void:
	carried = chunk
	target = null # The collision exception stays until the chunk is released

	carried.remove_from_group(Asteroid.GROUP)
	_carried_layer = carried.collision_layer
	_carried_mask = carried.collision_mask
	carried.collision_layer = 0
	carried.collision_mask = 0
	carried.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	carried.freeze = true

	# The chunk eases in until its edge sits exactly on the grip point (see _hold).
	var claw_inverse := arm.head.global_transform.affine_inverse()
	var grip := arm.head.to_global(grip_point)
	var settled := carried.global_transform.translated(grip - carried.get_closest_point(grip))

	_grip_start = claw_inverse * carried.global_transform
	_grip = claw_inverse * settled
	_snap_progress = 0.0
	_is_staged = false
	state = State.CARRYING


# Staging point first, then (doors fully open) the deposit point, claw facing into the hangar.
# The chunk sits ahead of the claw's tip, so the tip stops that much short of its goal.
# If the arm can't get to the deposit point exactly, it lets go once it has got as close as it can.
func _carry(delta: float) -> void:
	if not is_instance_valid(carried):
		carried = null
		state = State.SEEKING
		return

	if not is_running:
		_release(get_ship_velocity_at(carried.get_global_center()))
		return

	var doors_open := hangar.open_amount >= 1.0
	var center := carried.get_global_center()
	var staging_point := hangar.to_global(Vector2(hangar.door_line_x + deposit_gap + wait_distance, 0.0))
	var deposit_point := hangar.to_global(Vector2(hangar.door_line_x + deposit_gap, 0.0))
	var inside_point := hangar.to_global(Vector2(hangar.door_line_x - aim_depth, 0.0))

	if center.distance_to(staging_point) <= staging_tolerance:
		_is_staged = true

	var is_going_in := _is_staged and doors_open
	var goal_point := deposit_point if is_going_in else staging_point
	var local_goal := to_local(goal_point)
	var into_hangar := (to_local(inside_point) - local_goal).normalized()

	# In line with the arm while travelling; facing the hangar over the last stretch.
	var wanted_head := NAN

	if center.distance_to(goal_point) <= head_turn_distance or is_going_in:
		wanted_head = into_hangar.angle()

	var center_in_claw := arm.head.global_transform.affine_inverse() * center
	var ahead_of_tip := center_in_claw.x - arm.muzzle.position.x
	var goal_tip := local_goal - into_hangar * ahead_of_tip

	arm.move(delta, goal_tip.angle(), goal_tip.length(), wanted_head)
	_hold(delta)

	# Settled: tip at its goal and the wrist done turning. The arm is as close as it can get,
	# even if the goal itself is out of reach.
	var head_turn := absf(angle_difference(_last_head_angle, arm.head_angle))
	var is_tip_there := absf(angle_difference(arm.angle, goal_tip.angle())) < 0.03 and absf(arm.tip_distance - goal_tip.length()) < 1.0
	var is_settled := is_tip_there and head_turn < 0.002
	_last_head_angle = arm.head_angle

	if not is_going_in:
		if is_settled:
			_is_staged = true

		return

	# On the point and facing the hangar, or settled as close as the arm gets.
	var is_on_point := carried.get_global_center().distance_to(deposit_point) <= release_tolerance
	var is_facing := absf(angle_difference(arm.head_angle, wanted_head)) <= deg_to_rad(head_tolerance_degrees)

	if is_on_point and is_facing or is_settled:
		_throw()


func _hold(delta: float) -> void:
	_snap_progress = minf(_snap_progress + delta / snap_time, 1.0)
	var grip := _grip_start.interpolate_with(_grip, _snap_progress)
	carried.global_transform = arm.head.global_transform * grip


# A gentle push toward the mouth's centre, a bit inside the door line.
func _throw() -> void:
	var center := carried.get_global_center()
	var aim_point := hangar.to_global(Vector2(hangar.door_line_x - aim_depth, 0.0))
	var direction := (aim_point - center).normalized()

	_release(get_ship_velocity_at(center) + direction * throw_speed)


# Back to a normal, free-flying chunk.
func _release(velocity: Vector2) -> void:
	carried.freeze = false
	carried.collision_layer = _carried_layer
	carried.collision_mask = _carried_mask
	carried.add_to_group(Asteroid.GROUP)
	carried.linear_velocity = velocity
	carried.angular_velocity = ship.angular_velocity if ship != null else 0.0

	if ship != null:
		ship.remove_collision_exception_with(carried)

	_ignored[carried.get_instance_id()] = ignore_time
	carried = null
	_cooldown = cooldown_time
	state = State.COOLDOWN


# --- Misc


func _rest(delta: float) -> void:
	arm.move(delta, arm.get_rest_angle(), arm.rest_tip_distance)


func _tick_ignored(delta: float) -> void:
	for id in _ignored.keys():
		_ignored[id] -= delta

		if _ignored[id] <= 0.0:
			_ignored.erase(id)
