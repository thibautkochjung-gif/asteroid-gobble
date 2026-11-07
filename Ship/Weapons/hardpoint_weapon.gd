class_name HardpointWeapon
extends Node2D

# Base class for every swappable hardpoint weapon.
# ShipHardpoints sets weapon_type, fire_action, ship, power_source and hangar before add_child(),
# so one weapon scene works on any slot and any mouse button.
# Every weapon scene needs a Muzzle (Marker2D), anywhere in the scene: where the shot leaves from,
# or the drill's tip.

@warning_ignore("unused_signal") # Emitted by the subclasses
signal cooldown_blocked(time_left: float)

enum Type { LASER, DRILL, PROJECTILE_LAUNCHER, GRABBER, PLASMA_GUN } # New types go at the end: scenes store them as numbers

const TYPE_NAMES := {
	Type.LASER: "Laser",
	Type.DRILL: "Drill",
	Type.PROJECTILE_LAUNCHER: "Projectile launcher",
	Type.GRABBER: "Grabber",
	Type.PLASMA_GUN: "Plasma gun",
}

var weapon_type: Type = Type.LASER # Set by ShipHardpoints
var fire_action: StringName # Set by ShipHardpoints
var ship: RigidBody2D # Set by ShipHardpoints
var power_source: Generator # Set by ShipHardpoints. null = free to use
var hangar: Hangar # Set by ShipHardpoints

@onready var muzzle: Marker2D = find_child("Muzzle") as Marker2D


# Returns the share of the needed power the generator could give, 0..1.
func draw_power(amount: float) -> float:
	if power_source == null or amount <= 0.0:
		return 1.0

	return power_source.draw_power(amount) / amount


func get_forward() -> Vector2:
	return muzzle.global_transform.x.normalized()


# Velocity of the ship's material at a global point: linear + the part due to its spin.
# Things launched or thrown from the ship start with it, so they keep the ship's inertia.
func get_ship_velocity_at(global_point: Vector2) -> Vector2:
	if ship == null:
		return Vector2.ZERO

	var offset := global_point - ship.to_global(ship.center_of_mass)
	return ship.linear_velocity + Vector2(-ship.angular_velocity * offset.y, ship.angular_velocity * offset.x)
