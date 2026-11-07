extends CanvasLayer

@export var hardpoints: ShipHardpoints
@export var flash_duration: float = 1.2

@export_group("Ship status")
@export var ship: RigidBody2D
@export var generator: Generator
@export var rooms: ShipRooms
@export var hangar: Hangar
@export var grinder: Grinder
@export var soft_points: ShipSoftPoints
@export var balance_view: BalanceView # Its per-input report shows while it's visible

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
	status_label.text = _build_status_text()


func _build_status_text() -> String:
	var lines := PackedStringArray()
	lines.append("Power   %d / %d" % [generator.stored, generator.battery_capacity])

	if soft_points != null and soft_points.get_power_capacity() > 0.0:
		lines[lines.size() - 1] += "   + caps %d / %d" % [soft_points.get_power(), soft_points.get_power_capacity()]

	lines.append("Fuel    %d / %d" % [rooms.get_fuel(), rooms.get_fuel_capacity()])

	if soft_points != null and soft_points.get_fuel_capacity() > 0.0:
		lines[lines.size() - 1] += "   + drop %d / %d" % [soft_points.get_fuel(), soft_points.get_fuel_capacity()]
	lines.append("Smelter %d / %d cells" % [rooms.get_smelter_cells(), rooms.get_smelter_capacity()])
	lines.append("Cargo   %.1f / %d units" % [rooms.get_cargo_cells(), rooms.get_cargo_capacity_cells()])

	var by_ore := rooms.get_cargo_by_ore()

	for ore_id in by_ore:
		lines.append("  %-11s %.1f" % [CellMaterials.get_material(ore_id).display_name, by_ore[ore_id]])

	lines.append("Mass    %.1f" % ship.mass)
	lines.append("Balance x %.0f, y %.0f" % [ship.center_of_mass.x, ship.center_of_mass.y])
	lines.append("Door    %s" % ["OPEN" if hangar.is_open else "closed"])

	if grinder != null:
		lines.append("Grinder %s" % grinder.get_status_text())
	_append_soft_points(lines)

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
	cooldown_label.text = "%s on cooldown (%.1f s)" % [weapon_name, time_left]
	cooldown_label.modulate.a = 1.0

	if flash_tween != null:
		flash_tween.kill()

	flash_tween = create_tween()
	flash_tween.tween_interval(flash_duration * 0.4)
	flash_tween.tween_property(cooldown_label, "modulate:a", 0.0, flash_duration * 0.6)
