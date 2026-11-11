class_name ShipComputer
extends Node

# Flight computer. Fires the ship's own thrusters to reach a velocity: it never sets a velocity
# directly, so it burns fuel, loses power with damaged thrusters and has to deal with the ship's
# off-balance like the player does. What it can do comes from `module` (a ComputerModule).
#
# - Kill momentum (X): speed and spin to zero, then the order ends.
# - Match velocity (F, mouse over a rock or the mothership): the ship's speed to the target's speed.
#   Spin is neither matched nor added. The order keeps the match until the player takes over or the
#   target is gone.
# - Settling, always on: a speed or a spin that is almost zero is brought to zero.
#
# The player always wins: any movement input ends the order, and the computer stays quiet while
# the input lasts. ShipMovement calls steer() every physics frame, after reading the player and
# before the fuel limit, so the computer's burns are paid for like any other.
#
# Picking the thrusters: at full strength, each thruster gives the ship a push (linear
# acceleration) and a turn (spin acceleration). Both depend on where it sits relative to the centre
# of mass, which moves as the hold fills. The computer looks for the strengths (0..1) whose sum
# comes closest to the acceleration it wants, adjusting one thruster at a time, a few passes per
# frame. Nothing here knows the Bucket's layout: another ship with other thrusters works too.

signal message(text: String) # For the cockpit terminal

enum Order { NONE, KILL, MATCH }

const SOLVER_PASSES: int = 12
const MAX_HOVER_HITS: int = 32 # Results per query. A rock is made of many rectangles

@export var ship: RigidBody2D
@export var module: ComputerModule # Empty = a basic computer
@export var kill_action: StringName = &"kill_momentum"
@export var match_action: StringName = &"match_velocity"
@export var spin_weight: float = 100.0 # px. Puts spin errors on the same scale as speed errors. Higher = spin gets fixed first

var order: Order = Order.NONE
var target: Asteroid # The rock being matched (Order.MATCH)
var hovered: Asteroid # The rock under the mouse, or null
var mothership_target: Mothership # The mothership being matched (Order.MATCH), instead of a rock
var hovered_mothership: Mothership # The mothership under the mouse, when no rock is

var _is_matched: bool = false # The match order reached the rock's speed once (for the terminal)
var _hover_shape := CircleShape2D.new()


func _ready() -> void:
	assert(ship != null, "ShipComputer: assign the ship in the inspector")

	if module == null:
		module = ComputerModule.new()


func _physics_process(_delta: float) -> void:
	_update_hovered()

	if Input.is_action_just_pressed(kill_action):
		_start_kill()

	if Input.is_action_just_pressed(match_action):
		_start_match()


# Called by ShipMovement every physics frame. Adds the computer's requests to the thrusters.
func steer(thrusters: Array[Thruster], is_player_steering: bool) -> void:
	if order == Order.MATCH and not _has_match_target():
		_end_order("Computer: target lost")

	if is_player_steering:
		if order != Order.NONE:
			_end_order("Computer: manual control")

		return

	var reference := _get_match_velocity() if order == Order.MATCH else Vector2.ZERO
	var velocity_error := reference - ship.linear_velocity
	var spin_error := -ship.angular_velocity
	var speed_gap := velocity_error.length()
	var spin_gap := absf(spin_error)
	var is_speed_done := speed_gap <= module.done_speed
	var is_spin_done := spin_gap <= module.done_spin

	if order == Order.KILL and is_speed_done and is_spin_done:
		_end_order("Computer: all stop")
		return

	if order == Order.MATCH and is_speed_done and not _is_matched:
		_is_matched = true
		message.emit("Computer: speed matched")

	var fixes_speed := not is_speed_done and (order != Order.NONE or _can_settle(speed_gap, module.settle_speed))
	var fixes_spin := not is_spin_done and (order == Order.KILL or _can_settle(spin_gap, module.settle_spin))

	if not fixes_speed and not fixes_spin:
		return

	# An axis left alone still asks for zero acceleration, so fixing one doesn't upset the other.
	var wanted_acceleration := velocity_error / module.response_time if fixes_speed else Vector2.ZERO
	var wanted_spin_acceleration := spin_error / module.response_time if fixes_spin else 0.0
	_fire(thrusters, wanted_acceleration, wanted_spin_acceleration)


func _start_kill() -> void:
	if not module.can_kill_momentum:
		return

	order = Order.KILL
	target = null
	mothership_target = null
	message.emit("Computer: killing momentum")


func _start_match() -> void:
	if not module.can_match_velocity:
		return

	if hovered != null:
		target = hovered
		mothership_target = null
		message.emit("Computer: matching rock")
	elif hovered_mothership != null:
		target = null
		mothership_target = hovered_mothership
		message.emit("Computer: matching mothership")
	else:
		return

	order = Order.MATCH
	_is_matched = false


func _end_order(text: String) -> void:
	order = Order.NONE
	target = null
	mothership_target = null
	message.emit(text)


func _has_match_target() -> bool:
	return _is_valid_rock(target) or is_instance_valid(mothership_target)


func _get_match_velocity() -> Vector2:
	if _is_valid_rock(target):
		return target.linear_velocity

	return mothership_target.cruise_velocity


func _can_settle(gap: float, limit: float) -> bool:
	return module.can_settle and gap < limit


# Finds thruster strengths whose combined effect is as close as possible to the wanted
# accelerations, then requests them. Each thruster's effect is a Vector3: push x, push y, turn.
func _fire(thrusters: Array[Thruster], wanted_acceleration: Vector2, wanted_spin_acceleration: float) -> void:
	var state := PhysicsServer2D.body_get_direct_state(ship.get_rid())
	var center := ship.global_position + state.center_of_mass
	var effects: Array[Vector3] = []

	for thruster in thrusters:
		effects.append(_get_effect(thruster, center, state.inverse_mass, state.inverse_inertia))

	var strengths := PackedFloat32Array()
	strengths.resize(thrusters.size())
	var error := -Vector3(wanted_acceleration.x, wanted_acceleration.y, wanted_spin_acceleration * spin_weight)

	for _pass in SOLVER_PASSES:
		for i in thrusters.size():
			var effect := effects[i]
			var reach := effect.length_squared()

			if reach <= 0.0:
				continue

			var old_strength := strengths[i]
			var new_strength := clampf(old_strength - effect.dot(error) / reach, 0.0, 1.0)
			error += effect * (new_strength - old_strength)
			strengths[i] = new_strength

	for i in thrusters.size():
		thrusters[i].request_thrust(strengths[i])


func _get_effect(thruster: Thruster, center: Vector2, inverse_mass: float, inverse_inertia: float) -> Vector3:
	var force: Vector2 = thruster.get_max_force()
	var torque := (thruster.global_position - center).cross(force)
	var push := force * inverse_mass
	return Vector3(push.x, push.y, torque * inverse_inertia * spin_weight)


# The rock under the mouse. Tries the exact point first, then a small circle around it so small
# chunks are easy to pick. The circle keeps the same size on screen at any zoom.
func _update_hovered() -> void:
	hovered = null
	hovered_mothership = null

	if not module.can_read_rocks:
		return

	var space := ship.get_world_2d().direct_space_state
	var mouse := ship.get_global_mouse_position()
	var point_query := PhysicsPointQueryParameters2D.new()
	point_query.position = mouse
	var point_hits := space.intersect_point(point_query, MAX_HOVER_HITS)
	hovered = _pick_rock(point_hits)

	if hovered != null:
		return

	hovered_mothership = _pick_mothership(point_hits)

	if hovered_mothership != null:
		return

	_hover_shape.radius = module.hover_radius / ship.get_viewport().get_canvas_transform().get_scale().x
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = _hover_shape
	shape_query.transform = Transform2D(0.0, mouse)
	hovered = _pick_rock(space.intersect_shape(shape_query, MAX_HOVER_HITS))


func _pick_rock(hits: Array[Dictionary]) -> Asteroid:
	for hit in hits:
		var rock := hit.collider as Asteroid

		if _is_valid_rock(rock):
			return rock

	return null


func _pick_mothership(hits: Array[Dictionary]) -> Mothership:
	for hit in hits:
		var mothership := hit.collider as Mothership

		if mothership != null:
			return mothership

	return null


# Rocks being smelted leave the group; a rock bolted to the ship is frozen.
func _is_valid_rock(rock: Asteroid) -> bool:
	return is_instance_valid(rock) and rock.is_in_group(Asteroid.GROUP) and not rock.freeze
