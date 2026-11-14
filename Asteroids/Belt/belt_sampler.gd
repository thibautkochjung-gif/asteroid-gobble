class_name BeltSampler
extends RefCounted

# Reads the belt (BeltSettings) around a drop point: depth and richness at a point of the field.
# The field plays near its origin (floats lose precision far from it); the drop point says where
# that origin sits in the belt, in km. One sampler per thread: it owns a noise object.

var settings: BeltSettings
var origin_km := Vector2.ZERO # Where the field's (0, 0) is in the belt

var _richness: FastNoiseLite


func _init(belt_settings: BeltSettings, run_seed: int, drop_km: Vector2) -> void:
	settings = belt_settings
	origin_km = drop_km
	_richness = settings.make_richness_noise(run_seed)


# A point of the field (px) in belt km.
func to_km(field_point: Vector2) -> Vector2:
	return origin_km + field_point / BeltSettings.PX_PER_KM


func get_depth(field_point: Vector2) -> float:
	return maxf(to_km(field_point).x, 0.0)


func get_richness(field_point: Vector2) -> float:
	return settings.get_richness(_richness, to_km(field_point))


func get_richness_at_km(km: Vector2) -> float:
	return settings.get_richness(_richness, km)
