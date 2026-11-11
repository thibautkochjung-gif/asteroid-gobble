class_name ShipRooms
extends Node2D

# Owns the swappable room slots (the RoomSlot children) and routes resources between rooms.
# Each slot has its own size; the room installed there takes that size, and its capacity with it.
# Other systems ask this node for fuel or cargo space instead of talking to rooms directly,
# so they keep working whatever the current layout is.
# Two kinds of cargo: ingots (smelted, liquid, in ingot holds) and raw cells (in ore bins).

signal layout_changed

# Paths + load() rather than preload(): the room scripts reference ShipRooms,
# and loading lazily avoids a preload cycle.
const ROOM_SCENE_PATHS := {
	Room.Type.SMELTER: "res://Ship/Modules/smelter_room.tscn",
	Room.Type.INGOT_HOLD: "res://Ship/Modules/ingot_hold_room.tscn",
	Room.Type.FUEL_TANK: "res://Ship/Modules/fuel_tank_room.tscn",
	Room.Type.AMMO: "res://Ship/Modules/ammo_room.tscn",
	Room.Type.ORE_BIN: "res://Ship/Modules/ore_bin_room.tscn",
}

@export var ship: RigidBody2D # Rooms with physics inside (the smelter) need the ship's motion
@export var power: Generator
@export var starting_layout: Array[Room.Type] = [Room.Type.ORE_BIN, Room.Type.ORE_BIN, Room.Type.FUEL_TANK]

var slots: Array[RoomSlot] = []
var rooms: Array[Room] = [] # Same index as slots. null = empty slot


func _ready() -> void:
	for child in get_children():
		if child is RoomSlot:
			slots.append(child)

	rooms.resize(slots.size())

	for i in mini(slots.size(), starting_layout.size()):
		if starting_layout[i] < 0: # Empty slot (ShipLoadout.EMPTY)
			continue

		install_room(i, starting_layout[i])


func install_room(slot_index: int, type: Room.Type) -> void:
	var old_room := rooms[slot_index]

	if old_room != null:
		if old_room.room_type == type:
			return

		old_room.clear_contents()
		slots[slot_index].remove_child(old_room)
		old_room.queue_free()

	var room: Room = load(ROOM_SCENE_PATHS[type]).instantiate()
	room.ship_rooms = self
	room.size = slots[slot_index].size
	slots[slot_index].add_child(room)
	rooms[slot_index] = room
	layout_changed.emit()


func get_slot_count() -> int:
	return slots.size()


# In px.
func get_slot_size(slot_index: int) -> Vector2:
	return slots[slot_index].size


func get_room(slot_index: int) -> Room:
	return rooms[slot_index]


# --- Chunks from the hold
# Any room whose takes_chunks() is true can receive chunks (see Room): the smelter, and the ore
# bin (single cells only). A ship may have none.


func has_chunk_receivers() -> bool:
	for room in rooms:
		if room != null and room.takes_chunks():
			return true

	return false


# First room that can take this chunk right now, in slot order, or null.
func find_receiver_for(chunk: Asteroid) -> Room:
	for room in rooms:
		if room != null and room.takes_chunks() and room.can_accept_chunk(chunk):
			return room

	return null


# True if at least one room could take this chunk when empty.
func can_any_receiver_fit(chunk: Asteroid) -> bool:
	for room in rooms:
		if room != null and room.takes_chunks() and room.fits_chunk(chunk):
			return true

	return false


# Both kinds of cargo, gone.
func empty_cargo() -> void:
	for room in rooms:
		if room is IngotHoldRoom or room is OreBinRoom:
			room.clear_contents()


# Everything aboard that will sell at the hub: ingots, raw cells and unsmelted chunks alike.
# CellMaterials.Id of the ore -> units.
func get_ore_aboard() -> Dictionary[int, float]:
	var ore := get_ingots_by_ore()
	var raw := get_ore_bin_value()

	for ore_id in raw:
		ore[ore_id] = ore.get(ore_id, 0.0) + raw[ore_id]

	for room in rooms:
		if not room is SmelterRoom:
			continue

		var smelter := room as SmelterRoom

		for chunk in smelter.chunks:
			for cell in chunk.cells:
				var material_id: int = chunk.cells[cell]

				if CellMaterials.is_ore(material_id):
					ore[material_id] = ore.get(material_id, 0.0) + 1.0
				else:
					ore[chunk.ore_type] = ore.get(chunk.ore_type, 0.0) + smelter.rock_trace_yield

	return ore


# --- Smelting


func get_smelter_cells() -> int:
	var total := 0

	for room in rooms:
		if room is SmelterRoom:
			total += (room as SmelterRoom).get_cells()

	return total


func get_smelter_capacity() -> int:
	var total := 0

	for room in rooms:
		if room is SmelterRoom:
			total += (room as SmelterRoom).get_capacity_cells()

	return total


# --- Ingots (ingot holds)


func get_free_ingot_units() -> float:
	var total := 0.0

	for room in rooms:
		if room is IngotHoldRoom:
			total += (room as IngotHoldRoom).get_free_cells()

	return total


func get_ingot_units() -> float:
	var total := 0.0

	for room in rooms:
		if room is IngotHoldRoom:
			total += (room as IngotHoldRoom).stored_cells

	return total


func get_ingot_capacity() -> float:
	var total := 0.0

	for room in rooms:
		if room is IngotHoldRoom:
			total += (room as IngotHoldRoom).get_capacity_cells()

	return total


# Units of each ore across all ingot holds. CellMaterials.Id -> units.
func get_ingots_by_ore() -> Dictionary[int, float]:
	var totals: Dictionary[int, float] = {}

	for room in rooms:
		if room is IngotHoldRoom:
			var by_ore := (room as IngotHoldRoom).stored_by_ore

			for ore_id in by_ore:
				totals[ore_id] = totals.get(ore_id, 0.0) + by_ore[ore_id]

	return totals


# Fills the ingot holds in slot order. Returns how many units were stored.
func store_ingots(ore_id: int, units: float) -> float:
	var stored := 0.0

	for room in rooms:
		if stored >= units:
			break

		if room is IngotHoldRoom:
			stored += (room as IngotHoldRoom).store(ore_id, units - stored)

	return stored


# Takes up to max_units out of the ingot holds, every ore in proportion to how much there is.
# Returns what was taken: CellMaterials.Id -> units.
func take_ingots(max_units: float) -> Dictionary[int, float]:
	var taken: Dictionary[int, float] = {}
	var total := get_ingot_units()

	if total <= 0.0 or max_units <= 0.0:
		return taken

	var share := minf(max_units / total, 1.0)

	for room in rooms:
		if not room is IngotHoldRoom:
			continue

		var hold := room as IngotHoldRoom

		for ore_id in hold.stored_by_ore.keys():
			var units := hold.take(ore_id, hold.stored_by_ore[ore_id] * share)
			taken[ore_id] = taken.get(ore_id, 0.0) + units

	return taken


# --- Raw cells (ore bins)


func has_ore_bin() -> bool:
	for room in rooms:
		if room is OreBinRoom:
			return true

	return false


func get_ore_bin_cells() -> int:
	var total := 0

	for room in rooms:
		if room is OreBinRoom:
			total += (room as OreBinRoom).get_cell_count()

	return total


func get_ore_bin_capacity() -> int:
	var total := 0

	for room in rooms:
		if room is OreBinRoom:
			total += (room as OreBinRoom).get_capacity_cells()

	return total


func get_free_ore_bin_cells() -> int:
	return get_ore_bin_capacity() - get_ore_bin_cells()


# Into the first ore bin with room, in slot order. Returns false if they're all full.
func store_ore_cell(material_id: int, ore_type: int) -> bool:
	for room in rooms:
		if room is OreBinRoom and (room as OreBinRoom).store_cell(material_id, ore_type):
			return true

	return false


# Takes up to max_cells out of the ore bins, last slot first. Same entries as OreBinRoom.contents.
func take_ore_cells(max_cells: int) -> Array[Vector2i]:
	var taken: Array[Vector2i] = []

	for i in range(rooms.size() - 1, -1, -1):
		if taken.size() >= max_cells:
			break

		if rooms[i] is OreBinRoom:
			taken.append_array((rooms[i] as OreBinRoom).take_cells(max_cells - taken.size()))

	return taken


# What the raw cells will sell for. CellMaterials.Id of the ore -> units.
func get_ore_bin_value() -> Dictionary[int, float]:
	var totals: Dictionary[int, float] = {}

	for room in rooms:
		if room is OreBinRoom:
			var value := (room as OreBinRoom).get_ore_value()

			for ore_id in value:
				totals[ore_id] = totals.get(ore_id, 0.0) + value[ore_id]

	return totals


# CellMaterials.Id -> cells, across all ore bins.
func get_ore_bin_by_material() -> Dictionary[int, int]:
	var totals: Dictionary[int, int] = {}

	for room in rooms:
		if room is OreBinRoom:
			var counts := (room as OreBinRoom).get_cells_by_material()

			for material_id in counts:
				totals[material_id] = totals.get(material_id, 0) + counts[material_id]

	return totals


# --- Fuel


func get_fuel() -> float:
	var total := 0.0

	for room in rooms:
		if room is FuelTankRoom:
			total += (room as FuelTankRoom).fuel

	return total


func get_fuel_capacity() -> float:
	var total := 0.0

	for room in rooms:
		if room is FuelTankRoom:
			total += (room as FuelTankRoom).capacity

	return total


# Empties the tanks in slot order. Returns how much fuel was actually given.
func draw_fuel(amount: float) -> float:
	var granted := 0.0

	for room in rooms:
		if granted >= amount:
			break

		if room is FuelTankRoom:
			granted += (room as FuelTankRoom).draw_fuel(amount - granted)

	return granted


func refuel() -> void:
	for room in rooms:
		if room is FuelTankRoom:
			(room as FuelTankRoom).refuel()


# --- Ammo (ShipHardpoints draws from here)


func get_ammo() -> int:
	var total := 0

	for room in rooms:
		if room is AmmoRoom:
			total += (room as AmmoRoom).rounds

	return total


func get_ammo_capacity() -> int:
	var total := 0

	for room in rooms:
		if room is AmmoRoom:
			total += (room as AmmoRoom).capacity

	return total


# Empties the ammo rooms in slot order. Returns how many rounds were given.
func draw_ammo(count: int) -> int:
	var granted := 0

	for room in rooms:
		if granted >= count:
			break

		if room is AmmoRoom:
			granted += (room as AmmoRoom).draw_ammo(count - granted)

	return granted


func restock_ammo() -> void:
	for room in rooms:
		if room is AmmoRoom:
			(room as AmmoRoom).restock()
