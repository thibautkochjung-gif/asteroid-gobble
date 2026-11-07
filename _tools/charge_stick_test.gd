extends "res://_tools/soft_points_test.gd"

# Dev tool: throws demolition charges at rocks in various situations and logs which ones stick.
# Logs to _tools/charge_stick_test.log, then quits.


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

	await _frames(10)

	if not OS.get_cmdline_user_args().has("--weld-only"):
		for gap: float in [20.0, 100.0, 170.0, 220.0, 300.0]:
			await _throw_case("rock %.0f px away" % gap, gap, 0.0, 0.0, false)

		await _throw_case("rock 60 px away, spinning 1 rad/s", 60.0, 1.0, 0.0, false)
		await _throw_case("rock 60 px away, ship moving sideways 40 px/s", 60.0, 0.0, 40.0, false)

	await _throw_case("rock welded by the tether", 15.0, 0.0, 0.0, true)

	_write("")
	_write("DONE: %d checks passed, %d failed" % [_checks_passed, _checks_failed])
	get_tree().quit()


func _throw_case(label: String, gap: float, spin: float, side_speed: float, weld: bool) -> void:
	await _clear_area()
	_write("")
	_write("== " + label)
	var rack := _install(0, SoftPoint.Type.CHARGE_RACK) as ChargeRack
	rack.restock()
	var rock := _main.get_node("Asteroid2") as Asteroid
	_place_rock_off_tip(rock, rack, gap)

	if weld:
		var tether := _install(1, SoftPoint.Type.TETHER) as Tether
		_place_rock_off_tip(rock, tether, 10.0)
		await _frames(2)
		tether._on_tap()
		await _frames(5)
		_write("  welded: %s" % (tether.welded == rock))
		_write("  rock from rack tip: %.1f px" % rock.get_closest_point(rack.get_tip()).distance_to(rack.get_tip()))

	await _frames(3)
	rock.angular_velocity = spin
	_player.linear_velocity = _player.global_transform.y * side_speed
	var charge := rack.launch_item() as DemolitionCharge
	await _seconds(5.0)

	var state_name: String = DemolitionCharge.State.keys()[charge.state]
	_write("  charge: %s, age %.1f s" % [state_name, charge._age])
	_check(charge.is_stuck(), label + ": charge stuck")

	if weld and charge.is_stuck():
		var before: Dictionary[Node, bool] = {}

		for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
			before[node] = true

		rack._on_hold_started()

		for wait: float in [0.05, 0.3, 1.0]:
			await _seconds(wait)

			for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
				var c := node as Asteroid

				if not before.has(c) and c.cells.size() >= 5:
					var toward_ship := c.linear_velocity.normalized().dot((_player.global_position - c.get_global_center()).normalized())
					_write("    +%.2f s chunk %d cells: %.1f px/s, heading toward the ship %.2f (1 = straight at it), %.0f px from it" % [wait, c.cells.size(), c.linear_velocity.length(), toward_ship, c.get_global_center().distance_to(_player.global_position)])

		await _seconds(0.65)
		var flying := 0
		var torn := 0

		for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
			var chunk := node as Asteroid

			if before.has(chunk) or chunk.cells.size() < 5:
				continue

			torn += 1

			if (chunk.linear_velocity - _player.linear_velocity).length() > 15.0:
				flying += 1

		_write("  detonated on the welded rock: %d chunks, %d still flying off after 2 s, ship %.1f px/s" % [torn, flying, _player.linear_velocity.length()])
		_check(torn > 0 and flying == torn, "chunks fly off a welded rock")

	if weld:
		var tether := _soft_points.get_module(1) as Tether
		tether._on_tap()
		await _frames(3)


func _write(line: String) -> void:
	print("TEST ", line)
	_log_lines.append(line)
	var file := FileAccess.open("res://_tools/charge_stick_test.log", FileAccess.WRITE)
	file.store_string("\n".join(_log_lines) + "\n")
