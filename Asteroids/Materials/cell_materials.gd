class_name CellMaterials
extends RefCounted

# Every material an asteroid cell can be made of. Cells store an Id (an int): dictionaries of ints
# stay light, and the values live in one place, the .tres files next to this script.
#
# Rock makes up most of every asteroid: about half tough, half soft.
# Ores, loosely based on real asteroid classes:
# - Water ice: C-type (carbonaceous) asteroids, the most common kind. Cheap, but it will be fuel.
# - Nickel-iron: M-type (metallic) asteroids. Very hard, low value per unit.
# - Cobalt: S-type (stony) asteroids, mixed into their metal grains.
# - Gold: S-type and M-type asteroids. Soft for a metal.
# - Platinum: the platinum-group metals (platinum, iridium, rhodium) of M-type asteroids.
#   The rarest and the most valuable.

enum Id { SOFT_ROCK, TOUGH_ROCK, WATER_ICE, NICKEL_IRON, COBALT, GOLD, PLATINUM }

const ORES: Array[int] = [Id.WATER_ICE, Id.NICKEL_IRON, Id.COBALT, Id.GOLD, Id.PLATINUM]

# Same order as Id.
const ALL := [
	preload("res://Asteroids/Materials/soft_rock.tres"),
	preload("res://Asteroids/Materials/tough_rock.tres"),
	preload("res://Asteroids/Materials/water_ice.tres"),
	preload("res://Asteroids/Materials/nickel_iron.tres"),
	preload("res://Asteroids/Materials/cobalt.tres"),
	preload("res://Asteroids/Materials/gold.tres"),
	preload("res://Asteroids/Materials/platinum.tres"),
]

# What buried ore looks like until it has been seen.
const HIDDEN_ORE_LOOK: Id = Id.TOUGH_ROCK


static func get_material(id: int) -> CellMaterial:
	return ALL[id]


static func is_ore(id: int) -> bool:
	return get_material(id).is_ore


# What the player sees: ore that hasn't been seen yet looks like tough rock.
static func get_display_id(id: int, is_revealed: bool) -> int:
	if is_revealed or not is_ore(id):
		return id

	return HIDDEN_ORE_LOOK


# Weighted by spawn_weight: common ores come up more often.
static func pick_ore_type() -> int:
	var weights := PackedFloat32Array()

	for id in ORES:
		weights.append(get_material(id).spawn_weight)

	var rng := RandomNumberGenerator.new()
	return ORES[rng.rand_weighted(weights)]
