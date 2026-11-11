class_name Cockpit
extends Control

# The Bucket's cockpit. Reads the ship's systems every frame and feeds the display widgets, which
# know nothing about the ship: another ship gets another cockpit scene, with the same widgets.
# Laid out on a 1280 x 720 design canvas (the mockups' size), scaled to fit the window and kept at
# the bottom centre. Art/cockpit_panels.png sits under the widgets, Art/cockpit_glass.png over them.

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const FREE_VIEW_TOP: float = 66.0 # Design px. Under the top corner panels
const FREE_VIEW_BOTTOM: float = 526.0 # Design px. Above the radar bezel, the dashboard's highest point
const MOUSE_BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_XBUTTON1: "M4",
	MOUSE_BUTTON_XBUTTON2: "M5",
}
const LOG_DIM_COLOR := "#3f7a2a" # Older terminal lines; the newest uses the label's own colour
const GARBLE_CHARACTERS := "#%&@$*=+/|<>?"

@export_group("Ship systems")
@export var ship: RigidBody2D
@export var generator: Generator
@export var rooms: ShipRooms
@export var hangar: Hangar
@export var grinder: Grinder
@export var soft_points: ShipSoftPoints
@export var hardpoints: ShipHardpoints
@export var ship_damage: ShipDamage
@export var computer: ShipComputer # Optional: its messages go to the terminal log
@export var dispatch: MothershipDispatch # Optional: its messages go to the terminal log
@export var speed_fx: SpeedFx # Optional: the speed readout flashes with its overspeed alerts

@export_group("Readouts")
@export var pixels_per_meter: float = 1.0 # Speeds show in m/s. Set the world's scale here once it's decided
@export var low_power_ratio: float = 0.25
@export var low_fuel_ratio: float = 0.2
@export var impact_flash_time: float = 1.5 # s. How long IMPACT stays lit after a hit
@export var overspeed_tint: Color = Color(1.25, 0.6, 0.45) # Speed readout at the peak of an overspeed alert
@export var log_lines: int = 3 # Messages kept on the terminal, under the two status lines

@export_group("Hits")
@export var hit_sensitivity: float = 2.5 # Disturbance = sqrt(share of hull lost) x this. 1% → 0.25, 16% → full
@export var max_garble: float = 0.5 # Share of terminal characters scrambled at full disturbance

var _log: PackedStringArray = []
var _impact_time_left: float = 0.0
var _last_hull: float = -1.0
var _was_grinding: bool = false
var _terminal_text: String = ""
var _base_position: Vector2 # Where _fit_to_viewport put us; the rattle shakes around it

@onready var speed_value: Label = %SpeedValue
@onready var spin_value: Label = %SpinValue
@onready var spin_unit: Label = %SpinUnit
@onready var impact_tile: HudAnnunciator = %ImpactTile
@onready var low_power_tile: HudAnnunciator = %LowPowerTile
@onready var low_fuel_tile: HudAnnunciator = %LowFuelTile
@onready var hardpoint_buttons: Array[HudHardpointButton] = [%HardpointButton1, %HardpointButton2]
@onready var mounts: Array[Control] = [%Mount1, %Mount2, %Mount3, %Mount4]
@onready var grind_led: HudLed = %GrindLed
@onready var smelt_led: HudLed = %SmeltLed
@onready var door_led: HudLed = %DoorLed
@onready var impact_led: HudLed = %ImpactLed
@onready var terminal: RichTextLabel = %Terminal
@onready var fuel_needle: HudNeedle = %FuelNeedle
@onready var fuel_value: Label = %FuelValue
@onready var power_needle: HudNeedle = %PowerNeedle
@onready var power_value: Label = %PowerValue
@onready var door_lever: HudLever = %DoorLever
@onready var door_key: Label = %DoorKey
@onready var radar: HudRadar = %Radar
@onready var loadout: HudLoadout = %Loadout
@onready var disturbance: CockpitDisturbance = %Disturbance


func _ready() -> void:
	assert(ship != null and generator != null and rooms != null and hangar != null, "Cockpit: assign the ship systems in the inspector")
	assert(grinder != null and soft_points != null and hardpoints != null and ship_damage != null, "Cockpit: assign the ship systems in the inspector")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()

	radar.ship = ship
	loadout.setup(ship, soft_points, hardpoints, ship_damage)
	refresh_key_texts()

	soft_points.message.connect(_on_soft_point_message)
	hardpoints.cooldown_blocked.connect(_on_cooldown_blocked)
	hardpoints.weapon_message.connect(_on_weapon_message)
	ship_damage.hull_changed.connect(_on_hull_changed)
	ship_damage.destroyed.connect(_on_destroyed)

	if computer != null:
		computer.message.connect(_add_log)

	if dispatch != null:
		dispatch.message.connect(_add_log)

	_last_hull = ship_damage.hull
	_setup_disturbance()


func _process(delta: float) -> void:
	_impact_time_left = maxf(_impact_time_left - delta, 0.0)

	_update_flight()
	_update_warnings()
	_update_hardpoints()
	_update_soft_points()
	_update_status()
	_update_gauges()
	_update_terminal()
	_update_disturbance()


# Key caps show the real bindings. Call again after the player remaps a key.
func refresh_key_texts() -> void:
	var hard_keys := PackedStringArray()

	for i in hardpoints.get_slot_count():
		hard_keys.append(get_key_text(hardpoints.get_fire_action(i)))

		if i < hardpoint_buttons.size():
			hardpoint_buttons[i].key_text = hard_keys[i]

	var soft_keys := PackedStringArray()

	for i in soft_points.get_mount_count():
		soft_keys.append(get_key_text(soft_points.get_action(i)))

		if i < mounts.size():
			(mounts[i].get_node(^"KeyLabel") as Label).text = soft_keys[i]

	loadout.hard_key_texts = hard_keys
	loadout.soft_key_texts = soft_keys
	door_key.text = get_key_text(&"toggle_hangar").to_upper()


static func get_key_text(action: StringName) -> String:
	if action.is_empty() or not InputMap.has_action(action):
		return "?"

	for event in InputMap.action_get_events(action):
		var mouse_event := event as InputEventMouseButton

		if mouse_event != null:
			return MOUSE_BUTTON_NAMES.get(mouse_event.button_index, "M%d" % mouse_event.button_index)

		var key_event := event as InputEventKey

		if key_event != null:
			var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
			return OS.get_keycode_string(keycode)

	return "?"


# --- Layout


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var fit := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)

	size = DESIGN_SIZE
	scale = Vector2(fit, fit)
	_base_position = Vector2((viewport_size.x - DESIGN_SIZE.x * fit) / 2.0, viewport_size.y - DESIGN_SIZE.y * fit)
	position = _base_position


## The band of the screen no panel covers, in screen px. Map markers stay inside it.
## Uses the resting position, so it doesn't shake with the cockpit.
func get_free_view_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	var top := _base_position.y + FREE_VIEW_TOP * scale.y
	var bottom := _base_position.y + FREE_VIEW_BOTTOM * scale.y

	return Rect2(0.0, top, viewport_size.x, bottom - top)


# Lights flicker dimmer; screens drop out almost completely. Mechanical parts (switches, lever,
# needles) don't flicker: the needles shake instead.
func _setup_disturbance() -> void:
	var lights: Array[CanvasItem] = [impact_tile, low_power_tile, low_fuel_tile, grind_led, smelt_led, door_led, impact_led]
	for button in hardpoint_buttons:
		lights.append(button)

	for mount in mounts:
		lights.append(mount.get_node(^"Led"))

	var screens: Array[CanvasItem] = [terminal, radar, loadout, speed_value, spin_value]
	disturbance.setup(lights, screens)


func _update_disturbance() -> void:
	disturbance.set_hull_ratio(ship_damage.get_hull_ratio())
	position = _base_position + disturbance.get_shake_offset() * scale
	radar.interference = disturbance.level
	fuel_needle.jitter = disturbance.level
	power_needle.jitter = disturbance.level


# --- Readouts


func _update_flight() -> void:
	var speed := ship.linear_velocity.length() / pixels_per_meter
	speed_value.text = "%03d" % mini(roundi(speed), 999)

	var alert := speed_fx.alert if speed_fx != null else 0.0
	speed_value.self_modulate = Color.WHITE.lerp(overspeed_tint, alert)

	var spin := rad_to_deg(ship.angular_velocity) # Positive turns clockwise on screen
	spin_value.text = "%d" % absi(roundi(spin))

	if spin > 0.5:
		spin_unit.text = "°/s ↻"
	elif spin < -0.5:
		spin_unit.text = "°/s ↺"
	else:
		spin_unit.text = "°/s"


func _update_warnings() -> void:
	var power_ratio := generator.get_ratio()
	low_power_tile.state = _get_warning_state(power_ratio, low_power_ratio)

	var fuel_capacity := rooms.get_fuel_capacity() + soft_points.get_fuel_capacity()
	var fuel_ratio := (rooms.get_fuel() + soft_points.get_fuel()) / fuel_capacity if fuel_capacity > 0.0 else 0.0
	low_fuel_tile.state = _get_warning_state(fuel_ratio, low_fuel_ratio)

	var is_hit := ship_damage.is_destroyed or _impact_time_left > 0.0
	impact_tile.state = HudAnnunciator.State.ALARM if is_hit else HudAnnunciator.State.OFF


func _get_warning_state(ratio: float, threshold: float) -> HudAnnunciator.State:
	if ratio <= 0.0:
		return HudAnnunciator.State.ALARM

	if ratio < threshold:
		return HudAnnunciator.State.CAUTION

	return HudAnnunciator.State.OFF


func _update_hardpoints() -> void:
	for i in hardpoint_buttons.size():
		var button := hardpoint_buttons[i]
		button.visible = i < hardpoints.get_slot_count()

		if not button.visible:
			continue

		var weapon := hardpoints.get_weapon(i)

		if weapon == null:
			button.state = HudHardpointButton.State.EMPTY
			continue

		button.title = weapon.get_button_title().to_upper()
		button.cooldown = weapon.get_cooldown_ratio()

		if weapon.get_part_health().is_broken():
			button.state = HudHardpointButton.State.BROKEN
		elif weapon.is_out_of_ammo():
			button.title = "NO AMMO"
			button.cooldown = 1.0 # Dark, nothing refilling
			button.state = HudHardpointButton.State.COOLDOWN
		elif button.cooldown > 0.0:
			button.state = HudHardpointButton.State.COOLDOWN
		elif Input.is_action_pressed(hardpoints.get_fire_action(i)):
			button.state = HudHardpointButton.State.FIRING
		else:
			button.state = HudHardpointButton.State.READY


func _update_soft_points() -> void:
	for i in mounts.size():
		var mount := mounts[i]
		mount.visible = i < soft_points.get_mount_count()

		if not mount.visible:
			continue

		var led := mount.get_node(^"Led") as HudLed
		var toggle := mount.get_node(^"Toggle") as HudToggle
		var tape := mount.get_node(^"Tape") as HudTapeText
		var module := soft_points.get_module(i)

		toggle.is_empty = module == null

		if module == null:
			led.state = HudLed.State.OFF
			tape.text = "EMPTY"
			continue

		tape.text = module.get_type_name().to_upper()
		toggle.has_guard = module.can_jettison
		toggle.is_on = module.is_engaged()

		if module.get_part_health().is_broken():
			led.state = HudLed.State.ALARM
		elif toggle.is_on:
			led.state = HudLed.State.ACTIVE
		else:
			led.state = HudLed.State.READY


func _update_status() -> void:
	grind_led.state = HudLed.State.ACTIVE if grinder.is_working else HudLed.State.OFF
	smelt_led.state = HudLed.State.ACTIVE if rooms.get_smelter_cells() > 0 else HudLed.State.OFF
	impact_led.state = HudLed.State.ALARM if _impact_time_left > 0.0 else HudLed.State.OFF

	if hangar.is_jammed():
		door_led.state = HudLed.State.ALARM
	elif hangar.is_open:
		door_led.state = HudLed.State.ACTIVE
	else:
		door_led.state = HudLed.State.OFF

	door_lever.open_amount = hangar.open_amount

	if grinder.is_working and not _was_grinding:
		_add_log("Grinder: cutting")

	_was_grinding = grinder.is_working


func _update_gauges() -> void:
	var fuel_capacity := rooms.get_fuel_capacity()
	fuel_needle.value = rooms.get_fuel() / fuel_capacity if fuel_capacity > 0.0 else 0.0

	if soft_points.get_fuel_capacity() > 0.0:
		fuel_value.text = "%d +%d DROP" % [roundi(rooms.get_fuel()), roundi(soft_points.get_fuel())]
	else:
		fuel_value.text = "%d / %d" % [roundi(rooms.get_fuel()), roundi(fuel_capacity)]

	power_needle.value = generator.get_ratio()
	power_value.text = "%d / %d" % [roundi(generator.stored), roundi(generator.battery_capacity)]

	if soft_points.get_power_capacity() > 0.0:
		power_value.text += " +%d" % roundi(soft_points.get_power())


func _update_terminal() -> void:
	var lines := PackedStringArray()
	var garble := disturbance.level * max_garble

	if rooms.has_ore_bin():
		lines.append(_dim(_garble("> BIN %d/%d" % [rooms.get_ore_bin_cells(), rooms.get_ore_bin_capacity()], garble)))

	if rooms.get_ingot_capacity() > 0.0:
		lines.append(_dim(_garble("> INGOT %d/%d" % [roundi(rooms.get_ingot_units()), roundi(rooms.get_ingot_capacity())], garble)))

	if rooms.get_smelter_capacity() > 0:
		lines.append(_dim(_garble("> SMELT %d/%d" % [rooms.get_smelter_cells(), rooms.get_smelter_capacity()], garble)))

	if hardpoints.get_magazine_capacity() > 0:
		var ammo_line := "> AMMO %d/%d +%d" % [hardpoints.get_loaded_ammo(), hardpoints.get_magazine_capacity(), hardpoints.get_ammo()]
		lines.append(_dim(_garble(ammo_line, garble)))

	for i in _log.size():
		var line := _garble("> " + _log[i], garble).replace("[", "[lb]")
		lines.append(line if i == _log.size() - 1 else _dim(line))

	var text := "\n".join(lines)

	if text != _terminal_text:
		_terminal_text = text
		terminal.text = text


# Scrambles a share of the characters, like a terminal losing sync. Spaces are left alone so the
# lines keep their shape.
func _garble(line: String, amount: float) -> String:
	if amount <= 0.0:
		return line

	var garbled := line

	for i in garbled.length():
		if garbled[i] != " " and randf() < amount:
			garbled[i] = GARBLE_CHARACTERS[randi() % GARBLE_CHARACTERS.length()]

	return garbled


func _dim(line: String) -> String:
	return "[color=%s]%s[/color]" % [LOG_DIM_COLOR, line]


func _add_log(text: String) -> void:
	_log.append(text)

	while _log.size() > log_lines:
		_log.remove_at(0)


# --- Signals


func _on_soft_point_message(mount_index: int, text: String) -> void:
	var prefix := "%d: " % [mount_index + 1] if mount_index >= 0 else ""
	_add_log(prefix + text)


# Clicking again during a cooldown updates the last line instead of filling the log.
func _on_cooldown_blocked(weapon_name: String, time_left: float) -> void:
	var prefix := "%s: cooldown" % weapon_name
	var text := "%s %.1f s" % [prefix, time_left]

	if not _log.is_empty() and _log[_log.size() - 1].begins_with(prefix):
		_log[_log.size() - 1] = text
		return

	_add_log(text)


func _on_weapon_message(weapon_name: String, text: String) -> void:
	_add_log("%s: %s" % [weapon_name, text])


func _on_hull_changed() -> void:
	var lost := _last_hull - ship_damage.hull
	_last_hull = ship_damage.hull

	if lost <= 0.0 or ship_damage.max_hull <= 0.0:
		return

	var share := lost / ship_damage.max_hull
	_impact_time_left = impact_flash_time
	disturbance.hit(clampf(sqrt(share) * hit_sensitivity, 0.0, 1.0))
	_add_log("IMPACT  hull -%d%%" % maxi(roundi(share * 100.0), 1))


func _on_destroyed() -> void:
	disturbance.lose_power()
	_add_log("POWER FAILURE")
