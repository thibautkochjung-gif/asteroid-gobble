extends CanvasLayer

@export var hardpoints: ShipHardpoints
@export var flash_duration: float = 1.2
@export var show_debug_text: bool = false # The cockpit shows the ship's state now. This text still shows with B (balance) or on death

@export_group("Ship status")
@export var ship: RigidBody2D
@export var generator: Generator
@export var rooms: ShipRooms
@export var hangar: Hangar
@export var grinder: Grinder
@export var soft_points: ShipSoftPoints
@export var balance_view: BalanceView # Its per-input report shows while it's visible
@export var ship_damage: ShipDamage # Optional
@export var dispatch: MothershipDispatch # Optional

@export_group("Soft point messages")
@export var message_duration: float = 2.5
@export var max_messages: int = 4

var flash_tween: Tween
var _messages: Array[Dictionary] = [] # { "text", "time_left" }, newest last

@onready var cooldown_label: Label = $CooldownLabel
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	cooldown_label.modulate.a = 0.0
	hardpoints.cooldown_blocked.connect(_on_weapon_cooldown_blocked)

	if soft_points != null:
		soft_points.message.connect(_on_soft_point_message)


func _process(delta: float) -> void:
	_tick_messages(delta)
	var is_destroyed := ship_damage != null and ship_damage.is_destroyed
	var wants_report := show_debug_text or balance_view != null and balance_view.visible
	status_label.visible = wants_report or is_destroyed

	if wants_report:
		status_label.text = _build_status_text()
	elif is_destroyed:
		status_label.text = "*** SHIP DESTROYED ***   R: restart"

	# Prototype shortcut: the HUD restarts the level. A game flow node will own this later.
	if is_destroyed and Input.is_action_just_pressed(&"restart"):
		get_tree().reload_current_scene()


func _build_status_text() -> String:
	var lines := PackedStringArray()

	if ship_damage != null and ship_damage.is_destroyed:
		lines.append("*** SHIP DESTROYED ***   R: restart")
		lines.append("")

	if ship_damage != null:
		lines.append("Hull    %.0f%%" % [100.0 * ship_damage.get_hull_ratio()])

	lines.append("Speed   %.0f px/s" % ship.linear_velocity.length())
	lines.append("Power   %d / %d" % [generator.stored, generator.battery_capacity])

	if soft_points != null and soft_points.get_power_capacity() > 0.0:
		lines[lines.size() - 1] += "   + caps %d / %d" % [soft_points.get_power(), soft_points.get_power_capacity()]

	lines.append("Fuel    %d / %d" % [rooms.get_fuel(), rooms.get_fuel_capacity()])

	if soft_points != null and soft_points.get_fuel_capacity() > 0.0:
		lines[lines.size() - 1] += "   + drop %d / %d" % [soft_points.get_fuel(), soft_points.get_fuel_capacity()]
	lines.append("Smelter %d / %d cells" % [rooms.get_smelter_cells(), rooms.get_smelter_capacity()])
	lines.append("Ingots  %.1f / %d units" % [rooms.get_ingot_units(), rooms.get_ingot_capacity()])
	lines.append("Ore bin %d / %d cells" % [rooms.get_ore_bin_cells(), rooms.get_ore_bin_capacity()])
	lines.append("Ammo    %d loaded, %d / %d stored" % [hardpoints.get_loaded_ammo(), hardpoints.get_ammo(), hardpoints.get_ammo_capacity()])

	var by_ore := rooms.get_ore_aboard()

	for ore_id in by_ore:
		lines.append("  %-11s %.1f" % [CellMaterials.get_material(ore_id).display_name, by_ore[ore_id]])

	lines.append("Mass    %.1f" % ship.mass)
	lines.append("Balance x %.0f, y %.0f" % [ship.center_of_mass.x, ship.center_of_mass.y])
	lines.append("Door    %s%s" % ["OPEN" if hangar.is_open else "closed", ", JAMMED" if hangar.is_jammed() else ""])

	if grinder != null:
		lines.append("Grinder %s" % grinder.get_status_text())
	_append_soft_points(lines)
	_append_damaged_parts(lines)

	if balance_view != null and balance_view.visible:
		lines.append("")
		lines.append("Balance (each input alone)")
		lines.append_array(balance_view.get_role_report())

	lines.append("")
	lines.append("Space: hangar door    Esc: rooms, hardpoints, soft points")
	lines.append("1-4: soft points (tap / hold)    Mouse 4 / Alt: aim    B: balance view")

	if not _messages.is_empty():
		lines.append("")

		for entry in _messages:
			lines.append("> " + entry["text"])

	return "\n".join(lines)


func _append_soft_points(lines: PackedStringArray) -> void:
	if soft_points == null:
		return

	lines.append("")
	lines.append("Soft points")

	for i in soft_points.get_mount_count():
		var module := soft_points.get_module(i)
		var key := i + 1

		if module == null:
			lines.append("  %d %-10s  empty" % [key, soft_points.get_mount_name(i)])
			continue

		var line := "  %d %-10s  %s" % [key, soft_points.get_mount_name(i), module.get_type_name()]
		var status := module.get_status_text()
		var controls := module.get_controls_text()

		if not status.is_empty():
			line += ", " + status

		if not controls.is_empty():
			line += "   [" + controls + "]"

		lines.append(line)


# Only the parts that took damage, so the list stays short.
func _append_damaged_parts(lines: PackedStringArray) -> void:
	if ship_damage == null:
		return

	var damaged := PackedStringArray()

	for part in ship_damage.get_parts():
		var health := ShipDamage.get_health(part)

		if health.get_ratio() >= 1.0:
			continue

		var state := "BROKEN" if health.is_broken() else "%.0f%%" % [100.0 * health.get_ratio()]
		damaged.append("  %-20s %s" % [ShipDamage.get_part_name(part), state])

	if damaged.is_empty():
		return

	lines.append("")
	lines.append("Damaged parts")
	lines.append_array(damaged)


func _on_soft_point_message(mount_index: int, text: String) -> void:
	var prefix := "%d: " % [mount_index + 1] if mount_index >= 0 else ""
	_messages.append({ "text": prefix + text, "time_left": message_duration })

	while _messages.size() > max_messages:
		_messages.pop_front()


func _tick_messages(delta: float) -> void:
	var kept: Array[Dictionary] = []

	for entry in _messages:
		entry["time_left"] -= delta

		if entry["time_left"] > 0.0:
			kept.append(entry)

	_messages = kept


func _on_weapon_cooldown_blocked(weapon_name: String, time_left: float) -> void:
	if not show_debug_text:
		return # The cockpit's terminal reports it

	cooldown_label.text = "%s on cooldown (%.1f s)" % [weapon_name, time_left]
	cooldown_label.modulate.a = 1.0

	if flash_tween != null:
		flash_tween.kill()

	flash_tween = create_tween()
	flash_tween.tween_interval(flash_duration * 0.4)
	flash_tween.tween_property(cooldown_label, "modulate:a", 0.0, flash_duration * 0.6)
