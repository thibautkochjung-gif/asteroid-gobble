class_name Thruster
extends Node2D

@export var thrust_force: float = 400.0
@export var fuel_per_second: float = 0.2 # Burned at full strength
@export var roles: Array[StringName] = []
@export var ship: RigidBody2D
@export var fx: ThrusterFX

var current_strength: float = 0.0 # Highest strength requested this physics frame, in 0..1


func _process(delta: float) -> void:
	if fx == null:
		return

	fx.update_strength(current_strength, delta)


func reset_strength() -> void:
	current_strength = 0.0


func request_thrust(strength: float) -> void:
	current_strength = clampf(maxf(current_strength, strength), 0.0, 1.0)


func get_fuel_needed(delta: float) -> float:
	return current_strength * fuel_per_second * delta


# Used when the tanks can't cover every request: all thrusters weaken by the same ratio.
func scale_strength(ratio: float) -> void:
	current_strength *= clampf(ratio, 0.0, 1.0)


func apply_thrust() -> void:
	if ship == null or current_strength <= 0.0:
		return

	var direction := -global_transform.x.normalized()
	var force := direction * thrust_force * current_strength
	ship.apply_force(force, global_position - ship.global_position)
