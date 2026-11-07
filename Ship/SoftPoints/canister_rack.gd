class_name CanisterRack
extends SoftPoint

# A canister for liquid ore, strapped on the hull.
# - tap: pour up to `capacity` units out of the cargo rooms into the canister and throw it
#   overboard. Ore is heavy: it's how to lighten a full ship in a hurry, or to leave a load
#   behind (next to a beacon) and come back for it.
# Touch the canister gently to take it back: its ore goes back into the cargo rooms, as much as
# fits. What doesn't fit stays in the canister, on the rack, where its weight counts.
# A tap with ore still in the stowed canister throws that ore out with it.

@export var capacity: float = 40.0 # Units
@export var canister_mass: float = 1.0
@export var ore_mass_per_unit: float = 0.1 # Keep equal to ShipMass.ore_mass_per_cell
@export var launch_speed: float = 20.0

@export_group("Look")
@export var liquid_color: Color = Color(0.8, 0.72, 0.56)

var has_canister: bool = true
var stowed: Dictionary[int, float] = {} # Ore left in the canister on the rack. CellMaterials.Id -> units


func _init() -> void:
	footprint = Rect2(0, -10, 12, 20)
	dry_mass = 1.0


func get_status_text() -> String:
	if not has_canister:
		return "no canister"

	var units := _count(stowed)
	return "canister aboard" if units <= 0.0 else "canister aboard, %.0f u in it" % units


func get_aim_speed() -> float:
	return launch_speed if has_canister else 0.0


func get_controls_text() -> String:
	return "tap: dump cargo" if has_canister else ""


func restock() -> void:
	has_canister = true
	queue_redraw()


func accepts_prop(prop: SpaceProp) -> bool:
	return prop is CargoCanister and not has_canister


func recover_prop(prop: SpaceProp) -> bool:
	if not accepts_prop(prop):
		return false

	var canister := prop as CargoCanister
	var back_in_hold := 0.0
	stowed.clear()

	for ore_id in canister.contents:
		var units: float = canister.contents[ore_id]
		var stored := soft_points.rooms.store_ore(ore_id, units)
		back_in_hold += stored

		if units - stored > 0.001:
			stowed[ore_id] = units - stored

	has_canister = true
	prop.queue_free()
	queue_redraw()

	if stowed.is_empty():
		say("Canister recovered: %.0f u back in the hold" % back_in_hold)
	else:
		say("Canister recovered: %.0f u in the hold, %.0f u kept in the canister" % [back_in_hold, _count(stowed)])

	return true


func _on_tap() -> void:
	if not has_canister:
		say("Canister: none aboard")
		return

	var contents: Dictionary[int, float] = {}

	for ore_id in stowed:
		contents[ore_id] = stowed[ore_id]

	var room_left := capacity - _count(contents)

	if room_left > 0.0 and soft_points.rooms != null:
		var taken := soft_points.rooms.take_cargo(room_left)

		for ore_id in taken:
			contents[ore_id] = contents.get(ore_id, 0.0) + taken[ore_id]

	if _count(contents) <= 0.0:
		say("Canister: the cargo rooms are empty")
		return

	var canister := CargoCanister.new()
	canister.empty_mass = canister_mass
	canister.ore_mass_per_unit = ore_mass_per_unit
	canister.fill(contents)

	stowed.clear()
	has_canister = false
	launch_prop(canister, get_tip() + get_outward() * (canister.radius + TEXEL), get_outward() * launch_speed)
	say("Canister: %.0f u thrown overboard" % canister.get_units())
	queue_redraw()


func _get_load_mass() -> float:
	if not has_canister:
		return 0.0

	return canister_mass + _count(stowed) * ore_mass_per_unit


func _count(contents: Dictionary) -> float:
	var total := 0.0

	for ore_id in contents:
		total += contents[ore_id]

	return total


func _draw_module() -> void:
	_draw_plate(Rect2(footprint.position, Vector2(TEXEL * 3.0, footprint.size.y)), body_color) # Cradle

	if not has_canister:
		return

	var can := Rect2(footprint.position.x + TEXEL * 3.0, footprint.position.y + TEXEL, footprint.size.x - TEXEL * 3.0, footprint.size.y - TEXEL * 2.0)
	draw_rect(can, outline_color)

	var inner := can.grow(-TEXEL * 0.5)
	draw_rect(inner, liquid_color.darkened(0.5))

	var ratio := clampf(_count(stowed) / capacity, 0.0, 1.0)
	var level := snappedf(inner.size.y * ratio, TEXEL)
	draw_rect(Rect2(inner.position.x, inner.end.y - level, inner.size.x, level), liquid_color)
