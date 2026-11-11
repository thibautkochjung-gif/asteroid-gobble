class_name HardpointWeapon
extends Node2D

# Base class for every swappable hardpoint weapon.
# ShipHardpoints sets weapon_type, fire_action, ship, power_source and hangar before add_child(),
# so one weapon scene works on any slot and any mouse button.
# Every weapon scene needs a Muzzle (Marker2D), anywhere in the scene: where the shot leaves from,
# or the drill's tip.

@warning_ignore("unused_signal") # Emitted by the subclasses
signal cooldown_blocked(time_left: float)
@warning_ignore("unused_signal") # Emitted by the subclasses
signal message(text: String) # A short line for the cockpit's terminal ("reloading", "out of ammo")

enum Type {
	LASER,
	DRILL,
	PROJECTILE_LAUNCHER,
	GRABBER,
	PLASMA_GUN,
	NET_LAUNCHER,
	SCANNER,
	PRECISION_SCANNER,
	HYDRAULIC_SPLITTER,
	TRACTOR_BEAM,
	HEAVY_TRACTOR_BEAM,
	SMART_TRACTOR_BEAM,
	BREACHING_LANCE,
} # New types go at the end: scenes store them as numbers

const TYPE_NAMES := {
	Type.LASER: "Laser",
	Type.DRILL: "Drill",
	Type.PROJECTILE_LAUNCHER: "Projectile launcher",
	Type.GRABBER: "Grabber",
	Type.PLASMA_GUN: "Plasma gun",
	Type.NET_LAUNCHER: "Net launcher",
	Type.SCANNER: "Scanner",
	Type.PRECISION_SCANNER: "Precision scanner",
	Type.HYDRAULIC_SPLITTER: "Hydraulic splitter",
	Type.TRACTOR_BEAM: "Tractor beam",
	Type.HEAVY_TRACTOR_BEAM: "Heavy tractor beam",
	Type.SMART_TRACTOR_BEAM: "Smart tractor beam",
	Type.BREACHING_LANCE: "Breaching lance",
}

# Shared by every weapon that has a second function (tractor push/pull, net tow).
const MODE_ACTION: StringName = &"hardpoint_mode"
const TOW_ACTION: StringName = &"net_tow"

@export_group("Aiming")
@export var aim_arc_degrees: float = 0.0 # Whole arc the mouse can aim in, centred on the slot's axis. 0 = fixed
@export var aim_speed_degrees: float = 120.0 # How fast the weapon turns toward the mouse, degrees per second

var weapon_type: Type = Type.LASER # Set by ShipHardpoints
var fire_action: StringName # Set by ShipHardpoints
var ship: RigidBody2D # Set by ShipHardpoints
var power_source: Generator # Set by ShipHardpoints. null = free to use
var hangar: Hangar # Set by ShipHardpoints
var ammo_source: ShipHardpoints # Set by ShipHardpoints. null = unlimited ammo (test scenes)
var toughness: float = 1.0 # Times a standard part's points (PartHealth). Sturdier weapons raise it in _init()
var is_damage_proof: bool = true # Impacts don't wear hard points. Only the ship's destruction breaks them

var _health: PartHealth

@onready var muzzle: Marker2D = find_child("Muzzle") as Marker2D


# Returns the share of the needed power the generator could give, 0..1.
func draw_power(amount: float) -> float:
	if power_source == null or amount <= 0.0:
		return 1.0

	return power_source.draw_power(amount) / amount


# --- Damage (see ShipDamage)


func get_part_health() -> PartHealth:
	if _health == null:
		_health = PartHealth.new(toughness)
		_health.is_invulnerable = is_damage_proof

	return _health


func get_part_name() -> String:
	return TYPE_NAMES[weapon_type]


# What the cockpit's button shows. Weapons with a mode or a stock override it ("TRACTOR PUSH").
func get_button_title() -> String:
	return get_part_name()


# Station service, after ShipHardpoints.restock_ammo(). For weapons with their own stock (lances).
func restock() -> void:
	pass


# 1 = just fired, 0 = ready to fire. Weapons without a cooldown keep this default.
func get_cooldown_ratio() -> float:
	return 0.0


# --- Ammo. Weapons that don't use any keep these defaults.


# Rounds inside the weapon (its magazine), already taken out of the ship's storage.
func get_loaded_ammo() -> int:
	return 0


func get_magazine_size() -> int:
	return 0


# Empty and nothing left to reload from: the cockpit greys the button out.
func is_out_of_ammo() -> bool:
	return false


# What each weapon multiplies its output by: 0 when broken.
func get_performance() -> float:
	return get_part_health().get_performance()


# Shortest distance to the line from the mount to the muzzle. Arm weapons use their links instead.
func get_hit_distance(global_point: Vector2) -> float:
	var closest := Geometry2D.get_closest_point_to_segment(global_point, global_position, muzzle.global_position)
	return closest.distance_to(global_point)


# Where the wear marks go (DamageMarks), in global coordinates: halfway along the barrel. Arm weapons use their joints instead.
func get_damage_points() -> PackedVector2Array:
	return PackedVector2Array([global_position.lerp(muzzle.global_position, 0.5)])


func get_forward() -> Vector2:
	return muzzle.global_transform.x.normalized()


# --- Mouse aiming. The weapon node itself turns inside its slot, so the sprite, the muzzle and
# the beam all follow. Rotation 0 is the slot's axis.


# Turns toward the mouse, stopping at the edge of the arc.
func update_aim(delta: float) -> void:
	if aim_arc_degrees <= 0.0:
		return

	var slot := get_parent() as Node2D
	var to_mouse := slot.to_local(get_global_mouse_position()) - position
	var half_arc := deg_to_rad(aim_arc_degrees) / 2.0
	_turn_toward(clampf(to_mouse.angle(), -half_arc, half_arc), delta)


# Swings back to the slot's axis.
func reset_aim(delta: float) -> void:
	_turn_toward(0.0, delta)


func _turn_toward(target_angle: float, delta: float) -> void:
	rotation = rotate_toward(rotation, target_angle, deg_to_rad(aim_speed_degrees) * delta)


# Velocity of the ship's material at a global point: linear + the part due to its spin.
# Things launched or thrown from the ship start with it, so they keep the ship's inertia.
func get_ship_velocity_at(global_point: Vector2) -> Vector2:
	if ship == null:
		return Vector2.ZERO

	var offset := global_point - ship.to_global(ship.center_of_mass)
	return ship.linear_velocity + Vector2(-ship.angular_velocity * offset.y, ship.angular_velocity * offset.x)


# Draws a straight line of the given length along the muzzle's axis, fading out over the last
# fade_length px before max_range. A line cut short by a hit fades only as far as it reaches into
# that stretch, so a close target keeps a solid line.
# Uses the Line2D's gradient, which replaces its default_color.
func set_range_line(line: Line2D, length: float, color: Color, max_range: float, fade_length: float) -> void:
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])

	if line.gradient == null:
		line.gradient = Gradient.new()

	var fade_start := maxf(max_range - fade_length, 0.0)
	var end_color := color

	if fade_length > 0.0:
		end_color.a *= clampf(inverse_lerp(max_range, fade_start, length), 0.0, 1.0)

	var solid_end := clampf(fade_start / length, 0.0, 1.0) if length > 0.0 else 1.0
	line.gradient.offsets = PackedFloat32Array([0.0, solid_end, 1.0])
	line.gradient.colors = PackedColorArray([color, color, end_color])
