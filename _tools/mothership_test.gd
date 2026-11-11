extends Node

# Test: pickup spawn rules, a docking that's too fast, a clean docking, the deflector pushing a
# rock aside. Loads main.tscn, moves things around by hand and prints the results.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")

var _main: Node
var _dispatch: MothershipDispatch
var _ship: RigidBody2D


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_dispatch = _main.get_node("MothershipDispatch")
	_ship = _main.get_node("Player")
	_run.call_deferred()


func _run() -> void:
	await _wait(0.5)
	var drop_off: Mothership = get_tree().get_first_node_in_group(Mothership.GROUP)
	print("TEST drop-off: state %s (0 = carrying), slot %02d, ship in slot: %s" % [drop_off.state, drop_off.player_slot.number, drop_off._is_in_slot(_ship)])

	# Out of the slot with a short burn of the main engine
	var drop_slot := drop_off.global_transform * drop_off.get_player_slot_transform()
	await _wait(4.0) # The clamps' push alone
	var away := _ship.global_position - (drop_off.global_transform * drop_off.get_player_slot_transform()).origin
	print("TEST drop-off: drifted %.0f px off the slot, %.0f deg from straight out, ship %.0f deg from the train's heading" % [away.length(), rad_to_deg(absf(away.angle_to(drop_slot.y * signf(drop_off.get_player_slot_transform().origin.y)))), rad_to_deg(absf(angle_difference(_ship.global_rotation, drop_off.global_rotation)))])
	print("TEST drop-off: state %s (2 = leaving), hull %.0f%%" % [drop_off.state, 100.0 * _hull()])

	_check_spots()
	_place(Vector2(0, 4000), 0.0, Vector2.ZERO)
	await _wait(0.3)
	_dispatch._call_pickup()
	await _wait(0.3)
	var train := _dispatch._pickup
	var out := train.get_marker_position() - _ship.global_position
	print("TEST pickup: slot %.0f km away, %.0f deg off 'straight away'" % [out.length() / 1000.0, rad_to_deg(absf((train.global_position - _ship.global_position).angle_to(train.cruise_velocity)))])

	# Too fast: come at the slot from outside the car, 150 px/s faster than the train
	var slot := train.global_transform * train.get_player_slot_transform()
	var side := signf(train.get_player_slot_transform().origin.y)
	var inward := -slot.y.normalized() * side
	_place(slot.origin - inward * 260.0, slot.get_rotation(), train.cruise_velocity + inward * 150.0)
	await _wait(2.0)
	print("TEST too fast: state %s (1 = waiting), hull %.0f%%" % [train.state, 100.0 * _hull()])

	# Clean: 25 px/s
	slot = train.global_transform * train.get_player_slot_transform()
	_place(slot.origin - inward * 260.0, slot.get_rotation(), train.cruise_velocity + inward * 25.0)
	await _wait(14.0)
	print("TEST docking: state %s (3 = docking), secured %s, home %s, fees %d" % [train.state, train.is_player_secured, _dispatch.is_home, _dispatch.fees_paid])

	# Deflector: a train driven at the big rock
	var rock: Asteroid = _main.get_node("Asteroid3")
	var cells_before := rock.cells.size()
	var breaker := _dispatch._make(Vector2.RIGHT, false)
	breaker.state = Mothership.State.WAITING
	breaker.position = rock.global_position + Vector2(-2600, 0)
	_dispatch._add(breaker)
	var start_y := rock.global_position.y
	await _wait(25.0)
	var lateral := rock.global_position.y - start_y if is_instance_valid(rock) else 0.0
	var behind := breaker.to_local(rock.global_position).x < 0.0 if is_instance_valid(rock) else false
	print("TEST deflector: rock moved %.0f px sideways, now %s the locomotive, cells %d -> %d" % [lateral, "beside/behind" if behind else "ahead of", cells_before, rock.cells.size()])


func _check_spots() -> void:
	var worst_angle := 0.0
	var shortest := INF
	var longest := 0.0

	for i in 500:
		var spot := _dispatch._pick_spot()
		var out: Vector2 = spot.position - _ship.global_position
		worst_angle = maxf(worst_angle, rad_to_deg(absf(out.angle_to(spot.heading))))
		shortest = minf(shortest, out.length())
		longest = maxf(longest, out.length())

	print("TEST spots: distance %.0f..%.0f, worst heading %.1f deg from straight away" % [shortest, longest, worst_angle])


func _hull() -> float:
	return _main.get_node("Player/ShipDamage").get_hull_ratio()


func _place(at: Vector2, angle: float, velocity: Vector2) -> void:
	var xform := Transform2D(angle, at)
	_ship.global_transform = xform
	PhysicsServer2D.body_set_state(_ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	_ship.linear_velocity = velocity
	_ship.angular_velocity = 0.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
