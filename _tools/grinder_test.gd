extends Node

# Dev tool: drops a chunk that's too big for the smelter into the hold, runs the game fast,
# logs what the grinder and the smelter do, takes two screenshots, then quits.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const TIME_SCALE: float = 4.0
const DURATION: float = 40.0 # Game seconds

@export var remove_smelter: bool = false # Swaps the smelter (slot 0) for a cargo room
@export var log_name: String = "grinder_test"
@export var feed_acceleration: float = -1.0 # Overrides the grinder's when >= 0

var _main: Node
var _grinder: Grinder
var _hangar: Hangar
var _rooms: ShipRooms
var _log_lines := PackedStringArray()
var _chunk: Asteroid
var _player: RigidBody2D
var _ship_start: Vector2


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)

	var player := _main.get_node("Player") as RigidBody2D
	_grinder = player.get_node("Grinder")
	_hangar = player.get_node("Hangar")
	_rooms = player.get_node("Rooms")

	var camera := Camera2D.new()
	_main.add_child(camera)
	camera.make_current()
	camera.zoom = Vector2.ONE * 3.0

	for _i in 10:
		await get_tree().physics_frame

	if feed_acceleration >= 0.0:
		_grinder.feed_acceleration = feed_acceleration

	if remove_smelter:
		_rooms.install_room(0, Room.Type.CARGO)

	# Doors open, like when the player pushes a chunk in.
	_hangar.is_open = true
	_hangar.open_amount = 1.0
	_hangar._update_leaves()

	for _i in 3:
		await get_tree().physics_frame

	var chunk := _make_big_chunk(_main.get_node("Asteroid2") as Asteroid) # Normal mass_per_cell (0.1)
	var hold_center := player.to_global(Vector2(100, 0)) # Centre past the door line, tail out of the doors
	var offset := chunk.get_global_center() - chunk.global_position
	chunk.global_transform = Transform2D(player.global_rotation, hold_center - offset)
	chunk.linear_velocity = Vector2.ZERO
	chunk.angular_velocity = 0.0
	chunk.sleeping = false
	camera.global_position = player.to_global(Vector2(60, 0))
	_chunk = chunk
	_player = player
	_ship_start = player.global_position
	_write("chunk of %d cells placed. Too big: %s" % [chunk.cells.size(), _hangar.is_too_big(chunk)])

	Engine.time_scale = TIME_SCALE
	var elapsed := 0.0
	var next_log := 0.0
	var shot_taken := false

	while elapsed < DURATION:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

		if not shot_taken and elapsed > 1.0:
			_save(log_name + "_start")
			shot_taken = true

		if elapsed >= next_log:
			next_log += 2.0
			_log(elapsed)

		if elapsed > 4.5 and elapsed < 7.0 and fmod(elapsed, 0.1) < get_physics_process_delta_time():
			_log_momentum(elapsed)

	_save(log_name + "_end")
	Engine.time_scale = 1.0
	get_tree().quit()


# A block of 12 x 6 cells: fits through the doors, longer than the smelter chamber and the hold.
func _make_big_chunk(asteroid: Asteroid) -> Asteroid:
	var part: Array[Vector2i] = []

	for cell in asteroid.cells:
		if cell.x >= -6 and cell.x < 6 and cell.y >= -3 and cell.y < 3:
			part.append(cell)

	return asteroid.detach_cells(part, Vector2.ZERO)


func _log(elapsed: float) -> void:
	var sizes: Array[int] = []

	for chunk in _hangar.get_chunks_inside():
		sizes.append(chunk.cells.size())

	if is_instance_valid(_chunk):
		_write("   chunk centre in ship space: %s" % _player.to_local(_chunk.get_global_center()))

	_write("   ship moved %.1f px from its start, velocity %s" % [_player.global_position.distance_to(_ship_start), _player.linear_velocity])
	_write("t=%.0fs  hold=%s  grinder=%s  smelter=%d cells  cargo=%.1f" % [elapsed, sizes, _grinder.get_status_text(), _rooms.get_smelter_cells(), _rooms.get_cargo_cells()])


# Ship + every asteroid within 300 px: internal forces can't change this total.
func _log_momentum(elapsed: float) -> void:
	var total := _player.linear_velocity * _player.mass
	var parts := PackedStringArray()

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		var asteroid := node as Asteroid

		if asteroid.global_position.distance_to(_player.global_position) < 300.0:
			total += asteroid.linear_velocity * asteroid.mass
			parts.append("%d cells m=%.1f v=%s" % [asteroid.cells.size(), asteroid.mass, asteroid.linear_velocity.round()])

	_write("   %.2fs P=%s ship m=%.1f v=%s | %s" % [elapsed, total.round(), _player.mass, _player.linear_velocity, ", ".join(parts)])


# Printed, and saved to _tools/<log_name>.log (the output is lost when the game quits).
func _write(line: String) -> void:
	print("TEST ", line)
	_log_lines.append(line)
	var file := FileAccess.open("res://_tools/%s.log" % log_name, FileAccess.WRITE)
	file.store_string("\n".join(_log_lines) + "\n")


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_tools/%s.png" % file_name)
