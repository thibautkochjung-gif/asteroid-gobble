class_name NetLauncher
extends HardpointWeapon

# Fires a very wide net on a cable (NetShot). Whatever it touches, it catches, and then it closes
# around its catch: one solid bundle (NetBundle) at the end of the cable.
# The cable is a rope (SoftLink): slack until stretched, then it pulls both ends. Tow a bundle
# around, reel it in, park it in tow and fire another net. Rough handling tears the net: over
# break_force, the bundle opens and the rocks drift free. Nets are unlimited, but the next one
# takes reload_time to fold in.
# Controls:
# - net ready: hold fire to aim (the launcher follows the mouse inside aim_arc_degrees), release
#   to fire. A released net waits for the launcher to reach the mouse;
# - net flying: press fire to close it now, on what it holds;
# - bundle on the cable: hold fire to reel in, tap fire to let it go (the net opens);
# - tow key (net_tow): put the bundle on the cable in tow and fold the next net. Its cable's ship
#   end slides back to a hitch at the stern (anchor_move_time). With nothing on the cable, the key
#   takes the last towed bundle back onto the winch, to reel it in or let it go;
# - release key (net_release): let go of the last towed bundle (its net opens). With nothing in
#   tow, it lets go of the bundle on the cable.
# A prompt (NetPrompt) shows the tow and release keys next to the bundles.
# The hold only takes loose rocks: to load a bundle, open the net next to the hangar.
#
# Cables are dictionaries: { "bundle", "point" (knot, local to the bundle), "length",
# "hitch" (ship-local, towed cables only), "from" (ship-local, where the ship end started its last
# move), "blend" (0..1 along that move) }.

const TEXEL: float = 2.0
const RELEASE_ACTION: StringName = &"net_release"
const HITCH_OFFSETS: Array[float] = [-14.0, 14.0, 0.0] # Across the stern, one per tow

@export var shot_speed: float = 300.0 # px/s, relative to the ship
@export var net_width: float = 400.0 # px, fully open. About two lengths of the starter ship
@export var max_range: float = 450.0
@export var reload_time: float = 2.0 # s to fold the next net
@export var max_tows: int = 3

@export_group("Cable")
@export var stiffness: float = 20.0 # 1/s². See SoftLink
@export var damping: float = 6.0 # 1/s
@export var break_force: float = 25000.0 # mass * px/s². Over this, the net tears
@export var reel_speed: float = 40.0 # px/s
@export var min_length: float = 30.0 # Reeling in stops here
@export var tap_time: float = 0.25 # s. Released sooner: a tap (let go). Held longer: reeling
@export var anchor_move_time: float = 0.8 # s for a cable's ship end to slide between the winch and the stern
@export var hitch_margin: float = 2.0 # px behind the hull's rearmost point

@export_group("Look")
@export var drum_color: Color = Color(0.54, 0.5, 0.45)
@export var net_color: Color = Color(0.83, 0.64, 0.16)
@export var cable_color: Color = Color(0.72, 0.68, 0.6)
@export var outline_color: Color = Color(0.06, 0.055, 0.07)
@export var preview_color: Color = Color(0.83, 0.64, 0.16, 0.35)

var shot: NetShot # In flight
var tether: Dictionary = {} # The cable on the winch. Empty if none
var tows: Array[Dictionary] = [] # Cables tied to the stern

var is_aiming: bool = false
var is_reeling: bool = false

var _fire_queued: bool = false # Released before the launcher reached the mouse: fires when it does

var _press_time: float = -1.0 # s the fire button has been held, while a bundle is on the winch
var _reload_left: float = 0.0
var _stern_x: float = NAN # Ship-local x of the hull's rearmost point, found once


func _ready() -> void:
	var layer := CanvasLayer.new() # Screen space, whatever the ship's rotation
	add_child(layer)

	var prompt := NetPrompt.new()
	prompt.launcher = self
	layer.add_child(prompt)


func _process(delta: float) -> void:
	_reload_left = maxf(_reload_left - delta, 0.0)
	_handle_fire(delta)
	_update_aim_for_state(delta)

	if Input.is_action_just_pressed(TOW_ACTION):
		_on_tow_pressed()

	if Input.is_action_just_pressed(RELEASE_ACTION):
		_on_release_pressed()

	queue_redraw()


func _physics_process(delta: float) -> void:
	if not tether.is_empty():
		if is_reeling:
			var ratio := get_performance()
			tether["length"] = maxf(tether["length"] - reel_speed * delta * ratio, min_length)

		if not _pull(tether, delta):
			tether = {}
			is_reeling = false
			_start_reload()

	for tow in tows.duplicate():
		if not _pull(tow, delta):
			tows.erase(tow)


func _exit_tree() -> void:
	if is_instance_valid(shot):
		shot.queue_free()


func get_button_title() -> String:
	if not tether.is_empty():
		return "REEL"

	if tows.is_empty():
		return "NET"

	return "NET T%d" % tows.size()


func get_cooldown_ratio() -> float:
	return _reload_left / reload_time if reload_time > 0.0 else 0.0


func is_loaded() -> bool:
	return _reload_left <= 0.0 and shot == null and tether.is_empty()


func can_tow() -> bool:
	return not tether.is_empty() and tows.size() < max_tows


# Where a cable meets the ship, in global coordinates. Slides between the winch and its hitch.
func get_anchor(cable: Dictionary) -> Vector2:
	var goal := _get_anchor_goal(cable)
	var blend: float = cable.get("blend", 1.0)

	if blend >= 1.0:
		return ship.to_global(goal)

	var from: Vector2 = cable["from"]
	return ship.to_global(from.lerp(goal, smoothstep(0.0, 1.0, blend)))


# The name of the key bound to an action, for prompts ("T").
static func get_key_label(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey

		if key != null:
			var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
			return OS.get_keycode_string(code)

	return "?"


# --- Controls


func _handle_fire(delta: float) -> void:
	if not tether.is_empty():
		_handle_tethered_fire(delta)
		return

	if Input.is_action_just_pressed(fire_action) and not _fire_queued:
		if is_instance_valid(shot):
			shot.close_now()
		elif _reload_left > 0.0:
			cooldown_blocked.emit(_reload_left)
		elif get_performance() > 0.0:
			is_aiming = true

	if is_aiming and Input.is_action_just_released(fire_action):
		_fire_queued = true

	if _fire_queued and is_on_target():
		is_aiming = false
		_fire_queued = false
		_fire()


# Follows the mouse while aiming, swings back to the slot's axis otherwise (net out, cable on).
func _update_aim_for_state(delta: float) -> void:
	if is_aiming:
		update_aim(delta)
	else:
		reset_aim(delta)


# Hold: reel in. Tap: let go.
func _handle_tethered_fire(delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		_press_time = 0.0

	if _press_time < 0.0:
		return

	_press_time += delta
	is_reeling = _press_time >= tap_time and Input.is_action_pressed(fire_action)

	if Input.is_action_just_released(fire_action):
		if _press_time < tap_time:
			_let_go()

		_press_time = -1.0
		is_reeling = false


func _on_tow_pressed() -> void:
	if not tether.is_empty():
		if tows.size() >= max_tows:
			message.emit("tow full (%d)" % max_tows)
			return

		_move_anchor(tether, _get_free_hitch())
		tows.append(tether)
		tether = {}
		is_reeling = false
		_press_time = -1.0
		message.emit("bundle in tow (%d)" % tows.size())
		_start_reload()
	elif not tows.is_empty() and shot == null:
		tether = tows.pop_back()
		_move_anchor(tether, null)
		_press_time = -1.0
		message.emit("bundle back on the winch")


func _on_release_pressed() -> void:
	if not tows.is_empty():
		var cable: Dictionary = tows.pop_back()
		var bundle: NetBundle = cable["bundle"]

		if is_instance_valid(bundle):
			bundle.release_all()

		message.emit("tow released")
	elif not tether.is_empty():
		_let_go()


# --- Net


func _fire() -> void:
	var forward := get_forward()
	shot = NetShot.new()
	shot.velocity = get_ship_velocity_at(muzzle.global_position) + forward * shot_speed
	shot.full_width = net_width
	shot.max_range = max_range
	shot.closed.connect(_on_net_closed)
	get_tree().current_scene.add_child(shot)
	shot.global_position = muzzle.global_position


func _on_net_closed(bundle: NetBundle) -> void:
	shot = null

	if bundle == null:
		message.emit("net came back empty")
		_start_reload()
		return

	var knot := _get_knot(bundle)
	tether = { "bundle": bundle, "point": bundle.to_local(knot), "length": muzzle.global_position.distance_to(knot) }
	message.emit("caught %d rocks" % bundle.rocks.size())


# Where the cable ties onto the bundle: the point of its rocks closest to the ship.
func _get_knot(bundle: NetBundle) -> Vector2:
	var best := bundle.global_position
	var best_distance := INF

	for rock in bundle.rocks:
		var point := rock.get_closest_point(muzzle.global_position)
		var distance := point.distance_to(muzzle.global_position)

		if distance < best_distance:
			best_distance = distance
			best = point

	return best


func _let_go() -> void:
	var bundle: NetBundle = tether.get("bundle")
	tether = {}
	is_reeling = false

	if is_instance_valid(bundle):
		bundle.release_all()

	message.emit("net opened")
	_start_reload()


func _start_reload() -> void:
	_reload_left = reload_time / maxf(get_performance(), PartHealth.BROKEN_RATIO)


# --- Cable ends


# Starts sliding the cable's ship end toward a hitch (ship-local), or back to the winch (null).
func _move_anchor(cable: Dictionary, hitch: Variant) -> void:
	cable["from"] = ship.to_local(get_anchor(cable))
	cable["blend"] = 0.0

	if hitch == null:
		cable.erase("hitch")
	else:
		cable["hitch"] = hitch


# Ship-local: the hitch for a towed cable, the muzzle for the one on the winch.
func _get_anchor_goal(cable: Dictionary) -> Vector2:
	if cable.has("hitch"):
		return cable["hitch"]

	return ship.to_local(muzzle.global_position)


# The first stern hitch no towed cable uses.
func _get_free_hitch() -> Vector2:
	var stern := _get_stern_x()

	for offset in HITCH_OFFSETS:
		var hitch := Vector2(stern, offset)
		var is_used := false

		for tow in tows:
			if tow.get("hitch", Vector2.INF) == hitch:
				is_used = true

		if not is_used:
			return hitch

	return Vector2(stern, 0.0)


# The hull's rearmost point (ship-local x), from the ship's collision shapes, arm tools left out.
func _get_stern_x() -> float:
	if not is_nan(_stern_x):
		return _stern_x

	_stern_x = 0.0

	for owner_id in ship.get_shape_owners():
		if ship.shape_owner_get_owner(owner_id) is RobotArm:
			continue

		var placement := ship.shape_owner_get_transform(owner_id)

		for i in ship.shape_owner_get_shape_count(owner_id):
			var area := ship.shape_owner_get_shape(owner_id, i).get_rect()

			for corner in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
				_stern_x = minf(_stern_x, (placement * corner).x)

	_stern_x -= hitch_margin
	return _stern_x


# Rope physics for one cable. Returns false once it's gone (bundle emptied, or the net tore).
# While the ship end slides, the cable pays out as needed so the slide never yanks the bundle.
func _pull(cable: Dictionary, delta: float) -> bool:
	var bundle: NetBundle = cable["bundle"]

	if not is_instance_valid(bundle) or bundle.is_queued_for_deletion():
		return false

	var knot := bundle.to_global(cable["point"])

	if cable.get("blend", 1.0) < 1.0:
		cable["blend"] = minf(cable["blend"] + delta / anchor_move_time, 1.0)
		cable["length"] = maxf(cable["length"], get_anchor(cable).distance_to(knot))

	var force := SoftLink.apply_spring(ship, get_anchor(cable), bundle, knot, cable["length"], stiffness, damping, true)

	if force > break_force:
		bundle.release_all()
		message.emit("the net tore!")
		Fx.shake(0.3)
		return false

	return true


# --- Look


func _draw() -> void:
	_draw_body()

	var tip := muzzle.position

	if is_aiming:
		var side := Vector2(0.0, net_width * 0.5)
		var far := tip + Vector2(max_range, 0.0)
		draw_dashed_line(tip, far, preview_color, 1.0, 6.0)
		draw_dashed_line(far - side, far + side, preview_color, 1.0, 6.0)

	if is_instance_valid(shot):
		_draw_cable(tip, to_local(shot.global_position), false)

	if not tether.is_empty():
		_draw_cable(to_local(get_anchor(tether)), to_local(tether["bundle"].to_global(tether["point"])), is_reeling)

	for tow in tows:
		if is_instance_valid(tow["bundle"]):
			_draw_cable(to_local(get_anchor(tow)), to_local(tow["bundle"].to_global(tow["point"])), false)


func _draw_cable(start: Vector2, end: Vector2, is_tight: bool) -> void:
	draw_line(start, end, outline_color, TEXEL)
	draw_line(start, end, net_color if is_tight else cable_color, TEXEL * 0.5)


# A drum with the folded net on it. The net shows only when one is loaded.
func _draw_body() -> void:
	var drum := Rect2(-TEXEL * 2.0, -TEXEL * 3.5, muzzle.position.x + TEXEL * 2.0, TEXEL * 7.0)
	draw_rect(drum, outline_color)
	draw_rect(drum.grow(-TEXEL * 0.5), drum_color)

	if is_loaded():
		var bundle := Rect2(TEXEL, -TEXEL * 2.5, muzzle.position.x - TEXEL * 2.0, TEXEL * 5.0)
		draw_rect(bundle, net_color.darkened(0.2))

		for i in int(bundle.size.x / (TEXEL * 2.0)):
			var x := bundle.position.x + TEXEL * (i * 2.0 + 0.5)
			draw_line(Vector2(x, bundle.position.y), Vector2(x + TEXEL, bundle.end.y), net_color.lightened(0.2), 1.0)
