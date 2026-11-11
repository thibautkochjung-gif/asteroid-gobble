class_name HarpoonWinch
extends SoftPoint

# Fires a harpoon on a cable, outward from the mount. It sticks in the first rock cell or prop on
# its path. Then the cable is a rope: slack until it's stretched, then it pulls both ends.
# - tap: fire. Tap again (hooked or flying): let go, and the winch takes the harpoon back.
# - hold, while hooked: reel in. The rope shortens and pulls the catch toward the ship, and the ship
#   toward the catch. Mounted on a side, a heavy catch also turns the ship.
# The hook follows its cell when the rock is cut (BodyAnchor). If the cell is destroyed, it comes
# loose. Hooking a prop (a beacon, a lost module...) and reeling it in brings it home: it's taken
# back when it touches the hull.
# The cable snaps over break_force.

enum State { STOWED, FLYING, HOOKED, RETRACTING }

@export var shot_speed: float = 260.0 # px/s, relative to the ship
@export var max_length: float = 240.0 # The harpoon comes back if it flies this far without a hit
@export var min_length: float = 14.0 # Reeling in stops here
@export var reel_speed: float = 45.0 # px/s
@export var reel_power_per_second: float = 3.0
@export var retract_speed: float = 320.0 # px/s, relative to the ship, when the winch takes the harpoon back
@export var stiffness: float = 30.0 # 1/s². See SoftLink
@export var damping: float = 8.0 # 1/s
@export var break_force: float = 40000.0 # mass * px/s²
@export var head_mass: float = 0.2 # For the recoil when firing

@export_group("Look")
@export var tube_color: Color = Color(0.31, 0.3, 0.31)
@export var cable_color: Color = Color(0.72, 0.68, 0.6)
@export var head_color: Color = Color(0.83, 0.85, 0.88)

var state: State = State.STOWED
var anchor: BodyAnchor
var rope_length: float = 0.0
var is_reeling: bool = false

var _head_position: Vector2 # Global
var _head_velocity: Vector2
var _is_hooked_on_prop: bool = false # A prop that gets taken back aboard frees itself: the hook isn't "lost"


func _init() -> void:
	footprint = Rect2(0, -7, 12, 14)
	dry_mass = 2.0


func _physics_process(delta: float) -> void:
	if ship == null:
		return

	match state:
		State.FLYING:
			_fly(delta)
		State.HOOKED:
			_pull(delta)
		State.RETRACTING:
			_retract(delta)

	if state != State.STOWED:
		queue_redraw()


func get_status_text() -> String:
	match state:
		State.FLYING:
			return "flying"
		State.HOOKED:
			return "hooked, %d px of cable" % rope_length
		State.RETRACTING:
			return "winding back"

	return "ready"


func is_engaged() -> bool:
	return state != State.STOWED


func get_controls_text() -> String:
	match state:
		State.STOWED:
			return "tap: fire"
		State.HOOKED:
			return "tap: let go  hold: reel in"

	return "tap: let go"


func get_aim_speed() -> float:
	return shot_speed if state == State.STOWED else 0.0


func get_aim_range() -> float:
	return max_length


# Same test as the flying harpoon: frozen rocks are skipped, props count.
func find_aim_hit(from: Vector2, to: Vector2) -> Dictionary:
	return _find_hit(from, to)


func _on_tap() -> void:
	match state:
		State.STOWED:
			_fire()
		State.FLYING, State.HOOKED:
			_let_go("")


func _on_hold_started() -> void:
	is_reeling = state == State.HOOKED


func _on_hold_ended() -> void:
	is_reeling = false


func _on_detached() -> void:
	state = State.STOWED
	anchor = null
	is_reeling = false


# --- States


func _fire() -> void:
	var outward := get_outward()
	_head_position = get_tip()
	_head_velocity = get_ship_velocity_at(_head_position) + outward * shot_speed
	ship.apply_impulse(-outward * shot_speed * head_mass, _head_position - ship.global_position)
	state = State.FLYING


func _fly(delta: float) -> void:
	var from := _head_position
	var to := from + _head_velocity * delta
	var hit := _find_hit(from, to)

	if not hit.is_empty():
		var body: RigidBody2D = hit["body"]
		var point: Vector2 = hit["point"]
		anchor = BodyAnchor.on_body(body, point)
		_is_hooked_on_prop = body is SpaceProp
		_head_position = point
		rope_length = maxf(get_tip().distance_to(point), min_length)
		state = State.HOOKED
		say("Harpoon: hooked")
		return

	_head_position = to

	if get_tip().distance_to(_head_position) > max_length:
		state = State.RETRACTING


func _pull(delta: float) -> void:
	if not anchor.resolve(get_tree()):
		_let_go("Harpoon: catch brought aboard" if _is_hooked_on_prop else "Harpoon: the hook came loose")
		return

	_head_position = anchor.get_global_position()

	if is_reeling and rope_length > min_length:
		var ratio := draw_ship_power(reel_power_per_second * delta)
		rope_length = maxf(rope_length - reel_speed * delta * ratio, min_length)

	var force := SoftLink.apply_spring(ship, get_tip(), anchor.body, _head_position, rope_length, stiffness, damping, true)

	if force > break_force:
		_let_go("Harpoon: the cable snapped!")


# The winch pulls the harpoon back in a straight line, relative to the ship.
func _retract(delta: float) -> void:
	var tip := get_tip()
	_head_position += get_ship_velocity_at(_head_position) * delta
	_head_position = _head_position.move_toward(tip, retract_speed * delta)

	if _head_position.distance_to(tip) < 1.0:
		state = State.STOWED


func _let_go(text: String) -> void:
	anchor = null
	is_reeling = false
	state = State.RETRACTING

	if not text.is_empty():
		say(text)


# Nearest thing on the segment: a rock cell, or a prop. {} if none.
# Frozen rocks (welded to a ship, held by a buoy) are skipped: pulling on them does nothing.
func _find_hit(from: Vector2, to: Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	var direction := (to - from).normalized()

	for cell_hit in Asteroid.find_hits_on_ray(get_tree(), from, to, 8):
		var rock: Asteroid = cell_hit["asteroid"]

		if rock.freeze:
			continue

		best_distance = cell_hit["distance"]
		best = { "body": rock, "point": from + direction * best_distance }
		break

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		var prop := node as SpaceProp

		if prop == null or prop.freeze:
			continue

		var nearest := SoftLink.distance_to_segment(prop.global_position, from, to)

		if nearest.x > prop.radius:
			continue

		var distance := nearest.y * from.distance_to(to)

		if distance < best_distance:
			best_distance = distance
			best = { "body": prop, "point": prop.global_position }

	return best


# --- Look


func _draw_module() -> void:
	_draw_plate(footprint, tube_color)

	var center_y := footprint.get_center().y
	var tube := Rect2(footprint.position.x + TEXEL, center_y - TEXEL * 1.5, footprint.size.x - TEXEL, TEXEL * 3.0)
	draw_rect(tube, outline_color)

	var tip := Vector2(footprint.end.x, center_y)

	if state == State.STOWED:
		_draw_head(tip, Vector2.RIGHT)
		return

	var head := to_local(_head_position)
	draw_line(tip, head, outline_color, TEXEL)
	draw_line(tip, head, cable_color, TEXEL * 0.5)
	_draw_head(head, (head - tip).normalized() if head != tip else Vector2.RIGHT)


func _draw_head(at: Vector2, direction: Vector2) -> void:
	var side := direction.orthogonal() * TEXEL * 1.5
	var back := at - direction * TEXEL * 4.0
	draw_colored_polygon(PackedVector2Array([at + direction * TEXEL, back + side, back - side]), head_color)
	draw_line(back, at - direction * TEXEL * 6.0, head_color, TEXEL)
