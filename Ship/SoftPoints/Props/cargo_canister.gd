class_name CargoCanister
extends SpaceProp

# Liquid ore poured out of the cargo rooms and thrown overboard (CanisterRack), to lighten the ship
# or to come back for later. Heavy: it weighs what its ore weighs.
# Touch it gently to take it back: the ore goes back into the cargo rooms, as much as fits.

@export var empty_mass: float = 1.0
@export var ore_mass_per_unit: float = 0.1 # Keep equal to ShipMass.ore_mass_per_cell

var contents: Dictionary[int, float] = {} # CellMaterials.Id -> units


func _init() -> void:
	super()
	radius = 6.0
	body_color = Color(0.8, 0.72, 0.56)
	marker_color = Color(0.92, 0.86, 0.7)


func fill(new_contents: Dictionary[int, float]) -> void:
	contents = new_contents
	mass = empty_mass + get_units() * ore_mass_per_unit


func get_units() -> float:
	var total := 0.0

	for ore_id in contents:
		total += contents[ore_id]

	return total


func get_marker_text() -> String:
	return "Canister %.0f u" % get_units()


func _draw_prop() -> void:
	var half := Vector2(radius, radius * 0.7)
	draw_rect(Rect2(-half, half * 2.0), outline_color)
	draw_rect(Rect2(-half + Vector2(TEXEL, TEXEL) * 0.5, half * 2.0 - Vector2(TEXEL, TEXEL)), body_color)
	draw_rect(Rect2(-half.x + TEXEL, -TEXEL * 0.5, half.x * 2.0 - TEXEL * 2.0, TEXEL), body_color.darkened(0.4))
