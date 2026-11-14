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
const HISTORY_LINES: int = 200 # Radio log lines kept for the ship menu
const GARBLE_CHARACTERS := "#%&@$*=+/|<>?"
const KEY_HINTS_RECT := Rect2(240.0, 474.0, 800.0, 48.0) # Design px. Just above the radar bezel, inside the free view

@export_group("Ship systems")
@export var ship: RigidBody2D
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
@export_range(0.0, 1.0) var cargo_caution_ratio: float = 0.85 # CARGO tile turns amber when the fullest store passes this; red when it's full
@export var low_fuel_ratio: float = 0.2
@export var impact_flash_time: float = 1.5 # s. How long IMPACT stays lit after a hit
@export var overspeed_tint: Color = Color(1.25, 0.6, 0.45) # Speed readout at the peak of an overspeed alert
@export var log_lines: int = 3 # Messages kept on the terminal, under the two status lines

@export_group("Hits")
@export var hit_sensitivity: float = 2.5 # Disturbance = sqrt(share of hull lost above impact_min_share) x this
@export_range(0.0, 0.1) var impact_min_share: float = 0.0025 # Share of the hull a hit must take to rattle the cockpit, light IMPACT and log. Slow bumps stay quiet
@export var max_garble: float = 0.5 # Share of terminal characters scrambled at full disturbance

var _log: PackedStringArray = []
var _impact_time_left: float = 0.0
var _last_hull: float = -1.0
var _was_grinding: bool = false
var _terminal_text: String = ""
var _history: Array[String] = [] # See get_history()
var _run_time: float = 0.0 # s since the cockpit appeared. Stops while the game is paused
var _base_position: Vector2 # Where _fit_to_viewport put us; the rattle shakes around it
var _key_hints: HudKeyHints

@onready var speed_value: Label = %SpeedValue
@onready var spin_value: Label = %SpinValue
@onready var spin_unit: Label = %SpinUnit
@onready var impact_tile: HudAnnunciator = %ImpactTile
@onready var cargo_tile: HudAnnunciator = %CargoTile
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
@onready var cargo_needle: HudNeedle = %CargoNeedle
@onready var cargo_value: Label = %CargoValue
@onready var door_lever: HudLever = %DoorLever
@onready var door_key: Label = %DoorKey
@onready var radar: HudRadar = %Radar
@onready var loadout: HudLoadout = %Loadout
@onready var disturbance: CockpitDisturbance = %Disturbance
@onready var hardpoints_title: Label = $HardpointsTitle


# The panel has two sockets. A ship with more hardpoints gets them split into a grid of short
# buttons, in slot order: row by row, left to right.
func _add_hardpoint_buttons() -> void:
	var count := hardpoints.get_slot_count()

	if count <= hardpoint_buttons.size():
		return

	var area := Rect2(hardpoint_buttons[0].position, Vector2.ZERO).merge(Rect2(hardpoint_buttons[-1].position, hardpoint_buttons[-1].size))
	var columns := hardpoint_buttons.size()
	var rows := ceili(float(count) / columns)
	var gap := 2.0
	var cell := Vector2((area.size.x - gap * (columns - 1)) / columns, (area.size.y - gap * (rows - 1)) / rows)

	while hardpoint_buttons.size() < count:
		var button := hardpoint_buttons[0].duplicate() as HudHardpointButton
		hardpoint_buttons[-1].add_sibling(button) # Right after the others: under the glass, like them
		hardpoint_buttons.append(button)

	for i in count:
		var button := hardpoint_buttons[i]
		button.position = area.position + Vector2(i % columns, floori(i / float(columns))) * (cell + Vector2(gap, gap))
		button.size = cell


# The panel has four mount sockets. A ship with more soft points gets all of them in the same strip,
# shrunk to fit, in mount order.
func _add_mounts() -> void:
	var count := soft_points.get_mount_count()

	if count <= mounts.size():
		return

	var area := Rect2(mounts[0].position, Vector2.ZERO).merge(Rect2(mounts[-1].position, mounts[-1].size))
	var pitch := mounts[1].position.x - mounts[0].position.x
	var shrink := area.size.x / (pitch * (count - 1) + mounts[0].size.x)

	while mounts.size() < count:
		var mount := mounts[0].duplicate() as Control
		mounts[-1].add_sibling(mount) # Right after the others, like the hardpoint buttons
		mounts.append(mount)

	for i in count:
		var mount := mounts[i]
		mount.scale = Vector2(shrink, shrink)
		mount.position = area.position + Vector2(i * pitch * shrink, area.size.y * (1.0 - shrink) * 0.5)


func _ready() -> void:
	assert(ship != null and rooms != null and hangar != null, "Cockpit: assign the ship systems in the inspector")
	assert(grinder != null and soft_points != null and hardpoints != null and ship_damage != null, "Cockpit: assign the ship systems in the inspector")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()

	radar.ship = ship
	loadout.setup(ship, soft_points, hardpoints, ship_damage)
	_add_hardpoint_buttons()
	_add_mounts()
	_add_key_hints()
	refresh_key_texts()

	soft_points.message.connect(_on_soft_point_message)
	hardpoints.cooldown_blocked.connect(_on_cooldown_blocked)
	hardpoints.weapon_message.connect(_on_weapon_message)
	hardpoints.active_pair_changed.connect(_on_active_pair_changed)
	_on_active_pair_changed(hardpoints.active_pair)
	ship_damage.hull_changed.connect(_on_hull_changed)
	ship_damage.destroyed.connect(_on_destroyed)

	if computer != null:
		computer.message.connect(_add_log)

	if dispatch != null:
		dispatch.message.connect(_add_log)

	_last_hull = ship_damage.hull
	_setup_disturbance()


func _process(delta: float) -> void:
	_run_time += delta
	_impact_time_left = maxf(_impact_time_left - delta, 0.0)

	_update_flight()
	_update_warnings()
	_update_hardpoints()
	_update_soft_points()
	_update_key_hints()
	_update_status()
	_update_gauges()
	_update_terminal()
	_update_disturbance()


# Key caps show the real bindings. Call again after the player remaps a key.
func refresh_key_texts() -> void:
	var hard_keys := PackedStringArray()

	for i in hardpoints.get_slot_count():
		hard_keys.append(get_key_text(hardpoints.get_trigger_action(i)))

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
	var lights: Array[CanvasItem] = [impact_tile, cargo_tile, low_fuel_tile, grind_led, smelt_led, door_led, impact_led]
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
	cargo_needle.jitter = disturbance.level


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
	var cargo_ratio := _get_cargo_ratio()

	if cargo_ratio >= 1.0:
		cargo_tile.state = HudAnnunciator.State.ALARM
	elif cargo_ratio >= cargo_caution_ratio:
		cargo_tile.state = HudAnnunciator.State.CAUTION
	else:
		cargo_tile.state = HudAnnunciator.State.OFF

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


# Lights the active pair's buttons, and says on the panel which pair it is and how to switch.
func _on_active_pair_changed(pair: int) -> void:
	for i in hardpoint_buttons.size():
		hardpoint_buttons[i].selected = hardpoints.is_slot_active(i)
		hardpoint_buttons[i].pair_marker = hardpoints.get_pair_count() > 1

	if hardpoints.get_pair_count() > 1:
		hardpoints_title.text = "HARDPOINTS %d/%d  %s" % [pair + 1, hardpoints.get_pair_count(), get_key_text(ShipHardpoints.SWITCH_ACTION)]
	else:
		hardpoints_title.text = "HARDPOINTS"


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


# Over everything else (the glass included): it's a prompt, not a panel.
func _add_key_hints() -> void:
	_key_hints = HudKeyHints.new()
	_key_hints.position = KEY_HINTS_RECT.position
	_key_hints.size = KEY_HINTS_RECT.size
	add_child(_key_hints)


# Shows the keys of the first bolted rock bolter: swing in, swing out, let go.
func _update_key_hints() -> void:
	var hints: Array[Dictionary] = []

	for i in soft_points.get_mount_count():
		var bolter := soft_points.get_module(i) as RockBolter

		if bolter == null or bolter.state != RockBolter.State.LOCKED:
			continue

		var swing_in := bolter.is_swinging and Input.is_action_pressed(RockBolter.SWING_IN_ACTION)
		var swing_out := bolter.is_swinging and Input.is_action_pressed(RockBolter.SWING_OUT_ACTION)
		hints.append({ "key": get_key_text(RockBolter.SWING_IN_ACTION), "text": "NOSE IN", "lit": swing_in })
		hints.append({ "key": get_key_text(RockBolter.SWING_OUT_ACTION), "text": "NOSE OUT", "lit": swing_out })
		hints.append({ "key": get_key_text(soft_points.get_action(i)), "text": "LET GO", "lit": false })
		_key_hints.title = "ROCK BOLTER  SWING %+d°" % roundi(bolter.swing)
		break

	_key_hints.hints = hints


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

	var cargo_ratio := _get_cargo_ratio()
	cargo_needle.value = cargo_ratio
	cargo_value.text = "%d%%" % roundi(cargo_ratio * 100.0)


# How full the fullest store is: ore bins or ingot holds, whichever is closer to full. That's
# the one that stops the work when it fills (the grinder or the smelter waits).
func _get_cargo_ratio() -> float:
	var ratio := 0.0

	if rooms.get_ore_bin_capacity() > 0:
		ratio = float(rooms.get_ore_bin_cells()) / rooms.get_ore_bin_capacity()

	if rooms.get_ingot_capacity() > 0.0:
		ratio = maxf(ratio, rooms.get_ingot_units() / rooms.get_ingot_capacity())

	return clampf(ratio, 0.0, 1.0)


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


# Every terminal line of the run, with the run time, for the ship menu's radio log.
func get_history() -> Array[String]:
	return _history


func _add_log(text: String) -> void:
	_log.append(text)
	var seconds := floori(_run_time)
	_history.append("%02d:%02d  %s" % [floori(_run_time / 60.0), seconds % 60, text])

	while _history.size() > HISTORY_LINES:
		_history.remove_at(0)

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

	if share < impact_min_share and not ship_damage.is_destroyed:
		return # A nudge: the hull still loses it, the cockpit doesn't make a scene

	_impact_time_left = impact_flash_time
	disturbance.hit(clampf(sqrt(share - impact_min_share) * hit_sensitivity, 0.0, 1.0))
	_add_log("IMPACT  hull -%d%%" % maxi(roundi(share * 100.0), 1))


func _on_destroyed() -> void:
	disturbance.lose_power()
	_add_log("POWER FAILURE")
