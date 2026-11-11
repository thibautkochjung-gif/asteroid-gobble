class_name HydraulicSplitter
extends HardpointWeapon

# Hydraulic wedge on an articulated arm (see RobotArm for how the arm moves).
# The fire button turns it on or off, like the drill.
# While on, the arm looks for the nearest reachable rock of at least target_min_cells, reaches out
# and plants the wedge on its surface. The ram then drives it in. After split_time of contact the
# rock cracks in two: the crack starts at the wedge, heads along it, and follows the weakest rock
# on its way across (RockFracture). The halves drift apart.
# Split time grows with the square root of the rock's cell count: a rock four times bigger takes
# twice as long. Never less than min_split_time.
# The ram pushes the ship backward (not the rock). Thrust against it or bolt the ship to the
# rock, or the ship drifts out of the arm's reach and the wedge slips out.
# Progress stays with the rock for progress_memory_time: come back in time and it carries on.
# While on, it keeps working: once a rock is split, it moves on to the nearest piece big enough.

@export_group("Targeting")
@export var target_min_cells: int = 40 # Smaller rocks aren't worth a split: drill or grab them
@export var search_margin: float = 40.0 # Also targets rocks this far beyond the arm's reach
@export var retarget_interval: float = 0.25
@export var scan_directions: int = 72 # Aim directions tested around the shoulder (72 = every 5°)
@export var turn_cost: float = 8.0 # px of extra distance per radian of turning, when comparing spots
@export var contact_tolerance: float = 3.0 # px between the wedge's tip and the rock that still counts as contact

@export_group("Split")
@export var base_split_time: float = 3.0 # s for a rock of reference_cells
@export var reference_cells: int = 1000
@export var min_split_time: float = 1.0
@export var progress_memory_time: float = 5.0 # s without contact before the progress is lost
@export var separation_speed: float = 12.0 # px/s between the two halves
@export var cooldown_time: float = 1.5 # Pause after a split, before looking for the next rock

@export_group("Ram")
@export var push_force: float = 40.0 # mass * px/s², backward on the ship. Ship ≈ 26 mass
@export var power_per_second: float = 2.5 # Short on power: the arm moves but the ram doesn't drive

@export_group("Look")
@export var shake_amount: float = 0.6 # px the wedge shakes while driving
@export var crack_color: Color = Color(0.06, 0.055, 0.07)
@export var crack_length: float = 24.0 # px the crack mark grows ahead of the wedge, at full progress

var is_running: bool = false
var target: Asteroid
var progress: float = 0.0 # 0..1 on progress_rock
var progress_rock: Asteroid

var _target_angle: float = 0.0 # Where the arm aims to reach the target, from the last scan
var _retarget_timer: float = 0.0
var _memory_left: float = 0.0
var _cooldown: float = 0.0
var _is_driving: bool = false
var _contact_point: Vector2 # Global, while driving
var _rng := RandomNumberGenerator.new()

@onready var arm: RobotArm = $Arm
@onready var head_look: Node2D = $Arm/Head/Look
@onready var dust: CPUParticles2D = $Dust


func _init() -> void:
	toughness = 2.0 # Heavy industrial arm, like the drill's


func _ready() -> void:
	arm.setup(ship)
	_rng.randomize()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		is_running = not is_running

	head_look.position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * shake_amount if _is_driving else Vector2.ZERO
	queue_redraw()


func _physics_process(delta: float) -> void:
	var performance := get_performance()
	arm.speed_scale = performance
	_cooldown = maxf(_cooldown - delta, 0.0)
	_forget_progress(delta)

	if not is_running and arm.is_at_rest():
		_set_driving(false)
		target = null
		return

	arm.refresh_hull()

	if is_running and _cooldown <= 0.0:
		_update_target(delta)
	else:
		target = null

	if is_instance_valid(target):
		arm.move(delta, _target_angle, arm.max_reach)
	else:
		arm.move(delta, arm.get_rest_angle(), arm.rest_tip_distance)

	var forward := arm.get_direction()
	var hits := Asteroid.find_hits_on_ray(get_tree(), global_position, global_position + forward * arm.max_reach, 1)
	var contact_distance := INF

	if not hits.is_empty():
		contact_distance = hits[0]["distance"]

	arm.limit_tip(contact_distance) # The wedge doesn't go through rock: the ram does that

	var is_touching := contact_distance <= arm.tip_distance + contact_tolerance
	var has_power := is_running and _cooldown <= 0.0 and draw_power(power_per_second * delta) >= 1.0
	var is_big_enough := false

	if is_touching:
		var touched: Asteroid = hits[0]["asteroid"]
		is_big_enough = touched.cells.size() >= target_min_cells

	var is_working := is_big_enough and has_power and performance > 0.0
	_set_driving(is_working)

	if not is_working:
		return

	_contact_point = global_position + forward * contact_distance
	_drive(delta * performance, hits[0], forward)


func get_button_title() -> String:
	return "SPLITTER"


func get_cooldown_ratio() -> float:
	return _cooldown / cooldown_time if cooldown_time > 0.0 else 0.0


func get_hit_distance(global_point: Vector2) -> float:
	return arm.get_hit_distance(global_point)


func get_damage_points() -> PackedVector2Array:
	return arm.get_damage_points()


# A rock four times bigger takes twice as long.
func get_split_time(rock: Asteroid) -> float:
	return maxf(base_split_time * sqrt(float(rock.cells.size()) / reference_cells), min_split_time)


# --- Targeting (same search as the drill)


func _update_target(delta: float) -> void:
	_retarget_timer -= delta

	if _retarget_timer > 0.0 and is_instance_valid(target):
		return

	_retarget_timer = retarget_interval
	target = null

	var search_length := arm.max_reach + search_margin
	var candidates: Array[Asteroid] = []

	for asteroid in Asteroid.find_near(get_tree(), global_position, search_length):
		if asteroid.cells.size() < target_min_cells:
			continue

		if global_position.distance_to(asteroid.get_closest_point(global_position)) <= search_length:
			candidates.append(asteroid)

	if candidates.is_empty():
		return

	var found := arm.find_reachable(candidates, search_length, scan_directions, turn_cost)

	if not found.is_empty():
		target = found["asteroid"]
		_target_angle = found["angle"]


# --- Splitting


func _drive(delta: float, hit: Dictionary, forward: Vector2) -> void:
	var rock: Asteroid = hit["asteroid"]

	if rock != progress_rock:
		progress_rock = rock
		progress = 0.0

	_memory_left = progress_memory_time
	progress += delta / get_split_time(rock)

	# The ram pushes the ship back; the rock stays where it is. A rock welded to a ship is frozen:
	# the push would only shove the ship against itself, so nothing happens.
	if not rock.freeze:
		ship.apply_force(-forward * push_force, _contact_point - ship.global_position)

	if progress >= 1.0:
		_split(rock, hit["cell"], forward)


func _split(rock: Asteroid, start: Vector2i, forward: Vector2) -> void:
	var direction := rock.global_transform.basis_xform_inv(forward).normalized() # Cells are laid out in the rock's own space
	var crack := RockFracture.trace(rock, start, direction, _rng)
	var points := RockFracture.get_points(rock, crack)
	var dust_color := rock.get_cell_color(start)
	var old_center := rock.get_global_center()
	var old_velocity := rock.linear_velocity
	var old_spin := rock.angular_velocity

	progress = 0.0
	progress_rock = null
	target = null
	_cooldown = cooldown_time
	_set_driving(false)

	var pieces := rock.split_along(crack)
	Fx.spawn_vaporize(points, forward.orthogonal(), dust_color, old_velocity)
	Fx.shake(0.35)

	if pieces.is_empty():
		message.emit("cracked, not split") # A thin bridge left somewhere: the next push finishes it
		return

	pieces.append(rock)
	_push_apart(pieces, forward.orthogonal(), old_center, old_velocity, old_spin)
	message.emit("rock split")


# Each piece keeps the motion it had as part of the rock, plus a push away from the crack line.
# Lighter pieces move more, so the pair's momentum doesn't change.
func _push_apart(pieces: Array[Asteroid], across: Vector2, old_center: Vector2, old_velocity: Vector2, old_spin: float) -> void:
	var total_mass := 0.0

	for piece in pieces:
		total_mass += piece.cells.size() * piece.mass_per_cell

	for piece in pieces:
		if not is_instance_valid(piece) or piece.cells.is_empty() or piece.freeze:
			continue

		var center := piece.get_global_center()
		var offset := center - old_center
		var carried := old_velocity + Vector2(-old_spin * offset.y, old_spin * offset.x)
		var side := signf((center - _contact_point).dot(across))
		var piece_mass := piece.cells.size() * piece.mass_per_cell
		var share := 1.0 - piece_mass / total_mass if total_mass > 0.0 else 0.5
		piece.linear_velocity = carried + across * side * separation_speed * share
		piece.angular_velocity = old_spin


func _forget_progress(delta: float) -> void:
	if progress_rock == null or _is_driving:
		return

	_memory_left -= delta

	if _memory_left <= 0.0 or not is_instance_valid(progress_rock):
		progress = 0.0
		progress_rock = null


func _set_driving(value: bool) -> void:
	_is_driving = value
	dust.emitting = value

	if value:
		dust.global_position = _contact_point


# --- Look


# A dark crack growing ahead of the wedge as the ram drives in.
func _draw() -> void:
	if not _is_driving or progress <= 0.0:
		return

	var from := to_local(_contact_point)
	var forward := arm.get_direction().rotated(-global_rotation)
	var to := from + forward * crack_length * progress
	draw_line(from, to, crack_color, 2.0)
