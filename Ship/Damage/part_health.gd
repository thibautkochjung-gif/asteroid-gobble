class_name PartHealth
extends RefCounted

# Hit points of one ship part: a thruster, a hardpoint weapon, a soft point module, the hangar doors.
# A standard part has BASE_POINTS. toughness scales that: 0.6 = fragile, 2 = sturdy.
# ShipDamage deals the damage (see there for how much a hit does).
#
# Performance, what the part's own script multiplies its output by:
# - under BROKEN_RATIO of its points, 0: the part doesn't work at all;
# - above, the share of points left (90% points = 90% thrust, charge speed, door speed...).
#
# Each part creates its PartHealth on first use (get_part_health()), not in its declaration:
# by then its toughness has been set, by the scene or by a subclass's _init().
# A part only needs three methods for ShipDamage and the HUD to find it:
# get_part_health(), get_part_name() and get_hit_distance(global_point).
# For the wear marks (DamageMarks), it also needs get_damage_points().

signal changed

const BASE_POINTS: float = 100.0
const BROKEN_RATIO: float = 0.2

var max_points: float
var points: float
var is_invulnerable: bool = false # Impacts do nothing. Only the ship's destruction breaks it


func _init(toughness: float = 1.0) -> void:
	max_points = BASE_POINTS * toughness
	points = max_points


func take_damage(amount: float) -> void:
	if amount <= 0.0 or points <= 0.0:
		return

	if is_invulnerable and not is_inf(amount):
		return

	points = maxf(points - amount, 0.0)
	changed.emit()


func repair() -> void:
	points = max_points
	changed.emit()


func get_ratio() -> float:
	if max_points <= 0.0:
		return 0.0

	return points / max_points


func is_broken() -> bool:
	return get_ratio() < BROKEN_RATIO


func get_performance() -> float:
	if is_broken():
		return 0.0

	return get_ratio()
