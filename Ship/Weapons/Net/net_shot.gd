class_name NetShot
extends Node2D

# A net in flight, fired by a NetLauncher. It flies straight on (it keeps the ship's velocity from
# the launch), opening from closed_width to the launcher's full width over open_time.
# Every frame, any free rock touching the band it swept since the last frame gets caught, whatever
# its size. The first catch starts a short close_delay, so the rocks right beside it get caught
# too; then the net closes around everything it holds (NetBundle) and tells the launcher.
# At max range, it closes on what it holds, or comes back empty.
# The cable doesn't pull in flight: a net weighs next to nothing.

signal closed(bundle: NetBundle) # null: came back empty

const CATCH_MARGIN: float = 4.0 # px. A rock this close to the net's line counts as touched

@export var closed_width: float = 20.0
@export var open_time: float = 0.6
@export var close_delay: float = 0.25
@export var rope_color: Color = Color(0.83, 0.64, 0.16)
@export var weight_color: Color = Color(0.31, 0.3, 0.31)

var velocity: Vector2 = Vector2.ZERO
var full_width: float = 400.0
var max_range: float = 450.0

var caught: Array[Asteroid] = []

var _travelled: float = 0.0
var _age: float = 0.0
var _close_timer: float = -1.0 # Counts down once something is caught
var _last_left: Vector2
var _last_right: Vector2
var _is_done: bool = false


func _ready() -> void:
	z_index = 2
	_update_ends()


func _physics_process(delta: float) -> void:
	if _is_done:
		return

	_age += delta
	var step := velocity * delta
	global_position += step
	_travelled += step.length()

	var previous_left := _last_left
	var previous_right := _last_right
	_update_ends()
	_catch_in(PackedVector2Array([previous_left, previous_right, _last_right, _last_left]))

	if _close_timer >= 0.0:
		_close_timer -= delta

		if _close_timer < 0.0:
			_close()
			return

	if _travelled >= max_range:
		_close()

	queue_redraw()


func get_width() -> float:
	return lerpf(closed_width, full_width, clampf(_age / open_time, 0.0, 1.0))


# Closes now, on whatever it holds. The launcher calls it when the player presses fire mid-flight.
func close_now() -> void:
	if not _is_done:
		_close()


func _update_ends() -> void:
	var side := velocity.normalized().orthogonal() * get_width() * 0.5
	_last_left = global_position - side
	_last_right = global_position + side


func _catch_in(band: PackedVector2Array) -> void:
	var center := global_position
	var reach := get_width() * 0.5 + velocity.length() * 0.05 + CATCH_MARGIN

	for rock in Asteroid.find_near(get_tree(), center, reach):
		if rock.freeze or caught.has(rock):
			continue

		var on_line := Geometry2D.get_closest_point_to_segment(rock.get_global_center(), _last_left, _last_right)
		var surface := rock.get_closest_point(on_line)
		var is_touched := surface.distance_to(Geometry2D.get_closest_point_to_segment(surface, _last_left, _last_right)) <= CATCH_MARGIN

		if is_touched or Geometry2D.is_point_in_polygon(surface, band):
			caught.append(rock)

			if _close_timer < 0.0:
				_close_timer = close_delay


func _close() -> void:
	_is_done = true
	var alive: Array[Asteroid] = []

	for rock in caught:
		if is_instance_valid(rock) and not rock.cells.is_empty() and not rock.freeze and rock.is_in_group(Asteroid.GROUP):
			alive.append(rock)

	var bundle: NetBundle = null

	if not alive.is_empty():
		bundle = NetBundle.wrap(alive, alive[0].get_parent() as Node2D, _get_global_edge())

	closed.emit(bundle)
	queue_free()


# The net's rope as it flies, local: a sag between the two weights.
func _get_edge() -> PackedVector2Array:
	var side := velocity.normalized().orthogonal() * get_width() * 0.5
	var sag := -velocity.normalized() * 6.0
	var edge := PackedVector2Array()

	for i in 9:
		var t := i / 8.0
		edge.append((-side).lerp(side, t) + sag * sin(t * PI))

	return edge


func _get_global_edge() -> PackedVector2Array:
	var edge := PackedVector2Array()

	for point in _get_edge():
		edge.append(global_position + point)

	return edge


# The net's leading edge: a sagging rope between two weights, and a mesh trailing behind it.
func _draw() -> void:
	var side := velocity.normalized().orthogonal() * get_width() * 0.5
	var back := -velocity.normalized() * 10.0
	var left := -side
	var right := side
	var edge := _get_edge()

	for i in range(0, 9, 2):
		draw_line(edge[i], back * 1.6, Color(rope_color, 0.5), 1.0)

	draw_polyline(edge, rope_color, 1.5)

	for end in [left, right]:
		draw_rect(Rect2(end - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), weight_color)
