class_name Thruster
extends Node2D

@export var thrust_force: float = 400.0
@export var fuel_per_second: float = 0.2 # Burned at full strength
@export var roles: Array[StringName] = []
@export var ship: RigidBody2D
@export var fx: ThrusterFX
@export var toughness: float = 1.2 # Times a standard part's points (PartHealth)

var current_strength: float = 0.0 # Highest strength requested this physics frame, in 0..1

var _health: PartHealth


func _process(delta: float) -> void:
	if fx == null:
		return

	fx.update_strength(current_strength, delta)


func reset_strength() -> void:
	current_strength = 0.0


# A damaged thruster gives less: weaker push, smaller flame, less fuel burned. Broken: nothing.
func request_thrust(strength: float) -> void:
	var performance := get_part_health().get_performance()
	current_strength = clampf(maxf(current_strength, strength * performance), 0.0, 1.0)


# --- Damage (see ShipDamage)


func get_part_health() -> PartHealth:
	if _health == null:
		_health = PartHealth.new(toughness)

	return _health


func get_part_name() -> String:
	return "%s thruster" % name


func get_hit_distance(global_point: Vector2) -> float:
	return global_position.distance_to(global_point)


# Where the wear marks go (DamageMarks), in global coordinates: on the nozzle housing, just inside the hull.
func get_damage_points() -> PackedVector2Array:
	return PackedVector2Array([to_global(Vector2(-6.0, 0.0))])


func get_fuel_needed(delta: float) -> float:
	return current_strength * fuel_per_second * delta


# Used when the tanks can't cover every request: all thrusters weaken by the same ratio.
func scale_strength(ratio: float) -> void:
	current_strength *= clampf(ratio, 0.0, 1.0)


# The push at full strength, in global coordinates, after damage. ShipComputer plans its burns with it.
func get_max_force() -> Vector2:
	var direction := -global_transform.x.normalized()
	return direction * thrust_force * get_part_health().get_performance()


func apply_thrust() -> void:
	if ship == null or current_strength <= 0.0:
		return

	var direction := -global_transform.x.normalized()
	var force := direction * thrust_force * current_strength
	ship.apply_force(force, global_position - ship.global_position)
