class_name CanisterRack
extends SoftPoint

# A canister for cargo, strapped on the hull. Two versions, one scene each:
# - the ingot canister (cargo = INGOTS) takes liquid ore from the ingot holds, in units;
# - the ore canister (cargo = ORE) takes raw cells from the ore bins, in cells.
# - tap: fill the canister with up to `capacity` out of the rooms and throw it overboard.
#   Ore is heavy: it's how to lighten a full ship in a hurry, or to leave a load behind
#   (next to a beacon) and come back for it.
# Touch the canister gently to take it back: its contents go back into the rooms, as much as
# fits. What doesn't fit stays in the canister, on the rack, where its weight counts.
# A rack only takes back its own kind of canister.
# A tap with cargo still in the stowed canister throws that cargo out with it.
#
# Contents are a dictionary of amounts (see CargoCanister): ore id -> units for ingots,
# Vector2i(material, ore it counts as) -> cells for raw cells, the same entries as OreBinRoom.

@export var cargo: CargoCanister.Cargo = CargoCanister.Cargo.INGOTS
@export var capacity: float = 40.0 # Units of ingots, or cells of raw ore
@export var canister_mass: float = 1.0
@export var ore_mass_per_unit: float = 0.1 # Keep equal to ShipMass.ore_mass_per_cell
@export var launch_speed: float = 20.0

@export_group("Look")
@export var liquid_color: Color = Color(0.8, 0.72, 0.56) # Also the colour of the raw cells in the ore canister

var has_canister: bool = true
var stowed: Dictionary = {} # Cargo left in the canister on the rack. Same keys as CargoCanister.contents


func _init() -> void:
	footprint = Rect2(0, -10, 12, 20)
	dry_mass = 1.0


func get_status_text() -> String:
	if not has_canister:
		return "no canister"

	var amount := CargoCanister.count(stowed)
	return "canister aboard" if amount <= 0.0 else "canister aboard, %.0f %s in it" % [amount, _get_unit_name()]


func get_aim_speed() -> float:
	return launch_speed if has_canister else 0.0


func get_controls_text() -> String:
	if not has_canister:
		return ""

	return "tap: dump ingots" if cargo == CargoCanister.Cargo.INGOTS else "tap: dump raw ore"


func restock() -> void:
	has_canister = true
	queue_redraw()


func accepts_prop(prop: SpaceProp) -> bool:
	return prop is CargoCanister and (prop as CargoCanister).cargo == cargo and not has_canister


func recover_prop(prop: SpaceProp) -> bool:
	if not accepts_prop(prop):
		return false

	var canister := prop as CargoCanister
	stowed = _store_in_rooms(canister.contents)
	var back_in_hold := canister.get_amount() - CargoCanister.count(stowed)
	has_canister = true
	prop.queue_free()
	queue_redraw()

	if stowed.is_empty():
		say("Canister recovered: %.0f %s back in the hold" % [back_in_hold, _get_unit_name()])
	else:
		say("Canister recovered: %.0f %s in the hold, %.0f kept in the canister" % [back_in_hold, _get_unit_name(), CargoCanister.count(stowed)])

	return true


func _on_tap() -> void:
	if not has_canister:
		say("Canister: none aboard")
		return

	var contents := stowed.duplicate()
	var room_left := capacity - CargoCanister.count(contents)

	if room_left > 0.0 and soft_points.rooms != null:
		var taken := _take_from_rooms(room_left)

		for key in taken:
			contents[key] = contents.get(key, 0.0) + taken[key]

	if CargoCanister.count(contents) <= 0.0:
		say("Canister: the %s are empty" % ("ingot holds" if cargo == CargoCanister.Cargo.INGOTS else "ore bins"))
		return

	var canister := CargoCanister.new()
	canister.cargo = cargo
	canister.empty_mass = canister_mass
	canister.ore_mass_per_unit = ore_mass_per_unit
	canister.fill(contents)

	stowed.clear()
	has_canister = false
	launch_prop(canister, get_tip() + get_outward() * (canister.radius + TEXEL), get_outward() * launch_speed)
	say("Canister: %.0f %s thrown overboard" % [canister.get_amount(), _get_unit_name()])
	queue_redraw()


# Up to `amount` out of the rooms this canister is for.
func _take_from_rooms(amount: float) -> Dictionary:
	var taken := {}

	if cargo == CargoCanister.Cargo.INGOTS:
		var ingots := soft_points.rooms.take_ingots(amount)

		for ore_id in ingots:
			taken[ore_id] = ingots[ore_id]

		return taken

	for entry in soft_points.rooms.take_ore_cells(floori(amount)):
		taken[entry] = taken.get(entry, 0.0) + 1.0

	return taken


# Puts the contents back into the rooms, as much as fits. Returns what didn't fit.
func _store_in_rooms(contents: Dictionary) -> Dictionary:
	var left := {}

	for key in contents:
		var amount: float = contents[key]
		var stored := 0.0

		if cargo == CargoCanister.Cargo.INGOTS:
			stored = soft_points.rooms.store_ingots(key, amount)
		else:
			var entry: Vector2i = key

			while stored < amount and soft_points.rooms.store_ore_cell(entry.x, entry.y):
				stored += 1.0

		if amount - stored > 0.001:
			left[key] = amount - stored

	return left


func _get_unit_name() -> String:
	return "u" if cargo == CargoCanister.Cargo.INGOTS else "cells"


func _get_load_mass() -> float:
	if not has_canister:
		return 0.0

	return canister_mass + CargoCanister.count(stowed) * ore_mass_per_unit


func _draw_module() -> void:
	_draw_plate(Rect2(footprint.position, Vector2(TEXEL * 3.0, footprint.size.y)), body_color) # Cradle

	if not has_canister:
		return

	var can := Rect2(footprint.position.x + TEXEL * 3.0, footprint.position.y + TEXEL, footprint.size.x - TEXEL * 3.0, footprint.size.y - TEXEL * 2.0)
	draw_rect(can, outline_color)

	var inner := can.grow(-TEXEL * 0.5)
	draw_rect(inner, liquid_color.darkened(0.5))

	var ratio := clampf(CargoCanister.count(stowed) / capacity, 0.0, 1.0)
	var level := snappedf(inner.size.y * ratio, TEXEL)
	draw_rect(Rect2(inner.position.x, inner.end.y - level, inner.size.x, level), liquid_color)

	if cargo == CargoCanister.Cargo.ORE:
		# Crate slats, so the ore canister reads differently from the ingot one
		var y := inner.position.y + TEXEL * 2.0

		while y < inner.end.y:
			draw_rect(Rect2(inner.position.x, y, inner.size.x, TEXEL * 0.5), outline_color)
			y += TEXEL * 3.0
