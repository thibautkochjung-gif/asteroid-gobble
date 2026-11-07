class_name ShipHardpoints
extends Node2D

# Owns the swappable weapon slots: every Node2D child is a hardpoint, in tree order.
# Slot N fires with the input action "fire_hardpoint_N" (1 = LMB, 2 = RMB).
# Relays every weapon's cooldown_blocked, so the HUD works whatever is installed.

signal layout_changed
signal cooldown_blocked(weapon_name: String, time_left: float)

# Paths + load(), same reason as ShipRooms: avoids a preload cycle with the weapon scripts.
const WEAPON_SCENE_PATHS := {
	HardpointWeapon.Type.LASER: "res://Ship/Weapons/laser.tscn",
	HardpointWeapon.Type.DRILL: "res://Ship/Weapons/drill.tscn",
	HardpointWeapon.Type.PROJECTILE_LAUNCHER: "res://Ship/Weapons/projectile_launcher.tscn",
	HardpointWeapon.Type.GRABBER: "res://Ship/Weapons/grabber.tscn",
	HardpointWeapon.Type.PLASMA_GUN: "res://Ship/Weapons/plasma_gun.tscn",
}

@export var ship: RigidBody2D
@export var power: Generator
@export var hangar: Hangar
@export var starting_layout: Array[HardpointWeapon.Type] = [HardpointWeapon.Type.LASER, HardpointWeapon.Type.DRILL]

var slots: Array[Node2D] = []
var weapons: Array[HardpointWeapon] = [] # Same index as slots. null = empty hardpoint


func _ready() -> void:
	for child in get_children():
		if child is Node2D:
			slots.append(child)

	weapons.resize(slots.size())

	for i in mini(slots.size(), starting_layout.size()):
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
	weapon.power_source = power
	weapon.hangar = hangar
	weapon.cooldown_blocked.connect(_on_weapon_cooldown_blocked.bind(weapon))
	slots[slot_index].add_child(weapon)
	weapons[slot_index] = weapon
	layout_changed.emit()


func get_slot_count() -> int:
	return slots.size()


func get_weapon(slot_index: int) -> HardpointWeapon:
	return weapons[slot_index]


func get_fire_action(slot_index: int) -> StringName:
	return StringName("fire_hardpoint_%d" % [slot_index + 1])


# cooldown_blocked gives time_left; the bound weapon is appended after it.
func _on_weapon_cooldown_blocked(time_left: float, weapon: HardpointWeapon) -> void:
	cooldown_blocked.emit(HardpointWeapon.TYPE_NAMES[weapon.weapon_type], time_left)
