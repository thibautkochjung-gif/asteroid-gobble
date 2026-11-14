class_name ShipLoadout
extends Resource

# One of the player's ships: its hull, what sits in each of its slots (EMPTY = nothing fitted), and
# its condition between runs.
# GameState keeps the player's ships. RunLink (field) and ShipPreview (mechanic) build the ship
# from it with apply(), before the ship's _ready(): the systems then install the modules themselves
# from their starting_layout, as they always did.
#
# Hull layout: every hull scene (Ship/Hulls) has these children, which the loadout fills:
# - Rooms: ShipRooms, with one RoomSlot child per room slot;
# - Hardpoints: ShipHardpoints, with one Node2D child per hardpoint;
# - SoftPoints: ShipSoftPoints, with one SoftPointMount child per mount;
# - Computer: ShipComputer, which gets its ComputerModule;
# - Grinder: Grinder (optional), which gets the triage (discarded).
# Module settings from the ship menu (J), other than the grinder's triage, sit in module_settings:
# settings key (ShipHardpoints.get_settings_key) -> the module's own dictionary.

const EMPTY: int = -1

@export var hull_id: StringName = &"bucket"
@export var rooms: Array[int] = [] # Room.Type per room slot
@export var hardpoints: Array[int] = [] # HardpointWeapon.Type per hardpoint
@export var soft_points: Array[int] = [] # SoftPoint.Type per mount
@export var computers: Array[int] = [ComputerModule.Type.BASIC] # Always one, never EMPTY. An array so the mechanic handles it like the other slots

# The ship's condition between runs. What's missing is bought back on the undock screen.
@export var hull_ratio: float = 1.0
@export var fuel_missing: float = 0.0
@export var ammo_missing: int = 0
@export var discarded: Array[int] = [CellMaterials.Id.SOFT_ROCK, CellMaterials.Id.TOUGH_ROCK] # CellMaterials.Id the grinder throws out
@export var module_settings: Dictionary = {} # Settings key -> settings (see the header)


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
	var module := (ship.get_node("Computer") as ShipComputer).module
	loadout.computers.assign([module.model if module != null else ComputerModule.Type.BASIC])

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
	ship.get_node("Hardpoints").module_settings = module_settings.duplicate(true) # A copy: the menu saves through GameState
	ship.get_node("SoftPoints").starting_layout.assign(soft_points)
	(ship.get_node("Computer") as ShipComputer).module = ComputerModule.load_type(computers[0])

	var grinder := ship.get_node_or_null("Grinder") as Grinder

	if grinder != null:
		grinder.discarded_materials.assign(discarded)


func copy() -> ShipLoadout:
	var other := ShipLoadout.new()
	other.hull_id = hull_id
	other.rooms = rooms.duplicate()
	other.hardpoints = hardpoints.duplicate()
	other.soft_points = soft_points.duplicate()
	other.computers = computers.duplicate()
	other.discarded = discarded.duplicate()
	other.module_settings = module_settings.duplicate(true)
	other.hull_ratio = hull_ratio
	other.fuel_missing = fuel_missing
	other.ammo_missing = ammo_missing
	return other


func to_dict() -> Dictionary:
	return {
		"hull": String(hull_id),
		"rooms": rooms,
		"hardpoints": hardpoints,
		"soft_points": soft_points,
		"computers": computers,
		"discarded": discarded,
		"module_settings": module_settings,
		"hull_ratio": hull_ratio,
		"fuel_missing": fuel_missing,
		"ammo_missing": ammo_missing,
	}


static func from_dict(data: Dictionary) -> ShipLoadout:
	var loadout := ShipLoadout.new()
	loadout.hull_id = StringName(data.get("hull", "bucket"))
	loadout.rooms = _ints(data.get("rooms", []))
	loadout.hardpoints = _ints(data.get("hardpoints", []))
	loadout.soft_points = _known_types(_ints(data.get("soft_points", [])), SoftPoint.Type.values())

	if data.has("computers"): # Saves from before the computer slot keep the basic one
		loadout.computers = _ints(data.computers)

	if data.has("discarded"):
		loadout.discarded = _ints(data.discarded)

	loadout.module_settings = data.get("module_settings", {})
	loadout.hull_ratio = float(data.get("hull_ratio", 1.0))
	loadout.fuel_missing = float(data.get("fuel_missing", 0.0))
	loadout.ammo_missing = int(data.get("ammo_missing", 0))
	return loadout


static func _fit_to(layout: Array, count: int) -> Array[int]:
	var out: Array[int] = []

	for i in count:
		out.append(int(layout[i]) if i < layout.size() else EMPTY)

	return out


# Types that no longer exist (the capacitor pack) become EMPTY.
static func _known_types(types: Array[int], known: Array) -> Array[int]:
	var out: Array[int] = []

	for type in types:
		out.append(type if type == EMPTY or known.has(type) else EMPTY)

	return out


static func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []

	for value in values:
		out.append(int(value))

	return out
