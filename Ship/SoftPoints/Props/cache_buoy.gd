class_name CacheBuoy
extends SpaceProp

# A stash in space. It stops itself after launch (like a beacon), and latches on to any small
# chunk that bumps into it gently: push chunks into it, harpoon them over, let them drift in.
# Latched chunks ride on the buoy (frozen, out of the asteroid group so tools ignore them) and
# make it heavier. Come back later, tap the rack's key near it: it lets every chunk go, slowly
# drifting apart, ready for the grabber or the hangar.
# It only goes back into its rack empty.

@export var settle_time: float = 2.0
@export var max_station_acceleration: float = 40.0 # px/s². Weighed down by chunks, it stops slower
@export var latch_speed: float = 40.0 # px/s. Faster bumps just bounce off
@export var max_chunk_cells: int = 80 # Per chunk
@export var max_cells: int = 400 # In total
@export var release_speed: float = 8.0 # px/s, chunks drift apart this fast when let go
@export var release_ignore_time: float = 2.0 # s before released chunks collide with the buoy again

var chunks: Array[Asteroid] = []

var _empty_mass: float = 2.0
var _ignored: Dictionary[int, float] = {} # Released chunks: instance id -> seconds before they collide with the buoy again


func _init() -> void:
	super()
	radius = 7.0
	body_color = Color(0.67, 0.36, 0.18)
	light_color = Color(1.0, 0.85, 0.35)


func _ready() -> void:
	super()
	_empty_mass = mass


func _prop_process(delta: float) -> void:
	_hold_station(delta, settle_time, max_station_acceleration * _empty_mass / mass)
	_tick_ignored(delta)
	_latch_touching()


func can_recover() -> bool:
	return chunks.is_empty()


func get_cell_count() -> int:
	var total := 0

	for chunk in chunks:
		if is_instance_valid(chunk):
			total += chunk.cells.size()

	return total


func get_marker_text() -> String:
	if chunks.is_empty():
		return "Cache (empty)"

	return "Cache %d chunks, %d cells" % [chunks.size(), get_cell_count()]


# Lets go of every chunk. They drift away from the buoy, slowly.
func release_all() -> int:
	var space := get_parent()
	var count := 0

	for chunk in chunks:
		if not is_instance_valid(chunk):
			continue

		var away := (chunk.get_global_center() - global_position).normalized()
		var velocity := SoftLink.velocity_at(self, chunk.get_global_center()) + away * release_speed

		chunk.reparent(space, true)
		chunk.space_parent = null
		chunk.freeze = false
		chunk.collision_layer = chunk.get_meta(&"cache_layer", 1)
		chunk.collision_mask = chunk.get_meta(&"cache_mask", 1)
		chunk.add_to_group(Asteroid.GROUP)
		chunk.linear_velocity = velocity
		chunk.angular_velocity = 0.0
		add_collision_exception_with(chunk)
		_ignored[chunk.get_instance_id()] = release_ignore_time
		count += 1

	chunks.clear()
	mass = _empty_mass
	return count


func _latch_touching() -> void:
	for body in get_colliding_bodies():
		var chunk := body as Asteroid

		if chunk == null or chunk.freeze or _ignored.has(chunk.get_instance_id()):
			continue

		if chunk.cells.size() > max_chunk_cells or get_cell_count() + chunk.cells.size() > max_cells:
			continue

		var relative_speed := (chunk.linear_velocity - linear_velocity).length()

		if relative_speed > latch_speed:
			continue

		_latch(chunk)


func _latch(chunk: Asteroid) -> void:
	# Momentum: the buoy catches the chunk, like the hangar does.
	var total_mass := mass + chunk.mass
	linear_velocity = (linear_velocity * mass + chunk.linear_velocity * chunk.mass) / total_mass

	chunk.set_meta(&"cache_layer", chunk.collision_layer)
	chunk.set_meta(&"cache_mask", chunk.collision_mask)
	chunk.remove_from_group(Asteroid.GROUP)
	chunk.space_parent = get_parent()
	chunk.collision_layer = 0
	chunk.collision_mask = 0
	chunk.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	chunk.freeze = true
	chunk.reparent(self, true)
	chunks.append(chunk)
	mass = total_mass


func _tick_ignored(delta: float) -> void:
	for id in _ignored.keys():
		var chunk := instance_from_id(id) as Asteroid

		if chunk == null:
			_ignored.erase(id)
			continue

		_ignored[id] -= delta

		if _ignored[id] > 0.0:
			continue

		_ignored.erase(id)
		remove_collision_exception_with(chunk)


func _draw_prop() -> void:
	draw_circle(Vector2.ZERO, radius, outline_color)
	draw_circle(Vector2.ZERO, radius - TEXEL * 0.5, body_color)
	draw_circle(Vector2.ZERO, radius - TEXEL * 2.0, body_color.darkened(0.3))

	for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var direction := Vector2.from_angle(angle)
		draw_line(direction * radius, direction * (radius + TEXEL * 2.0), outline_color, TEXEL) # Latches

	_draw_light(Vector2.ZERO, is_blink_on(2.0, 0.15))
