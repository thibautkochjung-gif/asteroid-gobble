extends "res://_tools/soft_points_test.gd"

# Dev tool: puts the rock bolter through rough situations (ramming a rock, flying fast while
# bolted, letting go at speed) and logs whether ship and rock stay together and finite.
# Logs to _tools/rock_bolter_test.log, then quits.


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_player = _main.get_node("Player")
	_soft_points = _player.get_node("SoftPoints")
	_rooms = _player.get_node("Rooms")
	_generator = _player.get_node("Generator")

	_camera = Camera2D.new()
	_main.add_child(_camera)
	_camera.make_current()

	_soft_points.message.connect(func(index: int, text: String) -> void: _write("  [msg %d] %s" % [index + 1, text]))
	await _frames(10)

	await _case("rock at rest, ship at rest", 20.0, 0.0, false)
	await _case("ship closing in at 25 px/s", 30.0, 25.0, false)
	await _case("ship closing in at 60 px/s", 30.0, 60.0, false)
	await _case("bolted, then another rock hits it", 20.0, 0.0, true)

	_write("")
	_write("DONE: %d checks passed, %d failed" % [_checks_passed, _checks_failed])
	get_tree().quit()


func _case(label: String, gap: float, ram_speed: float, hit_by_rock: bool) -> void:
	await _clear_area()
	_write("")
	_write("== " + label)
	var bolter := _install(2, SoftPoint.Type.ROCK_BOLTER) as RockBolter

	while bolter.state != RockBolter.State.STOWED:
		await _frames(1)

	var rock := _main.get_node("Asteroid2") as Asteroid
	_place_rock_off_tip(rock, bolter, gap)
	_player.linear_velocity = bolter.get_outward() * ram_speed
	await _frames(2)

	bolter._on_tap()
	await _watch(bolter, rock, 1.0)

	_write("  state after tap: %s, rock parent %s" % [RockBolter.State.keys()[bolter.state], rock.get_parent().name])

	if ram_speed > bolter.max_lock_speed:
		_check(bolter.state != RockBolter.State.LOCKED, label + ": too fast, pitons bounce off")

	if bolter.state != RockBolter.State.LOCKED:
		return

	if hit_by_rock:
		var other := _main.get_node("Asteroid3") as Asteroid
		var toward := (_player.global_position - rock.get_global_center()).normalized()
		_teleport(other, rock.get_global_center() - toward * 260.0 - other.get_local_center())
		other.linear_velocity = toward * 200.0
		await _watch(bolter, rock, 3.0)
		_write("  after the hit: state %s, module %s, ship v %s" % [RockBolter.State.keys()[bolter.state], _soft_points.get_module(2), _player.linear_velocity])

		if bolter.state != RockBolter.State.LOCKED:
			return

	await get_tree().process_frame # Read after the bolter pins the rock back, as it's drawn
	var offset_before := (_player.global_transform.affine_inverse() * rock.global_transform).origin
	Input.action_press("forward_thrust")
	Input.action_press("left_turn")

	for i in 6:
		await _seconds(0.5)
		await get_tree().process_frame
		var offset := (_player.global_transform.affine_inverse() * rock.global_transform).origin
		_write("  t=%.1f s ship v %s w %.2f, mass %.0f, inertia %.0f, rock offset %s, finite %s" % [(i + 1) * 0.5, _player.linear_velocity, _player.angular_velocity, _player.mass, PhysicsServer2D.body_get_param(_player.get_rid(), PhysicsServer2D.BODY_PARAM_INERTIA), offset, _player.global_position.is_finite()])

	Input.action_release("forward_thrust")
	Input.action_release("left_turn")
	await get_tree().process_frame
	var offset_after := (_player.global_transform.affine_inverse() * rock.global_transform).origin
	_check(offset_before.distance_to(offset_after) < 1.0, label + ": rock stays put on the ship")
	_check(_player.global_position.is_finite() and _player.linear_velocity.is_finite(), label + ": ship finite")

	var ship_velocity := SoftLink.velocity_at(_player, rock.get_global_center())
	var hull_speed := SoftLink.velocity_at(_player, _player.global_position).length()
	var spin := _player.angular_velocity
	bolter._on_tap()
	await _frames(2)
	var hull_speed_after := SoftLink.velocity_at(_player, _player.global_position).length()
	_write("  hull speed %.1f -> %.1f px/s, spin %.2f -> %.2f rad/s, centre of mass now %s" % [hull_speed, hull_speed_after, spin, _player.angular_velocity, _player.center_of_mass])
	_check(absf(hull_speed - hull_speed_after) < 5.0 and absf(spin - _player.angular_velocity) < 0.1, label + ": the ship keeps its own motion when it lets go")

	if not hit_by_rock and ram_speed == 0.0:
		_camera.global_position = rock.get_global_center().lerp(_player.global_position, 0.6)
		_camera.zoom = Vector2.ONE * 3.0
		await _frames(5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://_tools/rock_bolter_release.png")

	_write("  after release: rock v %s, ship v at the rock %s" % [rock.linear_velocity, ship_velocity])
	_check(rock.linear_velocity.distance_to(ship_velocity) < 20.0, label + ": rock leaves with the ship's motion")
	await _seconds(1.0)
	_write("  1 s later: state %s, rock v %s, finite %s" % [RockBolter.State.keys()[bolter.state], rock.linear_velocity, rock.global_position.is_finite()])


# Waits, checking every physics frame that nothing went NaN. Logs the first frame that did.
func _watch(bolter: RockBolter, rock: Asteroid, duration: float) -> void:
	var elapsed := 0.0
	var last_state := bolter.state

	while elapsed < duration:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

		if bolter.state != last_state:
			_write("  %.2f s: %s -> %s" % [elapsed, RockBolter.State.keys()[last_state], RockBolter.State.keys()[bolter.state]])
			last_state = bolter.state

		var ok := _player.global_position.is_finite() and _player.linear_velocity.is_finite() and is_finite(_player.angular_velocity)
		ok = ok and (not is_instance_valid(rock) or rock.global_position.is_finite())

		if not ok:
			_write("  NAN at %.2f s: ship pos %s v %s w %s, mass %s, com %s, rock pos %s v %s" % [elapsed, _player.global_position, _player.linear_velocity, _player.angular_velocity, _player.mass, _player.center_of_mass, rock.global_position, rock.linear_velocity])
			_check(false, "everything finite")
			return


func _write(line: String) -> void:
	print("TEST ", line)
	_log_lines.append(line)
	var file := FileAccess.open("res://_tools/rock_bolter_test.log", FileAccess.WRITE)
	file.store_string("\n".join(_log_lines) + "\n")
