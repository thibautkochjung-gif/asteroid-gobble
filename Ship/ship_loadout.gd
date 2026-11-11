class_name ShipLoadout
extends Resource

# What a ship is built from: a hull, and what sits in each of its slots. EMPTY = nothing fitted.
# GameState keeps the player's loadout. RunLink (field) and ShipPreview (mechanic) build the ship
# from it with apply(), before the ship's _ready(): the systems then install the modules themselves
# from their starting_layout, as they always did.
#
# Hull layout: every hull scene (Ship/Hulls) has these children, which the loadout fills:
# - Rooms: ShipRooms, with one RoomSlot child per room slot;
# - Hardpoints: ShipHardpoints, with one Node2D child per hardpoint;
# - SoftPoints: ShipSoftPoints, with one SoftPointMount child per mount;
# - Computer: ShipComputer;
# - Grinder: Grinder (optional), which gets the triage (discarded).

const EMPTY: int = -1

@export var hull_id: StringName = &"bucket"
@export var rooms: Array[int] = [] # Room.Type per room slot
@export var hardpoints: Array[int] = [] # HardpointWeapon.Type per hardpoint
@export var soft_points: Array[int] = [] # SoftPoint.Type per mount
@export var discarded: Array[int] = [CellMaterials.Id.SOFT_ROCK, CellMaterials.Id.TOUGH_ROCK] # CellMaterials.Id the grinder throws out


# Reads the layout a hull scene comes with. Doesn't add the ship to the tree.
static func from_hull_scene(id: StringName, scene: PackedScene) -> ShipLoadout:
	var loadout := ShipLoadout.new()
	loadout.hull_id = id
	var ship := scene.instantiate()
	var room_count := ship.get_node("Rooms").get_children().filter(func(n: Node) -> bool: return n is RoomSlot).size()
	var hardpoint_count := ship.get_node("Hardpoints").get_children().filter(func(n: Node) -> bool: return n is Node2D).size()
	var mount_count := ship.get_node("SoftPoints").get_children().filter(func(n: Node) -> bool: return n is SoftPointMount).size()
	loadout.rooms = _fit_to(ship.get_node("Rooms").starting_layout, room_count)
	loadout.hardpoints = _fit_to(ship.get_node("Hardpoints").starting_layout, hardpoint_count)
	loadout.soft_points = _fit_to(ship.get_node("SoftPoints").starting_layout, mount_count)

	var grinder := ship.get_node_or_null("Grinder") as Grinder

	if grinder != null:
		loadout.discarded = _ints(grinder.discarded_materials)

	ship.free()
	return loadout


# Call on a freshly instantiated ship, before it enters the tree.
func apply(ship: Node) -> void:
	# assign() copies into the systems' enum-typed arrays; EMPTY entries pass through as -1.
	ship.get_node("Rooms").starting_layout.assign(rooms)
	ship.get_node("Hardpoints").starting_layout.assign(hardpoints)
	ship.get_node("SoftPoints").starting_layout.assign(soft_points)

	var grinder := ship.get_node_or_null("Grinder") as Grinder

	if grinder != null:
		grinder.discarded_materials.assign(discarded)


func copy() -> ShipLoadout:
	var other := ShipLoadout.new()
	other.hull_id = hull_id
	other.rooms = rooms.duplicate()
	other.hardpoints = hardpoints.duplicate()
	other.soft_points = soft_points.duplicate()
	other.discarded = discarded.duplicate()
	return other


func to_dict() -> Dictionary:
	return { "hull": String(hull_id), "rooms": rooms, "hardpoints": hardpoints, "soft_points": soft_points, "discarded": discarded }


static func from_dict(data: Dictionary) -> ShipLoadout:
	var loadout := ShipLoadout.new()
	loadout.hull_id = StringName(data.get("hull", "bucket"))
	loadout.rooms = _ints(data.get("rooms", []))
	loadout.hardpoints = _ints(data.get("hardpoints", []))
	loadout.soft_points = _ints(data.get("soft_points", []))

	if data.has("discarded"):
		loadout.discarded = _ints(data.discarded)

	return loadout


static func _fit_to(layout: Array, count: int) -> Array[int]:
	var out: Array[int] = []

	for i in count:
		out.append(int(layout[i]) if i < layout.size() else EMPTY)

	return out


static func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []

	for value in values:
		out.append(int(value))

	return out

