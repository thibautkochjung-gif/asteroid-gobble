class_name Hangar
extends Node2D

# The saloon-style hangar doors at the nose, and the intake behind them.
# toggle_hangar opens or closes the doors. Each leaf swings outward around its hinge;
# fully open, the two leaves form a funnel that guides chunks into the mouth.
# The hold is the space behind the doors (the intake area). A chunk is in the hold as soon as any
# part of it is: like a woodchipper, a chunk can be half in, half out.
# A chunk in the hold is handed to the first room that can take it (ShipRooms.find_receiver_for):
# the smelter or the ore bin. That goes on with the doors closed too.
# Never a chunk the grinder is about to throw out (Grinder.should_discard): triage comes first.
# A chunk too big for every such room waits until the Grinder cuts it down.
# Nothing here assumes a smelter: with no room taking chunks, they just wait in the hold.
# Chunks too wide for the mouth can't get in: the hull collision has a notch the width of the doorway.
# This node sits at the ship's origin, so its local space is the ship's space.

signal door_toggled(is_open: bool)

@export_group("Nodes")
@export var ship: RigidBody2D
@export var rooms: ShipRooms
@export var intake: Area2D
@export var left_door_collision: CollisionShape2D # Rectangle as long as doorway_half_width
@export var right_door_collision: CollisionShape2D

@export_group("Doors")
@export var door_line_x: float = 90.0 # The hinges sit on this line
@export var doorway_half_width: float = 16.0 # Also the length of each leaf
@export var open_angle_degrees: float = 135.0 # How far each leaf swings out. 135 = 45° funnel
@export var door_open_time: float = 0.5
@export var leaf_thickness: float = 4.0
@export var toughness: float = 25.0 # Times a standard part's points (PartHealth). Thick armoured leaves

@export_group("Intake")
@export var max_chunk_cells: int = 80 # Safety net on top of the doorway width

@export_group("Visuals")
@export var door_color: Color = Color(0.85, 0.64, 0.14)
@export var door_stripe_color: Color = Color(0.11, 0.11, 0.12)

var is_open: bool = false
var grinder: Grinder # Set by the grinder, if the ship has one
var open_amount: float = 0.0 # 0 closed, 1 fully open

var _health: PartHealth


func _ready() -> void:
	_update_leaves()


# Broken doors are jammed: the key does nothing, the leaves stay where they are.
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_hangar") and not is_jammed():
		is_open = not is_open
		door_toggled.emit(is_open)


func _physics_process(delta: float) -> void:
	var target := 1.0 if is_open else 0.0
	var performance := get_part_health().get_performance() # Damaged: the leaves swing slower

	if open_amount != target and performance > 0.0:
		open_amount = move_toward(open_amount, target, delta / door_open_time * performance)
		_update_leaves()
		queue_redraw()

	_capture_chunks()


func _draw() -> void:
	_draw_leaf(-1.0)
	_draw_leaf(1.0)


# --- Damage (see ShipDamage). The doors are the part; the hold behind them takes no damage.


func get_part_health() -> PartHealth:
	if _health == null:
		_health = PartHealth.new(toughness)

	return _health


func get_part_name() -> String:
	return "Hangar doors"


func is_jammed() -> bool:
	return get_part_health().is_broken()


# Shortest distance to either leaf.
func get_hit_distance(global_point: Vector2) -> float:
	var local := to_local(global_point)
	var best := INF

	for side in [-1.0, 1.0]:
		var hinge := _get_hinge(side)
		var leaf_end := hinge + Vector2.from_angle(_get_leaf_angle(side)) * doorway_half_width
		var closest := Geometry2D.get_closest_point_to_segment(local, hinge, leaf_end)
		best = minf(best, closest.distance_to(local))

	return best


# Where the wear marks go (DamageMarks), in global coordinates: the middle of each leaf.
func get_damage_points() -> PackedVector2Array:
	var points := PackedVector2Array()

	for side in [-1.0, 1.0]:
		var leaf_middle := _get_hinge(side) + Vector2.from_angle(_get_leaf_angle(side)) * doorway_half_width * 0.5
		points.append(to_global(leaf_middle))

	return points


# Chunks in the hold: any part of them inside the intake area (behind the door line).
func get_chunks_inside() -> Array[Asteroid]:
	var inside: Array[Asteroid] = []

	for body in intake.get_overlapping_bodies():
		var chunk := body as Asteroid

		if chunk != null and chunk.is_in_group(Asteroid.GROUP):
			inside.append(chunk)

	return inside


# The hold (the intake area), in this node's space, which is the ship's space.
func get_hold_rect() -> Rect2:
	for child in intake.get_children():
		var collision := child as CollisionShape2D

		if collision == null:
			continue

		var rectangle := collision.shape as RectangleShape2D

		if rectangle != null:
			var center := intake.position + collision.position

			return Rect2(center - rectangle.size * 0.5, rectangle.size)

	return Rect2()


# Too big for every room that takes chunks, even empty: it has to be ground down first.
# With no such room there's nothing to measure against, so nothing is too big.
func is_too_big(chunk: Asteroid) -> bool:
	if not rooms.has_chunk_receivers():
		return false

	return chunk.cells.size() > max_chunk_cells or not rooms.can_any_receiver_fit(chunk)


func _capture_chunks() -> void:
	for chunk in get_chunks_inside():
		if chunk.cells.size() > max_chunk_cells:
			continue

		if grinder != null and grinder.should_discard(chunk):
			continue

		var receiver := rooms.find_receiver_for(chunk)

		# The chunk is freed at the end of the frame: its mass and velocity can still be read.
		if receiver != null and receiver.receive_chunk(chunk):
			_absorb_momentum(chunk)


# The chunk becomes part of the ship's load, so from now on they move as one: momentum is
# conserved (a perfectly inelastic catch). Without this, a chunk caught while moving would take
# its momentum away with it, and the ship would keep drifting from the pushes the chunk gave it.
# ShipMass adds the chunk's mass to the ship on the next frame.
func _absorb_momentum(chunk: Asteroid) -> void:
	var total_mass := ship.mass + chunk.mass
	ship.linear_velocity = (ship.linear_velocity * ship.mass + chunk.linear_velocity * chunk.mass) / total_mass


# side: -1 for the left leaf (hinge at negative y), +1 for the right leaf.
func _get_hinge(side: float) -> Vector2:
	return Vector2(door_line_x, doorway_half_width * side)


# Closed, a leaf points at the doorway's centre. Opening swings it through the front, outward.
func _get_leaf_angle(side: float) -> float:
	var closed_angle := -side * PI * 0.5
	return closed_angle + side * deg_to_rad(open_angle_degrees) * open_amount


func _update_leaves() -> void:
	_place_leaf_collision(left_door_collision, -1.0)
	_place_leaf_collision(right_door_collision, 1.0)


# The shape is centred on the leaf, so it sits half a leaf away from the hinge.
func _place_leaf_collision(collision: CollisionShape2D, side: float) -> void:
	var angle := _get_leaf_angle(side)
	collision.position = _get_hinge(side) + Vector2.from_angle(angle) * doorway_half_width * 0.5
	collision.rotation = angle


func _draw_leaf(side: float) -> void:
	var half_thickness := leaf_thickness * 0.5
	draw_set_transform(_get_hinge(side), _get_leaf_angle(side))
	draw_rect(Rect2(0.0, -half_thickness, doorway_half_width, leaf_thickness), door_color)

	var x := 4.0

	while x < doorway_half_width:
		var stripe_length := minf(4.0, doorway_half_width - x)
		draw_rect(Rect2(x, -half_thickness, stripe_length, leaf_thickness), door_stripe_color)
		x += 8.0

	draw_set_transform(Vector2.ZERO)
