class_name Drill
extends HardpointWeapon

# Drill head on an articulated arm (see RobotArm for how the arm moves).
# The fire button turns it on or off.
# While on, the arm looks for the nearest reachable surface of an asteroid bigger than target_min_cells,
# in reach or nearly: it swings toward it and reaches out until the bit touches it.
# Each bite takes bite_time of contact, times the touched cell's hardness. Then a chunk around the
# touched cell (min_chunk_cells..max_chunk_cells, grown along soft rock) breaks off and drifts away
# sideways. The drill never breaks off single cells.
# Progress is stored on the cell (Asteroid.add_damage), so losing contact doesn't reset it:
# the cell remembers its damage for Asteroid.damage_memory_time.
# The bit doesn't push the asteroid: it only stops the arm from reaching through it (limit_tip).
# Chunks don't push it either: a chunk ignores the rock it came from for separation_time, so its
# jagged edge can't snag on the hole as it drifts out. A bite never takes the whole rock.
# Smoke and debris dust are rock-coloured, never ore-coloured: ore-coloured specks would look like
# ore cells flying off.

@export_group("Targeting")
@export var target_min_cells: int = 16 # "Over 15 cells". Smaller chunks are debris, not targets
@export var search_margin: float = 40.0 # Also targets asteroids this far beyond the arm's reach
@export var retarget_interval: float = 0.25
@export var nearby_margin: float = 120.0 # px past the search length. Rocks within get the bit's ray each frame; refreshed every retarget_interval
@export var scan_directions: int = 72 # Aim directions tested around the shoulder (72 = every 5°)
@export var turn_cost: float = 8.0 # px of extra distance per radian of turning, when comparing spots

@export_group("Bite")
@export var bite_time: float = 0.5 # Contact time needed to break a chunk off a soft-rock cell. Times the hardness
@export var contact_tolerance: float = 2.0 # px between the tip and a cell that still counts as contact
@export var min_chunk_cells: int = 6 # Was 2 (x3)
@export var max_chunk_cells: int = 24 # Was 8 (x3)

@export_group("Debris")
@export var eject_speed: float = 40.0 # px/s, relative to the drilled asteroid
@export var eject_min_angle_degrees: float = 30.0 # Off the surface's outward direction, to a random side
@export var eject_max_angle_degrees: float = 60.0 # Keep under 90: debris then always moves away from the rock
@export var separation_time: float = 1.5 # s the chunk and its rock don't collide, so the chunk clears the hole

@export_group("Power")
@export var power_per_second: float = 2.0 # Short on power = the arm moves but the bit doesn't cut

@export_group("Visuals")
@export var frames_per_second: float = 16.0

var is_running: bool = false
var target: Asteroid

var _target_angle: float = 0.0 # Where the arm aims to reach the target, from the last scan
var _retarget_timer: float = 0.0
var _nearby: Array[Asteroid] = [] # Rocks the bit's ray is cast against. The whole field would cost too much each frame
var _nearby_timer: float = 0.0
var _work_color: Color = Color.GRAY # Colour of the cell being cut, for the smoke
var _animation_time: float = 0.0

@onready var arm: RobotArm = $Arm
@onready var head_sprite: Sprite2D = $Arm/Head/Sprite
@onready var sparks: CPUParticles2D = $Sparks
@onready var smoke: CPUParticles2D = $Smoke


func _init() -> void:
	toughness = 2.0 # Heavy industrial arm: sturdier than a standard part


func _ready() -> void:
	arm.setup(ship)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		is_running = not is_running

	_animate(delta)


func _physics_process(delta: float) -> void:
	var has_power := is_running and draw_power(power_per_second * delta) >= 1.0
	var performance := get_performance() # Damaged: the arm moves and the bit cuts slower

	arm.speed_scale = performance

	# Off and folded: nothing to aim at or touch. Skips the ray and the pose search, the costly parts.
	# (A rock drifting onto the folded bit no longer pushes it back: the arm's hitboxes still collide.)
	if not is_running and arm.is_at_rest():
		target = null
		_update_effects(false, Vector2.ZERO, Vector2.ZERO)
		return

	arm.refresh_hull()

	if is_running:
		_update_target(delta)
	else:
		target = null

	if is_instance_valid(target):
		arm.move(delta, _target_angle, arm.max_reach)
	else:
		arm.move(delta, arm.get_rest_angle(), arm.rest_tip_distance)

	_refresh_nearby(delta)
	var forward := arm.get_direction()
	var ray_end := global_position + forward * arm.max_reach
	var hits := Asteroid.find_hits_on_ray_among(_nearby, global_position, ray_end, 1)
	var contact_distance := INF

	if not hits.is_empty():
		contact_distance = hits[0]["distance"]

	# Never past the first cell on the aim line: if an asteroid comes closer, the arm is pushed back.
	arm.limit_tip(contact_distance)

	var is_touching := contact_distance <= arm.tip_distance + contact_tolerance
	var is_working := is_touching and has_power and performance > 0.0
	var contact_point := global_position + forward * contact_distance
	_update_effects(is_working, contact_point, forward)

	if not is_working:
		return

	_work(delta * performance, hits[0])


func get_hit_distance(global_point: Vector2) -> float:
	return arm.get_hit_distance(global_point)


func get_damage_points() -> PackedVector2Array:
	return arm.get_damage_points()


# --- Targeting


func _refresh_nearby(delta: float) -> void:
	_nearby_timer -= delta

	if _nearby_timer > 0.0:
		return

	_nearby_timer = retarget_interval
	_nearby = Asteroid.find_near(get_tree(), global_position, arm.max_reach + search_margin + nearby_margin)


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


# --- Cutting


# Damage goes to the touched cell. If the asteroid spins, the bit moves on to other cells,
# and each one keeps what it already took.
func _work(delta: float, hit: Dictionary) -> void:
	var asteroid: Asteroid = hit["asteroid"]
	var cell: Vector2i = hit["cell"]
	_work_color = _get_dust_color(asteroid, cell)

	if asteroid.add_damage(cell, delta / (bite_time * asteroid.get_hardness(cell))):
		_bite(hit)


func _bite(hit: Dictionary) -> void:
	var asteroid: Asteroid = hit["asteroid"]
	var cell: Vector2i = hit["cell"]
	# At most half the rock: taking all of it would throw the whole rock at eject_speed
	# (A crumb of 1-3 cells still loses at least one)
	var size := maxi(mini(randi_range(min_chunk_cells, max_chunk_cells), asteroid.cells.size() / 2), 1)
	var part := asteroid.grow_part(cell, size, true)

	if part.is_empty():
		return
	var contact := asteroid.get_cell_global_position(cell)
	var outward := asteroid.get_outward_direction(part)
	var part_velocity := asteroid.get_velocity_at(asteroid.get_part_global_center(part))
	var velocity := part_velocity + _get_eject_direction(outward) * eject_speed

	Fx.spawn_vaporize(PackedVector2Array([contact]), get_forward(), _get_dust_color(asteroid, cell), asteroid.get_velocity_at(contact))
	var chunk := asteroid.detach_cells(part, velocity)

	if chunk != null:
		_nearby.append(chunk) # Right at the bit: the ray must see it before the next refresh
		_ignore_for_a_while(chunk, asteroid)


# One exception is enough: Godot skips the pair if either body lists the other.
func _ignore_for_a_while(chunk: Asteroid, asteroid: Asteroid) -> void:
	chunk.add_collision_exception_with(asteroid)
	await get_tree().create_timer(separation_time, false, true).timeout

	if is_instance_valid(chunk) and is_instance_valid(asteroid):
		chunk.remove_collision_exception_with(asteroid)


# The cell's rock colour. Ore (seen or not) gives the tough rock's colour, like buried ore looks.
func _get_dust_color(asteroid: Asteroid, cell: Vector2i) -> Color:
	var display_id := asteroid.get_display_id(cell)

	if CellMaterials.is_ore(display_id):
		display_id = CellMaterials.HIDDEN_ORE_LOOK

	return CellMaterials.get_material(display_id).color


# Out of the rock, tilted to a random side so the debris also clears the bit's line
# (the outward direction at the cut usually points straight back at the drill).
func _get_eject_direction(outward: Vector2) -> Vector2:
	var angle := deg_to_rad(randf_range(eject_min_angle_degrees, eject_max_angle_degrees))

	if randf() < 0.5:
		angle = -angle

	return outward.rotated(angle)


# --- Visuals


# Emitters use world coordinates (local_coords off): particles stay where they were emitted.
# Sparks spray back along the arm, smoke takes the asteroid's colour.
func _update_effects(is_working: bool, contact_point: Vector2, forward: Vector2) -> void:
	# Only on change: setting these every frame isn't free
	if sparks.emitting != is_working:
		sparks.emitting = is_working
		smoke.emitting = is_working

	if not is_working:
		return

	sparks.global_position = contact_point
	sparks.global_rotation = forward.angle() + PI
	smoke.global_position = contact_point
	var smoke_color := _work_color.lightened(0.2)

	if smoke.color != smoke_color:
		smoke.color = smoke_color


func _animate(delta: float) -> void:
	if not is_running:
		head_sprite.frame = 0
		return

	_animation_time += delta
	head_sprite.frame = int(_animation_time * frames_per_second) % head_sprite.hframes
