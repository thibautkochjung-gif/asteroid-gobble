extends "res://_tools/soft_points_test.gd"

# Dev tool: plants charges on a big rock, detonates them, and logs how fast the rock and the
# chunks move afterwards. Logs to _tools/charge_blast_test.log, then quits.


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
	await _run_case(1)
	await _run_case(2)
	await _run_case(4)
	get_tree().quit()


func _run_case(charge_count: int) -> void:
	await _clear_area()
	_write("")
	_write("== %d charge(s) on Asteroid2" % charge_count)
	var rack := _install(0, SoftPoint.Type.CHARGE_RACK) as ChargeRack
	rack.restock()
	var rock := _main.get_node("Asteroid2") as Asteroid
	_teleport(rock, _player.global_position + Vector2(0, -600) + rock.global_position - rock.get_global_center())
	await _frames(3)

	var center := rock.get_global_center()

	for i in charge_count:
		var side := Vector2.from_angle(-PI * 0.5 + (i - (charge_count - 1) * 0.5) * 0.35)
		var charge := rack._make_item() as DemolitionCharge
		_main.add_child(charge)
		charge.global_position = center + side * 200.0
		charge.linear_velocity = -side * 80.0
		rack.launched.append(charge)

	await _seconds(3.0)
	_write("  planted %d, rock %d cells, mass %.1f" % [rack._get_planted().size(), rock.cells.size(), rock.mass])

	if charge_count == 4:
		var planted := rack._get_planted()
		var focus := planted[1].global_position if planted.size() > 1 else center
		await _shot("charge_armed_a", focus, 4.0)
		await _seconds(0.3)
		await _shot("charge_armed_b", focus, 4.0)
		await _seconds(0.4)
		await _shot("charge_armed_c", focus, 4.0)

	var before: Dictionary[Node, bool] = {}

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		before[node] = true

	var blast_at := rack._get_planted()[0].global_position
	var started := Time.get_ticks_usec()
	rack._on_hold_started()

	if charge_count == 1:
		await _shot("charge_explosion_a", blast_at, 3.0)
		await _frames(6)
		await _shot("charge_explosion_b", blast_at, 3.0)
		await _seconds(0.6)
		await _shot("charge_explosion_c", blast_at, 2.0)
		await _seconds(2.5)
		await _shot("charge_hole", blast_at, 2.0)
	await get_tree().process_frame
	_write("  detonation + first frame: %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	var sizes: Array[int] = []

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		if not before.has(node):
			sizes.append((node as Asteroid).cells.size())

	sizes.sort()
	_write("  new bodies: %d, sizes %s" % [sizes.size(), sizes])

	for wait: int in [3, 30, 90]:
		await _frames(wait)
		_write("  after %d more frames: rock %.1f px/s (%d cells)" % [wait, rock.linear_velocity.length(), rock.cells.size()])

		for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
			var chunk := node as Asteroid

			if before.has(chunk) or chunk.cells.size() < 5:
				continue

			if wait != 30:
				continue

			var relative := chunk.linear_velocity - rock.linear_velocity
			var gap := rock.get_closest_point(chunk.get_global_center()).distance_to(chunk.get_closest_point(rock.get_global_center()))
			var away := relative.dot((chunk.get_global_center() - rock.get_global_center()).normalized())
			_write("    chunk %d cells: %.1f px/s, %.1f px/s relative to rock (%.1f px/s away from it), gap %.1f px" % [chunk.cells.size(), chunk.linear_velocity.length(), relative.length(), away, gap])



func _write(line: String) -> void:
	print("TEST ", line)
	_log_lines.append(line)
	var file := FileAccess.open("res://_tools/charge_blast_test.log", FileAccess.WRITE)
	file.store_string("\n".join(_log_lines) + "\n")
