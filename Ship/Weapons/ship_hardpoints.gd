class_name ShipHardpoints
extends Node2D

# Owns the swappable weapon slots: every Node2D child is a hardpoint, in tree order.
# Hardpoints work in pairs: slots 1-2, 3-4... Only the active pair fires. LMB (hardpoint_left) fires
# its first slot, RMB (hardpoint_right) its second, and Tab (switch_hardpoint_pair) moves to the next pair.
# Weapons don't know about pairs: each one reads its own action, "fire_hardpoint_N". Those actions have
# no key bound; this node presses and releases them from LMB and RMB (Input.action_press/release), so
# is_action_just_pressed() etc. keep working in the weapons as before.
# Relays every weapon's cooldown_blocked and message, so the HUD works whatever is installed.
#
# Ammo: weapons draw rounds through this node, never from a store directly. The rounds sit in
# three kinds of store, emptied in this order:
# - ammo boxes on the soft points (outside: the ship sheds that weight first, like drop tanks);
# - ammo rooms (ShipRooms);
# - the hull's own locker, built_in_ammo_capacity rounds. Its weight counts at this node.
# Rounds loaded in a magazine count in the ship's total: restock_ammo() leaves room for them.

signal layout_changed
signal cooldown_blocked(weapon_name: String, time_left: float)
signal weapon_message(weapon_name: String, text: String)
signal active_pair_changed(pair: int)

const LEFT_ACTION: StringName = &"hardpoint_left"
const RIGHT_ACTION: StringName = &"hardpoint_right"
const SWITCH_ACTION: StringName = &"switch_hardpoint_pair"
const AMMO_MASS_PER_ROUND: float = 0.01 # ShipMass, AmmoRoom and AmmoBox all use this one

# Paths + load(), same reason as ShipRooms: avoids a preload cycle with the weapon scripts.
const WEAPON_SCENE_PATHS := {
	HardpointWeapon.Type.LASER: "res://Ship/Weapons/laser.tscn",
	HardpointWeapon.Type.DRILL: "res://Ship/Weapons/drill.tscn",
	HardpointWeapon.Type.PROJECTILE_LAUNCHER: "res://Ship/Weapons/projectile_launcher.tscn",
	HardpointWeapon.Type.GRABBER: "res://Ship/Weapons/grabber.tscn",
	HardpointWeapon.Type.PLASMA_GUN: "res://Ship/Weapons/plasma_gun.tscn",
	HardpointWeapon.Type.NET_LAUNCHER: "res://Ship/Weapons/Net/net_launcher.tscn",
	HardpointWeapon.Type.SCANNER: "res://Ship/Weapons/Scanner/scanner.tscn",
	HardpointWeapon.Type.PRECISION_SCANNER: "res://Ship/Weapons/Scanner/precision_scanner.tscn",
	HardpointWeapon.Type.HYDRAULIC_SPLITTER: "res://Ship/Weapons/Splitter/hydraulic_splitter.tscn",
	HardpointWeapon.Type.TRACTOR_BEAM: "res://Ship/Weapons/TractorBeam/tractor_beam.tscn",
	HardpointWeapon.Type.HEAVY_TRACTOR_BEAM: "res://Ship/Weapons/TractorBeam/heavy_tractor_beam.tscn",
	HardpointWeapon.Type.SMART_TRACTOR_BEAM: "res://Ship/Weapons/TractorBeam/smart_tractor_beam.tscn",
	HardpointWeapon.Type.BREACHING_LANCE: "res://Ship/Weapons/Lance/breaching_lance.tscn",
	HardpointWeapon.Type.DEFLECTOR_PROW: "res://Ship/Weapons/Prow/deflector_prow.tscn",
}

@export var ship: RigidBody2D
@export var hangar: Hangar
@export var rooms: ShipRooms # Optional: ammo rooms
@export var soft_points: ShipSoftPoints # Optional: ammo boxes
@export var starting_layout: Array[HardpointWeapon.Type] = [HardpointWeapon.Type.LASER, HardpointWeapon.Type.DRILL]
@export var built_in_ammo_capacity: int = 120 # The hull's own locker. Set per ship

var slots: Array[Node2D] = []
var weapons: Array[HardpointWeapon] = [] # Same index as slots. null = empty hardpoint
var built_in_ammo: int = 0
var active_pair: int = 0
var module_settings: Dictionary = {} # Settings key -> the weapon's settings. Set by ShipLoadout.apply()

var _held_slots: Array[int] = [-1, -1] # Slot pressed by LMB, by RMB. -1 = none


func _ready() -> void:
	built_in_ammo = built_in_ammo_capacity # Before the weapons: they load their magazines from it

	for child in get_children():
		if child is Node2D:
			slots.append(child)

	weapons.resize(slots.size())
	_add_fire_actions()

	for i in mini(slots.size(), starting_layout.size()):
		if starting_layout[i] < 0: # Empty slot (ShipLoadout.EMPTY)
			continue

		install_weapon(i, starting_layout[i])


func install_weapon(slot_index: int, type: HardpointWeapon.Type) -> void:
	var old_weapon := weapons[slot_index]

	if old_weapon != null:
		if old_weapon.weapon_type == type:
			return

		slots[slot_index].remove_child(old_weapon)
		old_weapon.queue_free()

	var weapon: HardpointWeapon = load(WEAPON_SCENE_PATHS[type]).instantiate()
	weapon.weapon_type = type
	weapon.fire_action = get_fire_action(slot_index)
	weapon.ship = ship
	weapon.hangar = hangar
	weapon.ammo_source = self
	weapon.settings_key = get_settings_key(slot_index, type)
	weapon.apply_settings(module_settings.get(weapon.settings_key, {}))
	weapon.cooldown_blocked.connect(_on_weapon_cooldown_blocked.bind(weapon))
	weapon.message.connect(_on_weapon_message.bind(weapon))
	slots[slot_index].add_child(weapon)
	weapons[slot_index] = weapon
	layout_changed.emit()


# Per slot AND type: a weapon swapped for another type starts from its defaults.
static func get_settings_key(slot_index: int, type: int) -> String:
	return "hardpoint:%d:%d" % [slot_index, type]


func get_slot_count() -> int:
	return slots.size()


func get_weapon(slot_index: int) -> HardpointWeapon:
	return weapons[slot_index]


func get_fire_action(slot_index: int) -> StringName:
	return StringName("fire_hardpoint_%d" % [slot_index + 1])


# --- Pairs


func get_pair_count() -> int:
	return ceili(slots.size() / 2.0)


func get_pair(slot_index: int) -> int:
	return floori(slot_index / 2.0)


func is_slot_active(slot_index: int) -> bool:
	return get_pair(slot_index) == active_pair


# The physical action that fires this slot when its pair is active: LMB or RMB.
func get_trigger_action(slot_index: int) -> StringName:
	return LEFT_ACTION if slot_index % 2 == 0 else RIGHT_ACTION


func switch_pair() -> void:
	if get_pair_count() < 2:
		return

	_release_held()
	active_pair = (active_pair + 1) % get_pair_count()
	active_pair_changed.emit(active_pair)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(SWITCH_ACTION):
		switch_pair()
		return

	for side in 2:
		var trigger := LEFT_ACTION if side == 0 else RIGHT_ACTION

		if event.is_action_pressed(trigger):
			_press(side)
		elif event.is_action_released(trigger):
			_release(side)


# A release can be missed (game paused while the button was held): let go of anything whose
# button is no longer down.
func _physics_process(_delta: float) -> void:
	for side in 2:
		var trigger := LEFT_ACTION if side == 0 else RIGHT_ACTION

		if _held_slots[side] >= 0 and not Input.is_action_pressed(trigger):
			_release(side)


func _press(side: int) -> void:
	var slot_index := active_pair * 2 + side

	if slot_index >= slots.size():
		return

	_release(side)
	_held_slots[side] = slot_index
	Input.action_press(get_fire_action(slot_index))


func _release(side: int) -> void:
	if _held_slots[side] < 0:
		return

	Input.action_release(get_fire_action(_held_slots[side]))
	_held_slots[side] = -1


func _release_held() -> void:
	for side in 2:
		_release(side)


# One action per slot, with no key: only _press() and _release() drive them.
func _add_fire_actions() -> void:
	for i in slots.size():
		var action := get_fire_action(i)

		if not InputMap.has_action(action):
			InputMap.add_action(action)


# --- Ammo


# Rounds in storage, not counting the magazines.
func get_ammo() -> int:
	var total := built_in_ammo

	if rooms != null:
		total += rooms.get_ammo()

	if soft_points != null:
		total += soft_points.get_ammo()

	return total


func get_ammo_capacity() -> int:
	var total := built_in_ammo_capacity

	if rooms != null:
		total += rooms.get_ammo_capacity()

	if soft_points != null:
		total += soft_points.get_ammo_capacity()

	return total


# Rounds already loaded in the weapons' magazines.
func get_loaded_ammo() -> int:
	var total := 0

	for weapon in weapons:
		if weapon != null:
			total += weapon.get_loaded_ammo()

	return total


func get_magazine_capacity() -> int:
	var total := 0

	for weapon in weapons:
		if weapon != null:
			total += weapon.get_magazine_size()

	return total


# Ammo boxes first, then ammo rooms, then the locker. Returns how many rounds were given.
func draw_ammo(count: int) -> int:
	var granted := 0

	if soft_points != null:
		granted += soft_points.draw_ammo(count)

	if rooms != null and granted < count:
		granted += rooms.draw_ammo(count - granted)

	var from_locker := mini(count - granted, built_in_ammo)
	built_in_ammo -= from_locker
	return granted + from_locker


# Station service. Fills every store, then takes back what the magazines already hold, so the
# ship never carries more than its storage. Call it after ShipSoftPoints.restock(), which fills
# the ammo boxes.
func restock_ammo() -> void:
	built_in_ammo = built_in_ammo_capacity

	if rooms != null:
		rooms.restock_ammo()

	draw_ammo(get_loaded_ammo())

	for weapon in weapons:
		if weapon != null:
			weapon.restock()


# --- Signals


# cooldown_blocked gives time_left; the bound weapon is appended after it.
func _on_weapon_cooldown_blocked(time_left: float, weapon: HardpointWeapon) -> void:
	cooldown_blocked.emit(HardpointWeapon.TYPE_NAMES[weapon.weapon_type], time_left)


func _on_weapon_message(text: String, weapon: HardpointWeapon) -> void:
	weapon_message.emit(HardpointWeapon.TYPE_NAMES[weapon.weapon_type], text)
