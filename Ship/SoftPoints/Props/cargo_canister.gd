class_name CargoCanister
extends SpaceProp

# Cargo taken out of the rooms and thrown overboard (CanisterRack), to lighten the ship or to come
# back for later. Heavy: it weighs what its ore weighs.
# Two kinds: ingots (liquid ore from the ingot holds) and raw cells (from the ore bins).
# Touch it gently to take it back: the cargo goes back into the rooms, as much as fits.

enum Cargo { INGOTS, ORE }

@export var cargo: Cargo = Cargo.INGOTS
@export var empty_mass: float = 1.0
@export var ore_mass_per_unit: float = 0.1 # Keep equal to ShipMass.ore_mass_per_cell

# Ingots: CellMaterials.Id -> units.
# Raw cells: Vector2i(material, ore it counts as) -> cells, the same entries as OreBinRoom.contents.
var contents: Dictionary = {}


func _init() -> void:
	super()
	radius = 6.0
	body_color = Color(0.8, 0.72, 0.56)
	marker_color = Color(0.92, 0.86, 0.7)


# Sum of the amounts in a contents dictionary.
static func count(some_contents: Dictionary) -> float:
	var total := 0.0

	for key in some_contents:
		total += some_contents[key]

	return total


func fill(new_contents: Dictionary) -> void:
	contents = new_contents
	mass = empty_mass + get_amount() * ore_mass_per_unit

	if cargo == Cargo.ORE:
		body_color = Color(0.5, 0.46, 0.42)
		marker_color = Color(0.72, 0.68, 0.62)


func get_amount() -> float:
	return count(contents)


func get_marker_text() -> String:
	if cargo == Cargo.ORE:
		return "Ore canister %.0f cells" % get_amount()

	return "Ingot canister %.0f u" % get_amount()


func _draw_prop() -> void:
	var half := Vector2(radius, radius * 0.7)
	draw_rect(Rect2(-half, half * 2.0), outline_color)
	draw_rect(Rect2(-half + Vector2(TEXEL, TEXEL) * 0.5, half * 2.0 - Vector2(TEXEL, TEXEL)), body_color)
	draw_rect(Rect2(-half.x + TEXEL, -TEXEL * 0.5, half.x * 2.0 - TEXEL * 2.0, TEXEL), body_color.darkened(0.4))
