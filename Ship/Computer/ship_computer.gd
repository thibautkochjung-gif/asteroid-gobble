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
#
# Auto-trim (computers with can_auto_trim): ShipMovement hands the player's keys to trim() instead
# of firing the thrusters by role. Each pressed axis gets the strongest burn that pushes along it
# and nowhere else, whatever the balance of the ship: forward never spins or strafes, turning never
# changes the speed. Existing drift and spin are left alone. With damaged thrusters a clean burn
# may get too weak; the trim then settles for the closest burn and tells the terminal.

signal message(text: String) # For the cockpit terminal

enum Order { NONE, KILL, MATCH }

const SOLVER_PASSES: int = 12
const MAX_HOVER_HITS: int = 32 # Results per query. A rock is made of many rectangles
const TRIM_TOLERANCE: float = 0.0001 # Share of the largest effect under which two values count as equal
const TRIM_TIE_PASSES: int = 300 # Most passes to balance the thrusters left at break-even (usually a handful)
const TRIM_HYSTERESIS: float = 1.25 # Once degraded, a clean burn must beat the fallback ratio by this much to come back (no flicker)

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
var _is_trim_degraded: bool = false # The last trim fell back on the closest burn on at least one axis
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


func can_trim() -> bool:
	return module.can_auto_trim


# Called by ShipMovement instead of firing thrusters by role, when the computer can trim.
# `intent` is the player's input in the ship's own frame, each part in -1..1:
# x = forward (+) / backward (-), y = strafe right (+) / left (-), z = turn right (+) / left (-).
# Each pressed axis is solved alone, then the burns are added up. If that asks more than 100% of a
# thruster, every strength is scaled down by the same ratio, which keeps the sum clean.
func trim(thrusters: Array[Thruster], intent: Vector3) -> void:
	if intent == Vector3.ZERO:
		return

	var effects := _get_local_effects(thrusters)
	var totals := PackedFloat64Array()
	totals.resize(thrusters.size())
	var is_degraded := false

	for axis in 3:
		var amount := intent[axis]

		if amount == 0.0:
			continue

		var strengths := _solve_clean(effects, axis, signf(amount))

		if strengths.is_empty():
			is_degraded = true
			strengths = _solve_closest(effects, _get_axis_goal(effects, axis, signf(amount)))

		for i in thrusters.size():
			totals[i] += absf(amount) * strengths[i]

	var highest := 1.0

	for total in totals:
		highest = maxf(highest, total)

	for i in thrusters.size():
		thrusters[i].request_thrust(totals[i] / highest)

	if is_degraded != _is_trim_degraded:
		_is_trim_degraded = is_degraded
		message.emit("Computer: trim degraded" if is_degraded else "Computer: trim restored")


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

	var goal := Vector3(wanted_acceleration.x, wanted_acceleration.y, wanted_spin_acceleration * spin_weight)
	var strengths := _solve_closest(effects, goal)

	for i in thrusters.size():
		thrusters[i].request_thrust(strengths[i])


# The strengths (0..1) whose summed effects come closest to `goal`, adjusting one thruster at a
# time. Good at "about right", not at "exactly zero" on an axis: the trim uses _solve_clean for that.
func _solve_closest(effects: Array[Vector3], goal: Vector3) -> PackedFloat64Array:
	var strengths := PackedFloat64Array()
	strengths.resize(effects.size())
	var error := -goal

	for _pass in SOLVER_PASSES:
		for i in effects.size():
			var effect := effects[i]
			var reach := effect.length_squared()

			if reach <= 0.0:
				continue

			var old_strength := strengths[i]
			var new_strength := clampf(old_strength - effect.dot(error) / reach, 0.0, 1.0)
			error += effect * (new_strength - old_strength)
			strengths[i] = new_strength

	return strengths


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


# --- Auto-trim


# Each thruster's effect at full strength (see _get_effect), turned into the ship's frame:
# x = forward push, y = rightward push, z = right turn.
func _get_local_effects(thrusters: Array[Thruster]) -> Array[Vector3]:
	var state := PhysicsServer2D.body_get_direct_state(ship.get_rid())
	var center := ship.global_position + state.center_of_mass
	var effects: Array[Vector3] = []

	for thruster in thrusters:
		var effect := _get_effect(thruster, center, state.inverse_mass, state.inverse_inertia)
		var push := Vector2(effect.x, effect.y).rotated(-ship.global_rotation)
		effects.append(Vector3(push.x, push.y, effect.z))

	return effects


# The strongest clean burn along one axis (0 forward, 1 strafe, 2 turn; `direction` +1 or -1).
# Returns one strength per thruster, or an empty array if the clean burn is too weak to be worth it.
#
# Each thruster has a gain (how much it helps along the axis) and a leak (what it adds on the two
# other axes). We want the most total gain with a total leak of exactly zero.
#
# How: put a price on leaks, one per other axis (a Vector2). At a given price, a thruster is worth
# firing if its gain beats the price of its leak, and worth(price) is the summed profit of those
# thrusters. worth() is never below the best clean gain, and at the right price it equals it (this is
# a small linear program, and worth() is its dual). Its lowest point sits where two thrusters'
# break-even lines cross, on the point of a line closest to price zero, or at price zero: we try
# them all and keep the lowest. At that price, profitable thrusters fire at full, losing ones stay
# off, and the ones at break-even get the strengths that cancel the others' leak.
func _solve_clean(effects: Array[Vector3], axis: int, direction: float) -> PackedFloat64Array:
	var gains := PackedFloat64Array()
	var leaks := PackedVector2Array()
	var largest := 0.0
	var raw_reach := 0.0 # The push along the axis if the leaks didn't matter

	for effect in effects:
		var gain := effect[axis] * direction
		var leak := _get_leak(effect, axis)
		gains.append(gain)
		leaks.append(leak)
		largest = maxf(largest, maxf(absf(gain), leak.length()))
		raw_reach += maxf(gain, 0.0)

	if raw_reach <= 0.0:
		return PackedFloat64Array()

	var tolerance := largest * TRIM_TOLERANCE
	var best_price := Vector2.ZERO
	var best_worth := INF

	for price in _get_candidate_prices(gains, leaks, tolerance):
		var worth := _get_worth(gains, leaks, price)

		if worth < best_worth - tolerance:
			best_worth = worth
			best_price = price

	var fallback_ratio := module.trim_fallback_ratio * TRIM_HYSTERESIS if _is_trim_degraded else module.trim_fallback_ratio

	if best_worth < raw_reach * fallback_ratio:
		return PackedFloat64Array()

	var strengths := PackedFloat64Array()
	strengths.resize(effects.size())
	var at_break_even: Array[int] = []
	var leftover := Vector2.ZERO

	for i in effects.size():
		var profit := gains[i] - leaks[i].dot(best_price)

		if profit > tolerance:
			strengths[i] = 1.0
			leftover += leaks[i]
		elif profit >= -tolerance:
			at_break_even.append(i)

	return _cancel_leak(strengths, leaks, at_break_even, leftover)


# What a thruster adds on the two axes other than `axis`.
func _get_leak(effect: Vector3, axis: int) -> Vector2:
	match axis:
		0:
			return Vector2(effect.y, effect.z)
		1:
			return Vector2(effect.x, effect.z)

	return Vector2(effect.x, effect.y)


# Thruster i breaks even on the line leak_i · price = gain_i. Candidates: price zero, each line's
# point closest to zero, and every crossing of two lines (parallel lines never cross).
func _get_candidate_prices(gains: PackedFloat64Array, leaks: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var prices := PackedVector2Array([Vector2.ZERO])
	var min_size := tolerance * tolerance

	for i in gains.size():
		var leak_i := leaks[i]

		if leak_i.length_squared() > min_size:
			prices.append(leak_i * gains[i] / leak_i.length_squared())

		for j in range(i + 1, gains.size()):
			var leak_j := leaks[j]
			var determinant := leak_i.cross(leak_j)

			if absf(determinant) <= min_size:
				continue

			# Cramer's rule for leak_i · price = gain_i and leak_j · price = gain_j
			var price_x := gains[i] * leak_j.y - gains[j] * leak_i.y
			var price_y := leak_i.x * gains[j] - leak_j.x * gains[i]
			prices.append(Vector2(price_x, price_y) / determinant)

	return prices


func _get_worth(gains: PackedFloat64Array, leaks: PackedVector2Array, price: Vector2) -> float:
	var worth := 0.0

	for i in gains.size():
		worth += maxf(gains[i] - leaks[i].dot(price), 0.0)

	return worth


# Sets the break-even thrusters (0..1) so their leak cancels `leftover`, one at a time like
# _solve_closest. There are few of them and a clean answer exists, so this lands on zero.
func _cancel_leak(strengths: PackedFloat64Array, leaks: PackedVector2Array, at_break_even: Array[int], leftover: Vector2) -> PackedFloat64Array:
	for _pass in TRIM_TIE_PASSES:
		if leftover.is_zero_approx():
			break

		for i in at_break_even:
			var reach := leaks[i].length_squared()

			if reach <= 0.0:
				continue

			var old_strength := strengths[i]
			var new_strength := clampf(old_strength - leaks[i].dot(leftover) / reach, 0.0, 1.0)
			leftover += leaks[i] * (new_strength - old_strength)
			strengths[i] = new_strength

	return strengths


# For the degraded trim: push along the axis as hard as the thrusters allow, leaks accepted.
func _get_axis_goal(effects: Array[Vector3], axis: int, direction: float) -> Vector3:
	var raw_reach := 0.0

	for effect in effects:
		raw_reach += maxf(effect[axis] * direction, 0.0)

	var goal := Vector3.ZERO
	goal[axis] = raw_reach * direction
	return goal
