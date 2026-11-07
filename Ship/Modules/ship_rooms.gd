class_name ShipRooms
extends Node2D

# Owns the swappable room slots (the RoomSlot children) and routes resources between rooms.
# Each slot has its own size; the room installed there takes that size, and its capacity with it.
# Other systems ask this node for fuel or cargo space instead of talking to rooms directly,
# so they keep working whatever the current layout is.

signal layout_changed

# Paths + load() rather than preload(): the room scripts reference ShipRooms,
# and loading lazily avoids a preload cycle.
const ROOM_SCENE_PATHS := {
	Room.Type.SMELTER: "res://Ship/Modules/smelter_room.tscn",
	Room.Type.CARGO: "res://Ship/Modules/cargo_room.tscn",
	Room.Type.FUEL_TANK: "res://Ship/Modules/fuel_tank_room.tscn",
}

@export var ship: RigidBody2D # Rooms with physics inside (the smelter) need the ship's motion
@export var power: Generator
@export var starting_layout: Array[Room.Type] = [Room.Type.SMELTER, Room.Type.CARGO, Room.Type.FUEL_TANK]

var slots: Array[RoomSlot] = []
var rooms: Array[Room] = [] # Same index as slots. null = empty slot


func _ready() -> void:
	for child in get_children():
		if child is RoomSlot:
			slots.append(child)

	rooms.resize(slots.size())

	for i in mini(slots.size(), starting_layout.size()):
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
# Any room whose takes_chunks() is true can receive chunks (see Room): the smelter today,
# a holding room later. A ship may have none.


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


# --- Cargo


func get_free_cargo_cells() -> float:
	var total := 0.0

	for room in rooms:
		if room is CargoRoom:
			total += (room as CargoRoom).get_free_cells()

	return total


func get_cargo_cells() -> float:
	var total := 0.0

	for room in rooms:
		if room is CargoRoom:
			total += (room as CargoRoom).stored_cells

	return total


func get_cargo_capacity_cells() -> float:
	var total := 0.0

	for room in rooms:
		if room is CargoRoom:
			total += (room as CargoRoom).get_capacity_cells()

	return total


# Units of each ore across all cargo rooms. CellMaterials.Id -> units.
func get_cargo_by_ore() -> Dictionary[int, float]:
	var totals: Dictionary[int, float] = {}

	for room in rooms:
		if room is CargoRoom:
			var by_ore := (room as CargoRoom).stored_by_ore

			for ore_id in by_ore:
				totals[ore_id] = totals.get(ore_id, 0.0) + by_ore[ore_id]

	return totals


# Fills the cargo rooms in slot order. Returns how many units were stored.
func store_ore(ore_id: int, cells: float) -> float:
	var stored := 0.0

	for room in rooms:
		if stored >= cells:
			break

		if room is CargoRoom:
			stored += (room as CargoRoom).store(ore_id, cells - stored)

	return stored


# Takes up to max_units out of the cargo rooms, every ore in proportion to how much there is.
# Returns what was taken: CellMaterials.Id -> units.
func take_cargo(max_units: float) -> Dictionary[int, float]:
	var taken: Dictionary[int, float] = {}
	var total := get_cargo_cells()

	if total <= 0.0 or max_units <= 0.0:
		return taken

	var share := minf(max_units / total, 1.0)

	for room in rooms:
		if not room is CargoRoom:
			continue

		var cargo := room as CargoRoom

		for ore_id in cargo.stored_by_ore.keys():
			var units := cargo.take(ore_id, cargo.stored_by_ore[ore_id] * share)
			taken[ore_id] = taken.get(ore_id, 0.0) + units

	return taken


func empty_cargo() -> void:
	for room in rooms:
		if room is CargoRoom:
			room.clear_contents()


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
