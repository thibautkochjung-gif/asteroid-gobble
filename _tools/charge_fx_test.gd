extends "res://_tools/soft_points_test.gd"

# Dev tool: detonates a charge in the real game view (the player's own camera, its zoom and shake),
# logs the camera shake and takes screenshots. Logs to _tools/charge_fx_test.log, then quits.


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_player = _main.get_node("Player")
	_soft_points = _player.get_node("SoftPoints")
	_rooms = _player.get_node("Rooms")
	_generator = _player.get_node("Generator")
	var camera := _player.get_node("Camera2D") as Camera2D

	await _frames(10)
	await _clear_area()
	var rack := _install(0, SoftPoint.Type.CHARGE_RACK) as ChargeRack
	var rock := _main.get_node("Asteroid2") as Asteroid
	_place_rock_off_tip(rock, rack, 40.0)
	await _frames(3)

	for _i in 1:
		rack._on_tap()
		await _seconds(0.25)

	await _seconds(1.5)
	_write("planted %d, camera zoom %s" % [rack._get_planted().size(), camera.zoom])
	await _game_shot("charge_fx_before")
	rack._on_hold_started()
	var biggest_offset := 0.0

	for frame in 60:
		await get_tree().process_frame
		biggest_offset = maxf(biggest_offset, camera.offset.length())

		if frame < 12:
			_write("  frame %d: delta %.3f s, trauma %.2f, offset %s, noise %.2f" % [frame, get_process_delta_time(), camera.trauma, camera.offset, camera.noise.get_noise_1d(camera.noise_seed_x)])

		if frame == 1:
			await _game_shot("charge_fx_1")
		elif frame == 6:
			await _game_shot("charge_fx_6")
		elif frame == 20:
			await _game_shot("charge_fx_20")

	_write("camera trauma after 1 s: %.2f, biggest shake offset %.1f px" % [camera.trauma, biggest_offset])
	get_tree().quit()


func _game_shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_tools/%s.png" % file_name)


func _write(line: String) -> void:
	print("TEST ", line)
	_log_lines.append(line)
	var file := FileAccess.open("res://_tools/charge_fx_test.log", FileAccess.WRITE)
	file.store_string("\n".join(_log_lines) + "\n")
