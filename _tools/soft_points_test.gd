extends Node

# Dev tool: runs main.tscn and puts every soft point through its paces, one after the other.
# Logs to _tools/soft_points_test.log (the output is lost when the game quits), takes a few
# screenshots (_tools/soft_points_*.png), then quits.
# Run this scene (not main) to check the soft points after a change.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")

var _main: Node2D
var _player: RigidBody2D
var _soft_points: ShipSoftPoints
var _rooms: ShipRooms
var _generator: Generator
var _camera: Camera2D
var _log_lines := PackedStringArray()
var _checks_passed: int = 0
var _checks_failed: int = 0


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
	_camera.zoom = Vector2.ONE * 2.0

	_soft_points.message.connect(func(index: int, text: String) -> void: _write("  [msg %d] %s" % [index + 1, text]))
	await _frames(10)
	_write("start: mass %.1f, centre of mass %s" % [_player.mass, _player.center_of_mass])

	await _test_layout_and_mass()
	await _test_drop_tank()
	await _test_harpoon()
	await _test_tether()
	await _test_clamp()
	await _test_charges()
	await _test_probe()
	await _test_beacon_and_flare()
	await _test_cache_buoy()
	await _test_canister()
	await _test_capacitor()
	await _test_ballast_and_balance()
	await _test_tear_off()

	_write("")
	_write("DONE: %d checks passed, %d failed" % [_checks_passed, _checks_failed])
	get_tree().quit()


# --- Tests


func _test_layout_and_mass() -> void:
	_write("")
	_write("== Layout")

	for i in _soft_points.get_mount_count():
		var module := _soft_points.get_module(i)
		_write("  mount %d %s: %s" % [i + 1, _soft_points.get_mount_name(i), module.get_type_name() if module != null else "empty"])

	_check(_soft_points.get_mount_count() == 4, "4 mounts")
	_check(_player.mass > 26.0, "soft point mass counted (ship %.1f)" % _player.mass)
	await _shot("soft_points_ship", _player.global_position, 3.0)


func _test_drop_tank() -> void:
	await _clear_area()
	_write("")
	_write("== Drop tank")
	_reset_ship()
	var tank := _install(1, SoftPoint.Type.DROP_TANK) as DropTank
	var tank_fuel := tank.fuel
	var room_fuel := _rooms.get_fuel()

	Input.action_press("forward_thrust")
	await _seconds(1.0)
	Input.action_release("forward_thrust")

	_write("  drop tank %.1f -> %.1f, rooms %.1f -> %.1f" % [tank_fuel, tank.fuel, room_fuel, _rooms.get_fuel()])
	_check(tank.fuel < tank_fuel and is_equal_approx(room_fuel, _rooms.get_fuel()), "drop tank burned first")

	_reset_ship()
	var mass_before := _player.mass
	_soft_points.jettison(tank)
	await _frames(3)
	var prop := _find_prop(ModuleProp)
	_check(prop != null and _soft_points.get_module(1) == null, "jettisoned as a prop")
	_write("  mass %.1f -> %.1f" % [mass_before, _player.mass])
	_check(_player.mass < mass_before, "ship lighter after jettison")

	# Bring it back: put it next to the hull, drifting in slowly.
	await _seconds(1.6)
	_reset_ship()
	var mount := _soft_points.mounts[1]
	prop.global_position = mount.global_position + mount.global_transform.x * 18.0
	prop.linear_velocity = -mount.global_transform.x * 15.0
	prop.angular_velocity = 0.0
	await _seconds(2.0)
	_check(_soft_points.get_module(1) is DropTank, "drop tank recovered by touching it")


func _test_harpoon() -> void:
	await _clear_area()
	_write("")
	_write("== Harpoon")
	_reset_ship()
	var harpoon := _install(0, SoftPoint.Type.HARPOON) as HarpoonWinch
	var rock := _main.get_node("Asteroid2") as Asteroid
	_place_rock_off_tip(rock, harpoon, 120.0)

	harpoon._on_tap()
	await _seconds(1.0)
	_check(harpoon.state == HarpoonWinch.State.HOOKED, "harpoon hooked the rock (state %d)" % harpoon.state)
	await _shot("soft_points_harpoon", _player.global_position + harpoon.get_outward() * 60.0, 1.5)

	var start_distance := rock.get_closest_point(harpoon.get_tip()).distance_to(harpoon.get_tip())
	harpoon._on_hold_started()
	await _seconds(3.0)
	harpoon._on_hold_ended()
	var end_distance := rock.get_closest_point(harpoon.get_tip()).distance_to(harpoon.get_tip())
	_write("  distance %.0f -> %.0f, cable %.0f, ship spin %.2f" % [start_distance, end_distance, harpoon.rope_length, _player.angular_velocity])
	_check(end_distance < start_distance - 20.0, "reeling pulled the rock in")

	harpoon._on_tap()
	await _seconds(1.5)
	_check(harpoon.state == HarpoonWinch.State.STOWED, "harpoon back in its tube")
	_park_rock(rock, Vector2(700, -600))


func _test_tether() -> void:
	await _clear_area()
	_write("")
	_write("== Tether")
	_reset_ship()
	var tether := _install(2, SoftPoint.Type.TETHER) as Tether
	var rock := _main.get_node("Asteroid") as Asteroid
	_place_rock_off_tip(rock, tether, 8.0)
	await _frames(3)

	var mass_before := _player.mass
	tether._on_tap()
	await _frames(5)
	_check(tether.welded == rock and rock.get_parent() == _player, "rock welded and moved under the ship")
	_write("  ship mass %.1f -> %.1f (rock %.1f)" % [mass_before, _player.mass, rock.mass])
	_check(_player.mass > mass_before + rock.mass * 0.9, "rock's mass added")

	var relative := _player.global_transform.affine_inverse() * rock.global_transform
	Input.action_press("forward_thrust")
	Input.action_press("left_turn")
	await _seconds(1.5)
	Input.action_release("forward_thrust")
	Input.action_release("left_turn")
	var relative_after := _player.global_transform.affine_inverse() * rock.global_transform
	_write("  rock offset in ship space %s -> %s, ship v %s" % [relative.origin, relative_after.origin, _player.linear_velocity])
	_check(relative.origin.distance_to(relative_after.origin) < 0.5, "ship and rock move as one")
	await _shot("soft_points_tether", _player.global_position, 1.2)

	# Cut the welded rock in two: the far half must go to space, not into the ship.
	_reset_ship()
	var groups_before := get_tree().get_nodes_in_group(Asteroid.GROUP).size()
	var center := rock.to_local(rock.get_global_center()) / rock.cell_size
	var cells: Array[Vector2i] = []
	cells.assign(rock.cells.keys())
	var far_side := rock.to_local(tether.get_tip()).direction_to(center * rock.cell_size)
	var cut_count := 0

	for cell in cells:
		var along := (Vector2(cell) - center).dot(far_side)

		if along > 2.0 and along < 4.0:
			rock.remove_cell(cell)
			cut_count += 1

	await _frames(5)
	var groups_after := get_tree().get_nodes_in_group(Asteroid.GROUP).size()
	var chunk_in_ship := false

	for child in _player.get_children():
		if child is Asteroid and child != rock:
			chunk_in_ship = true

	_write("  cut %d cells, asteroids %d -> %d" % [cut_count, groups_before, groups_after])
	_check(groups_after > groups_before and not chunk_in_ship, "cut-off part went to space")

	tether._on_tap()
	await _frames(3)
	_check(tether.welded == null and rock.get_parent() == _main and not rock.freeze, "let go")
	_park_rock(rock, Vector2(-500, 500))


func _test_clamp() -> void:
	await _clear_area()
	_write("")
	_write("== Magnetic clamp")
	_reset_ship()
	var magnet := _install(3, SoftPoint.Type.MAGNETIC_CLAMP) as MagneticClamp

	# A barren rock: every ore cell turned to rock.
	var barren := _main.get_node("Asteroid2") as Asteroid

	for cell in barren.cells.keys():
		if barren.cells[cell] == barren.ore_type:
			barren.cells[cell] = CellMaterials.Id.SOFT_ROCK

	_place_rock_off_tip(barren, magnet, 4.0)
	await _frames(3)
	magnet._on_tap()
	_check(magnet.target != barren, "no grip on a barren rock")

	if not magnet.anchors.is_empty():
		magnet._on_tap() # It gripped something else nearby (a chunk with ore): let go
	_park_rock(barren, Vector2(900, -900))

	var rich := _main.get_node("Asteroid3") as Asteroid
	_place_rock_off_tip(rich, magnet, 4.0)
	await _frames(3)

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		var near := node as Asteroid
		var distance := near.get_closest_point(magnet.get_tip()).distance_to(magnet.get_tip())

		if distance < 40.0:
			_write("  near the pads: %s, %d cells, %.1f px, ore inside %s" % [near.name, near.cells.size(), distance, near.has_ore_cells()])

	magnet._on_tap()
	_check(not magnet.anchors.is_empty(), "grip on a rock with ore (%d cells)" % rich.cells.size())

	Input.action_press("forward_thrust")
	await _seconds(1.0)
	Input.action_release("forward_thrust")
	await _seconds(0.5)
	var gap := rich.get_closest_point(magnet.get_tip()).distance_to(magnet.get_tip())
	_write("  heavy rock (mass %.0f) after a full-thrust second: gripping %s, gap %.1f px" % [rich.mass, not magnet.anchors.is_empty(), gap])

	if not magnet.anchors.is_empty():
		magnet._on_tap()

	_park_rock(rich, Vector2(1200, 900))


func _test_charges() -> void:
	await _clear_area()
	_write("")
	_write("== Demolition charges")
	_reset_ship()
	var rack := _install(0, SoftPoint.Type.CHARGE_RACK) as ChargeRack

	# First, two throws from the rack onto one face of a big rock: they stick (a shallow groove).
	var big := _main.get_node("Asteroid2") as Asteroid
	_place_rock_off_tip(big, rack, 30.0)
	rack._on_tap()
	await _seconds(0.1)
	_player.global_position += _player.global_transform.x * 40.0
	_reset_ship()
	rack._on_tap()
	await _seconds(1.5)
	_check(rack._get_planted().size() == 2, "2 thrown charges stuck on the rock")
	var big_cells := big.cells.size()
	rack._on_hold_started()
	await _seconds(0.5)
	_write("  same face: %d -> %d cells" % [big_cells, big.cells.size()])
	await _clear_area()
	rack.restock()

	# Then the real use: charges on opposite sides of a small rock, so the det-cord crosses it.
	var source := _main.get_node("Asteroid") as Asteroid
	var rock := source.detach_cells(source.grow_part(source.cells.keys()[0], 160), Vector2.ZERO)
	await _frames(3)
	rock.global_position += _player.global_position + Vector2(0, -1200) - rock.get_global_center() # Clear of every parked rock
	rock.linear_velocity = Vector2.ZERO
	rock.angular_velocity = 0.0
	await _frames(2)
	var count_before := get_tree().get_nodes_in_group(Asteroid.GROUP).size()
	var cells_before := rock.cells.size()

	for side: float in [-1.0, 1.0]:
		var charge := rack._make_item() as DemolitionCharge
		_main.add_child(charge)
		charge.global_position = rock.get_global_center() + Vector2(side * 60.0, 0.0)
		charge.linear_velocity = Vector2(-side * 60.0, 0.0)
		rack.launched.append(charge)

	await _seconds(1.5)

	var planted := rack._get_planted()
	_check(planted.size() == 2 and planted[0].get_rock() == rock and planted[1].get_rock() == rock, "2 charges planted on opposite sides of the same rock")
	await _shot("soft_points_charges", rock.get_global_center(), 2.0)

	rack._on_hold_started()
	await _seconds(0.1)
	await _shot("soft_points_charges_cut", rock.get_global_center(), 2.0)
	await _seconds(0.9)
	var count_after := get_tree().get_nodes_in_group(Asteroid.GROUP).size()
	_write("  rock cells %d -> %d, asteroids %d -> %d" % [cells_before, rock.cells.size(), count_before, count_after])
	_check(count_after > count_before and cells_before - rock.cells.size() > 30, "det-cord cut the rock in pieces")


func _test_probe() -> void:
	await _clear_area()
	_write("")
	_write("== Survey probe")
	_reset_ship()
	var rack := _install(2, SoftPoint.Type.PROBE_RACK) as ProbeRack
	var rock := _main.get_node("Asteroid3") as Asteroid
	_place_rock_off_tip(rock, rack, 60.0)
	var revealed_before := rock.revealed_ore.size()
	var ore_total := 0

	for cell in rock.cells:
		if rock.cells[cell] == rock.ore_type:
			ore_total += 1

	var probe := rack.launch_item() as SurveyProbe
	await _seconds(0.5)
	probe.linear_velocity = Vector2.ZERO # Hold it still, so "in range" means the same thing at its last ping
	probe.angular_velocity = 0.0
	await _seconds(2.0)

	# Every ore cell within the scan radius of the probe must be revealed by now.
	var in_range := 0
	var missed := 0

	for cell in rock.cells:
		if rock.cells[cell] != rock.ore_type:
			continue

		if rock.get_cell_global_position(cell).distance_to(probe.global_position) > probe.scan_radius - rock.cell_size * 2.0:
			continue

		in_range += 1

		if not rock.revealed_ore.has(cell):
			missed += 1

	_write("  revealed ore %d -> %d of %d (%d within range of the probe, %d of those missed)" % [revealed_before, rock.revealed_ore.size(), ore_total, in_range, missed])
	_check(missed == 0, "probe revealed every ore cell in range, buried or not")
	await _shot("soft_points_probe", rock.get_global_center(), 1.0)
	_park_rock(rock, Vector2(1200, 900))


func _test_beacon_and_flare() -> void:
	await _clear_area()
	_write("")
	_write("== Beacon and flare")
	_reset_ship()
	var beacons := _install(0, SoftPoint.Type.BEACON_RACK) as BeaconRack
	var flares := _install(3, SoftPoint.Type.FLARE_RACK) as FlareRack
	var beacon := beacons.launch_item() as Beacon
	var flare := flares.launch_item() as Flare
	await _seconds(3.0)
	_write("  beacon %.0f px from the ship" % beacon.global_position.distance_to(_player.global_position) if is_instance_valid(beacon) else "  beacon gone")

	if not is_instance_valid(beacon):
		_check(false, "beacon still out")
		return

	_write("  beacon speed after 3 s: %.1f px/s, marker '%s'; flare marker '%s'" % [beacon.linear_velocity.length(), beacon.get_marker_text(), flare.get_marker_text()])
	_check(beacon.linear_velocity.length() < 2.0, "beacon held station")
	_check(flare.get_marker_text() == "Flare", "flare burning")
	_player.global_position += Vector2(-900, 0)
	_reset_ship()
	await _shot("soft_points_markers", _player.global_position, 1.0)
	_player.global_position += Vector2(900, 0)
	_reset_ship()


func _test_cache_buoy() -> void:
	await _clear_area()
	_write("")
	_write("== Cache buoy")
	_reset_ship()
	var rack := _install(1, SoftPoint.Type.CACHE_BUOY) as CacheBuoyRack
	var buoy := rack.launch_item() as CacheBuoy
	await _seconds(3.0)

	# A small chunk drifting gently into the buoy.
	var source := _main.get_node("Asteroid") as Asteroid
	var part := source.grow_part(source.cells.keys()[0], 10)
	var chunk := source.detach_cells(part, Vector2.ZERO)
	await _frames(2)
	chunk.global_position += buoy.global_position + Vector2(30, 0) - chunk.get_global_center()
	chunk.linear_velocity = buoy.linear_velocity + Vector2(-15, 0)
	chunk.angular_velocity = 0.0
	await _seconds(3.0)
	_check(buoy.chunks.has(chunk), "buoy latched the chunk")
	_write("  marker '%s'" % buoy.get_marker_text())

	_write("  ship to buoy: %.0f px" % _player.global_position.distance_to(buoy.global_position))
	rack._on_tap()
	await _frames(3)
	_write("  after opening: buoy holds %d, chunk valid %s" % [buoy.chunks.size(), is_instance_valid(chunk)])

	if is_instance_valid(chunk):
		_write("  chunk parent %s, in group %s, frozen %s" % [chunk.get_parent().name, chunk.is_in_group(Asteroid.GROUP), chunk.freeze])

	_check(buoy.chunks.is_empty() and is_instance_valid(chunk) and chunk.get_parent() == _main and chunk.is_in_group(Asteroid.GROUP), "cache opened, chunk free again")


func _test_canister() -> void:
	await _clear_area()
	_write("")
	_write("== Cargo canister")
	_reset_ship()
	var rack := _install(2, SoftPoint.Type.CARGO_CANISTER) as CanisterRack
	_rooms.store_ore(CellMaterials.Id.GOLD, 10.0)
	var cargo_before := _rooms.get_cargo_cells()
	rack._on_tap()
	await _frames(3)
	var canister := _find_prop(CargoCanister) as CargoCanister
	_write("  cargo %.1f -> %.1f, canister %.1f u, mass %.1f" % [cargo_before, _rooms.get_cargo_cells(), canister.get_units() if canister != null else 0.0, canister.mass if canister != null else 0.0])
	_check(canister != null and _rooms.get_cargo_cells() < 0.01, "cargo poured into the canister and thrown")

	await _seconds(1.6)
	_soft_points.try_recover(canister)
	await _frames(2)
	_check(rack.has_canister and _rooms.get_cargo_cells() > 9.9, "canister recovered, ore back in the hold")


func _test_capacitor() -> void:
	_write("")
	_write("== Capacitor")
	var capacitor := _install(3, SoftPoint.Type.CAPACITOR) as CapacitorPack
	var battery_before := _generator.stored
	var caps_before := capacitor.stored
	var granted := _generator.draw_power(10.0)
	_write("  drew %.1f: caps %.1f -> %.1f, battery %.1f -> %.1f" % [granted, caps_before, capacitor.stored, battery_before, _generator.stored])
	_check(capacitor.stored < caps_before and is_equal_approx(_generator.stored, battery_before), "capacitor drawn first")
	await _seconds(8.0)
	_check(capacitor.stored > caps_before - 10.0, "capacitor recharging from the surplus (%.1f)" % capacitor.stored)


func _test_ballast_and_balance() -> void:
	await _clear_area()
	_write("")
	_write("== Ballast and balance view")
	_reset_ship()
	_soft_points.clear_mount(3)
	_soft_points.clear_mount(2)
	_soft_points.clear_mount(0)
	await _frames(3)
	var center_before := _player.center_of_mass
	var ballast := _install(1, SoftPoint.Type.BALLAST) as BallastPod
	await _frames(3)
	var view := _player.get_node("BalanceView") as BalanceView
	_write("  centre of mass %s -> %s" % [center_before, _player.center_of_mass])
	_check(_player.center_of_mass.y < center_before.y - 1.0, "ballast on the left pulls the centre of mass left")

	for line in view.get_role_report():
		_write("  " + line)

	view.visible = true
	Input.action_press("right_thrust")
	await _frames(5)
	await _shot("soft_points_balance", _player.global_position, 2.5)
	Input.action_release("right_thrust")
	view.visible = false

	_soft_points.jettison(ballast)
	await _frames(3)
	_write("  after dropping it: %s" % _player.center_of_mass)


func _test_tear_off() -> void:
	await _clear_area()
	_write("")
	_write("== Tear-off")
	_reset_ship()
	var tank := _install(3, SoftPoint.Type.DROP_TANK) as DropTank
	var rock := _main.get_node("Asteroid3") as Asteroid
	_place_rock_off_tip(rock, tank, 40.0)
	rock.linear_velocity = -tank.get_outward() * 250.0
	await _seconds(1.0)
	var torn := _soft_points.get_module(3) == null
	_write("  heavy rock hit the drop tank at 250 px/s: torn off %s" % torn)
	_check(torn, "hard hit tears the module off")


# --- Helpers


# Every rock far away and at rest, every prop gone, the ship still: each test starts clean.
func _clear_area() -> void:
	var i := 0

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		var rock := node as Asteroid

		if rock.get_parent() != _main:
			continue

		_park_rock(rock, Vector2.from_angle(i * 0.7) * (2500.0 + i * 400.0))
		i += 1

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		node.queue_free()

	_reset_ship()
	await _frames(3)
	_reset_ship()

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		var rock := node as Asteroid
		var distance := rock.get_closest_point(_player.global_position).distance_to(_player.global_position)

		if distance < 500.0:
			_write("  (still near the ship after clearing: %s, %d cells, %.0f px, parent %s, frozen %s)" % [rock.name, rock.cells.size(), distance, rock.get_parent().name, rock.freeze])


func _install(mount_index: int, type: SoftPoint.Type) -> SoftPoint:
	_soft_points.install(mount_index, type)
	return _soft_points.get_module(mount_index)


func _reset_ship() -> void:
	_player.linear_velocity = Vector2.ZERO
	_player.angular_velocity = 0.0


# Puts the rock so its surface is `gap` px straight out from the module's tip, at rest.
func _place_rock_off_tip(rock: Asteroid, module: SoftPoint, gap: float) -> void:
	var outward := module.get_outward()
	var tip := module.get_tip()
	_teleport(rock, rock.global_position + tip + outward * 400.0 - rock.get_global_center())

	var surface := rock.get_closest_point(tip)
	_teleport(rock, rock.global_position + tip + outward * gap - surface)
	_write("  placed %s: surface %.1f px from the tip" % [rock.name, rock.get_closest_point(tip).distance_to(tip)])


func _park_rock(rock: Asteroid, offset: Vector2) -> void:
	if not is_instance_valid(rock):
		return

	_teleport(rock, _player.global_position + offset)


# Moves a body and stops it. Setting global_position on a moving RigidBody2D isn't reliable: the
# physics server can write its own position back. So the server is told directly too.
func _teleport(body: RigidBody2D, at: Vector2) -> void:
	var moved := body.global_transform
	moved.origin = at
	body.global_transform = moved
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, moved)
	PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
	PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)


func _find_prop(type: Variant) -> SpaceProp:
	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		if is_instance_of(node, type) and not node.is_queued_for_deletion():
			return node

	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		_checks_passed += 1
		_write("  PASS " + label)
	else:
		_checks_failed += 1
		_write("  FAIL " + label)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _seconds(duration: float) -> void:
	var elapsed := 0.0

	while elapsed < duration:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()


func _shot(file_name: String, at: Vector2, zoom: float) -> void:
	_camera.global_position = at
	_camera.zoom = Vector2.ONE * zoom
	await _frames(2)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_tools/%s.png" % file_name)


# Printed, and saved to _tools/soft_points_test.log.
func _write(line: String) -> void:
	print("TEST ", line)
	_log_lines.append(line)
	var file := FileAccess.open("res://_tools/soft_points_test.log", FileAccess.WRITE)
	file.store_string("\n".join(_log_lines) + "\n")
