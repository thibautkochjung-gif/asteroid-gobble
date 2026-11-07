class_name ShipMass
extends Node

# Keeps the ship's RigidBody2D mass and centre of mass in sync with what it carries:
# hull + chunks in the smelters + smelted ore in cargo + fuel + soft points (and what they hold,
# including a rock welded on by a tether).
# Same thrust on a heavier ship = less acceleration and slower turns.
#
# Centre of mass: the average position of every part of the ship, weighted by its mass.
# Each room says where its load sits (Room.get_contents_center). Liquid ore pools at the back
# of the hold, so filling the hold drags the centre of mass backward; burning fuel shifts it too.
# Thrusters push at their own position and Godot works out the torque around the centre of mass,
# so a shifted centre of mass changes how the ship turns, with no extra code in ShipMovement.
# Soft points sit on the flanks: a heavy one on one side pulls the centre of mass sideways.
# The balance view (B, BalanceView) shows the result.

@export var ship: RigidBody2D
@export var rooms: ShipRooms
@export var soft_points: ShipSoftPoints # Optional

@export var hull_mass: float = 20.0
@export var hull_center_of_mass: Vector2 = Vector2(-10, 0) # Empty ship, in the ship's space
@export var ore_mass_per_cell: float = 0.1 # Per raw cell in the smelter, and per refined unit in cargo. Keep equal to Asteroid.mass_per_cell
@export var fuel_mass_per_unit: float = 0.05
@export var update_threshold: float = 0.05 # Skips tiny changes (fuel burns a bit every frame)
@export var center_update_threshold: float = 0.5 # px. Same idea, for the centre of mass


func _ready() -> void:
	ship.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	_update(true)


func _physics_process(_delta: float) -> void:
	_update(false)


func get_total_mass() -> float:
	var total := hull_mass

	for i in rooms.get_slot_count():
		var room := rooms.get_room(i)

		if room != null:
			total += _get_room_mass(room)

	if soft_points != null:
		total += soft_points.get_total_mass()

	return total


# Mass-weighted average of the hull and every room's load, in the ship's space.
func get_center_of_mass() -> Vector2:
	var total := hull_mass
	var weighted := hull_center_of_mass * hull_mass

	for i in rooms.get_slot_count():
		var room := rooms.get_room(i)

		if room == null:
			continue

		var mass := _get_room_mass(room)
		total += mass
		weighted += ship.to_local(room.to_global(room.get_contents_center())) * mass

	if soft_points != null:
		total += soft_points.get_total_mass()
		weighted += soft_points.get_weighted_position_sum()

	return weighted / total


# force: skip the thresholds (first frame).
func _update(force: bool) -> void:
	var total := get_total_mass()

	if force or absf(total - ship.mass) > update_threshold:
		ship.mass = total

	var center := get_center_of_mass()

	if force or center.distance_to(ship.center_of_mass) > center_update_threshold:
		ship.center_of_mass = center


func _get_room_mass(room: Room) -> float:
	if room is CargoRoom:
		return (room as CargoRoom).stored_cells * ore_mass_per_cell

	if room is SmelterRoom:
		return (room as SmelterRoom).get_cells() * ore_mass_per_cell

	if room is FuelTankRoom:
		return (room as FuelTankRoom).fuel * fuel_mass_per_unit

	return 0.0
